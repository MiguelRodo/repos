package sysutil

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// fileCompareBufferSize keeps reads reasonably large while avoiding oversized
// allocations during repeated file comparisons.
const fileCompareBufferSize = 32 * 1024

// MirrorOptions controls mirror behaviour.
type MirrorOptions struct {
	DeleteExtraneous bool
}

// MirrorPath mirrors src into dst, preserving file permissions.
// It supports regular files, directories, and symlinks.
func MirrorPath(src, dst string, opts MirrorOptions) (bool, error) {
	srcInfo, err := os.Lstat(src)
	if err != nil {
		return false, fmt.Errorf("stat source %s: %w", src, err)
	}

	if srcInfo.IsDir() {
		return mirrorDir(src, dst, srcInfo.Mode().Perm(), opts)
	}
	if srcInfo.Mode()&os.ModeSymlink != 0 {
		return mirrorSymlink(src, dst)
	}
	if !srcInfo.Mode().IsRegular() {
		return false, fmt.Errorf("unsupported source type: %s", src)
	}
	return mirrorFile(src, dst, srcInfo.Mode().Perm())
}

func mirrorDir(srcDir, dstDir string, srcPerm os.FileMode, opts MirrorOptions) (bool, error) {
	changed := false

	dstInfo, err := os.Lstat(dstDir)
	if err != nil {
		if !os.IsNotExist(err) {
			return false, fmt.Errorf("stat destination %s: %w", dstDir, err)
		}
		if err := os.MkdirAll(dstDir, srcPerm); err != nil {
			return false, fmt.Errorf("create directory %s: %w", dstDir, err)
		}
		changed = true
	} else {
		if !dstInfo.IsDir() {
			if err := os.RemoveAll(dstDir); err != nil {
				return false, fmt.Errorf("replace non-directory destination %s: %w", dstDir, err)
			}
			if err := os.MkdirAll(dstDir, srcPerm); err != nil {
				return false, fmt.Errorf("create directory %s: %w", dstDir, err)
			}
			changed = true
		} else if dstInfo.Mode().Perm() != srcPerm {
			if err := os.Chmod(dstDir, srcPerm); err != nil {
				return false, fmt.Errorf("set permissions on %s: %w", dstDir, err)
			}
			changed = true
		}
	}

	entries, err := os.ReadDir(srcDir)
	if err != nil {
		return false, fmt.Errorf("read source directory %s: %w", srcDir, err)
	}

	seen := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		name := entry.Name()
		seen[name] = struct{}{}
		srcPath := filepath.Join(srcDir, name)
		dstPath := filepath.Join(dstDir, name)
		entryChanged, err := MirrorPath(srcPath, dstPath, opts)
		if err != nil {
			return false, err
		}
		if entryChanged {
			changed = true
		}
	}

	if opts.DeleteExtraneous {
		dstEntries, err := os.ReadDir(dstDir)
		if err != nil {
			return false, fmt.Errorf("read destination directory %s: %w", dstDir, err)
		}
		for _, entry := range dstEntries {
			if _, ok := seen[entry.Name()]; ok {
				continue
			}
			if err := os.RemoveAll(filepath.Join(dstDir, entry.Name())); err != nil {
				return false, fmt.Errorf("remove stale path %s: %w", filepath.Join(dstDir, entry.Name()), err)
			}
			changed = true
		}
	}

	return changed, nil
}

func mirrorFile(src, dst string, srcPerm os.FileMode) (bool, error) {
	same, err := RegularFilesEqual(src, dst)
	if err != nil {
		return false, err
	}

	if same {
		dstInfo, err := os.Stat(dst)
		if err != nil {
			return false, fmt.Errorf("stat destination %s: %w", dst, err)
		}
		if dstInfo.Mode().Perm() != srcPerm {
			if err := os.Chmod(dst, srcPerm); err != nil {
				return false, fmt.Errorf("set permissions on %s: %w", dst, err)
			}
			return true, nil
		}
		return false, nil
	}

	srcParentInfo, statErr := os.Stat(filepath.Dir(src))
	parentMode := os.FileMode(0o755)
	if statErr == nil {
		parentMode = srcParentInfo.Mode().Perm()
	}
	if err := os.MkdirAll(filepath.Dir(dst), parentMode); err != nil {
		return false, fmt.Errorf("create parent directory for %s: %w", dst, err)
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(dst), ".mirror-*")
	if err != nil {
		return false, fmt.Errorf("create temporary file for %s: %w", dst, err)
	}
	tmpName := tmpFile.Name()
	defer os.Remove(tmpName)

	srcFile, err := os.Open(src)
	if err != nil {
		tmpFile.Close()
		return false, fmt.Errorf("open source file %s: %w", src, err)
	}

	_, copyErr := io.Copy(tmpFile, srcFile)
	closeSrcErr := srcFile.Close()
	if copyErr != nil {
		tmpFile.Close()
		return false, fmt.Errorf("copy %s to %s: %w", src, dst, copyErr)
	}
	if closeSrcErr != nil {
		tmpFile.Close()
		return false, fmt.Errorf("close source file %s: %w", src, closeSrcErr)
	}

	if err := tmpFile.Chmod(srcPerm); err != nil {
		tmpFile.Close()
		return false, fmt.Errorf("set permissions on temporary file for %s: %w", dst, err)
	}
	if err := tmpFile.Close(); err != nil {
		return false, fmt.Errorf("close temporary file for %s: %w", dst, err)
	}

	if err := os.Rename(tmpName, dst); err != nil {
		return false, fmt.Errorf("replace destination %s: %w", dst, err)
	}
	return true, nil
}

func mirrorSymlink(src, dst string) (bool, error) {
	target, err := os.Readlink(src)
	if err != nil {
		return false, fmt.Errorf("read symlink %s: %w", src, err)
	}

	dstInfo, err := os.Lstat(dst)
	if err == nil {
		if dstInfo.Mode()&os.ModeSymlink != 0 {
			existingTarget, err := os.Readlink(dst)
			if err == nil && existingTarget == target {
				return false, nil
			}
		}
		if err := os.RemoveAll(dst); err != nil {
			return false, fmt.Errorf("replace destination symlink %s: %w", dst, err)
		}
	} else if !os.IsNotExist(err) {
		return false, fmt.Errorf("stat destination symlink %s: %w", dst, err)
	}

	srcParentInfo, statErr := os.Stat(filepath.Dir(src))
	parentMode := os.FileMode(0o755)
	if statErr == nil {
		parentMode = srcParentInfo.Mode().Perm()
	}
	if err := os.MkdirAll(filepath.Dir(dst), parentMode); err != nil {
		return false, fmt.Errorf("create parent directory for symlink %s: %w", dst, err)
	}
	if err := os.Symlink(target, dst); err != nil {
		return false, fmt.Errorf("create symlink %s: %w", dst, err)
	}
	return true, nil
}

// RegularFilesEqual compares two regular files byte-by-byte and reports whether
// they are identical in content and size.
func RegularFilesEqual(src, dst string) (equal bool, err error) {
	srcInfo, err := os.Stat(src)
	if err != nil {
		return false, fmt.Errorf("stat source file %s: %w", src, err)
	}
	dstInfo, err := os.Stat(dst)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, fmt.Errorf("stat destination file %s: %w", dst, err)
	}
	if !dstInfo.Mode().IsRegular() {
		return false, nil
	}
	if srcInfo.Size() != dstInfo.Size() {
		return false, nil
	}

	srcFile, err := os.Open(src)
	if err != nil {
		return false, fmt.Errorf("open source file %s: %w", src, err)
	}
	defer func() {
		if closeErr := srcFile.Close(); closeErr != nil && err == nil {
			err = fmt.Errorf("close source file %s: %w", src, closeErr)
		}
	}()
	dstFile, err := os.Open(dst)
	if err != nil {
		return false, fmt.Errorf("open destination file %s: %w", dst, err)
	}
	defer func() {
		if closeErr := dstFile.Close(); closeErr != nil && err == nil {
			err = fmt.Errorf("close destination file %s: %w", dst, closeErr)
		}
	}()

	srcBuf := make([]byte, fileCompareBufferSize)
	dstBuf := make([]byte, fileCompareBufferSize)
	for {
		srcN, srcErr := srcFile.Read(srcBuf)
		dstN, dstErr := dstFile.Read(dstBuf)

		if srcN != dstN || !bytes.Equal(srcBuf[:srcN], dstBuf[:dstN]) {
			return false, nil
		}
		if srcErr == io.EOF && dstErr == io.EOF {
			return true, nil
		}
		if srcErr != nil && srcErr != io.EOF {
			return false, fmt.Errorf("read source file %s: %w", src, srcErr)
		}
		if dstErr != nil && dstErr != io.EOF {
			return false, fmt.Errorf("read destination file %s: %w", dst, dstErr)
		}
	}
}
