package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"slices"

	"github.com/MiguelRodo/repos/internal/gitcmd"
	"github.com/MiguelRodo/repos/internal/sysutil"
)

var sharedSyncPaths = []string{
	filepath.Join(".github", "workflows"),
	"scripts",
}

func runUpdateScripts(args []string) error {
	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getting working directory: %w", err)
	}

	defaultFile := "repos.list"
	if _, err := os.Stat(defaultFile); err != nil {
		if _, err2 := os.Stat("repos-to-clone.list"); err2 == nil {
			defaultFile = "repos-to-clone.list"
		}
	}

	fs := flag.NewFlagSet("update-scripts", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	reposFile := fs.String("file", defaultFile, "repos list file")
	fs.StringVar(reposFile, "f", defaultFile, "repos list file")
	stage := fs.Bool("stage", false, "stage synced paths via git add")
	dryRun := fs.Bool("dry-run", false, "print what would change without writing files")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		updateScriptsUsage()
		return nil
	}

	if _, err := os.Stat(*reposFile); err != nil {
		return fmt.Errorf("file '%s' not found", *reposFile)
	}

	targetRepos, err := collectManagedRepoPaths(cwd, *reposFile)
	if err != nil {
		return err
	}
	if len(targetRepos) == 0 {
		fmt.Println("No managed repositories found in repos.list")
		return nil
	}

	fmt.Printf("Base repository: %s\n", cwd)
	fmt.Printf("Managed repositories found: %d\n", len(targetRepos))

	var updated, unchanged, skipped, failed int
	for _, repoDir := range targetRepos {
		rel, _ := filepath.Rel(cwd, repoDir)
		if rel == "." {
			fmt.Printf("⏭  skip base repository: %s\n", repoDir)
			skipped++
			continue
		}
		if _, err := os.Stat(filepath.Join(repoDir, ".git")); err != nil {
			fmt.Printf("⏭  skip (not a git repo): %s\n", repoDir)
			skipped++
			continue
		}

		repoChanged := false
		repoHadError := false
		for _, relPath := range sharedSyncPaths {
			src := filepath.Join(cwd, relPath)
			dst := filepath.Join(repoDir, relPath)
			if _, err := os.Lstat(src); err != nil {
				if errors.Is(err, os.ErrNotExist) {
					continue
				}
				fmt.Printf("✗ %s: source path check failed for %s: %v\n", repoDir, relPath, err)
				repoHadError = true
				break
			}
			if *dryRun {
				wouldChange, err := hasMirrorChanges(src, dst)
				if err != nil {
					fmt.Printf("✗ %s: dry-run comparison failed for %s: %v\n", repoDir, relPath, err)
					repoHadError = true
					break
				}
				if wouldChange {
					repoChanged = true
				}
				continue
			}
			changed, err := sysutil.MirrorPath(src, dst, sysutil.MirrorOptions{DeleteExtraneous: true})
			if err != nil {
				fmt.Printf("✗ %s: sync failed for %s: %v\n", repoDir, relPath, err)
				repoHadError = true
				break
			}
			if changed {
				repoChanged = true
			}
		}

		if repoHadError {
			failed++
			continue
		}

		if repoChanged && *stage && !*dryRun {
			for _, relPath := range sharedSyncPaths {
				if _, err := gitcmd.RunGit(repoDir, "add", "--", relPath); err != nil {
					fmt.Printf("✗ %s: git add failed for %s: %v\n", repoDir, relPath, err)
					repoHadError = true
					break
				}
			}
			if repoHadError {
				failed++
				continue
			}
		}

		if repoChanged {
			if *dryRun {
				fmt.Printf("~ would update: %s\n", repoDir)
			} else {
				fmt.Printf("✓ updated: %s\n", repoDir)
			}
			updated++
		} else {
			fmt.Printf("= unchanged: %s\n", repoDir)
			unchanged++
		}
	}

	fmt.Println()
	fmt.Println("Summary:")
	fmt.Printf("  Updated            : %d\n", updated)
	fmt.Printf("  Unchanged          : %d\n", unchanged)
	fmt.Printf("  Skipped            : %d\n", skipped)
	fmt.Printf("  Errors             : %d\n", failed)
	if *dryRun {
		fmt.Println("  Mode               : dry-run")
	}

	if failed > 0 {
		return fmt.Errorf("%d repositories failed to sync", failed)
	}
	return nil
}

func collectManagedRepoPaths(cwd, reposFile string) ([]string, error) {
	st := &state{
		startDir:        cwd,
		parentDir:       filepath.Dir(cwd),
		reposFile:       reposFile,
		globalFetchMode: "deferred",
		seenRemoteLocal: map[string]string{},
		plan:            map[string]planInfo{},
	}

	if err := st.initFallback(); err != nil {
		return nil, err
	}
	if err := st.applyGlobalFlagsFromFile(); err != nil {
		return nil, err
	}
	if err := st.planForward(); err != nil {
		return nil, err
	}

	f, err := os.Open(st.reposFile)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	fallbackHTTPS := st.currentRepoHTTPS
	fallbackLocal := cwd
	knownRemoteLocal := map[string]string{fallbackHTTPS: cwd}
	seenPaths := map[string]struct{}{}
	var repos []string

	addPath := func(p string) {
		abs, err := filepath.Abs(p)
		if err != nil {
			return
		}
		if _, exists := seenPaths[abs]; exists {
			return
		}
		seenPaths[abs] = struct{}{}
		repos = append(repos, abs)
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		trimmed := trimLine(scanner.Text())
		if trimmed == "" || lineIsGlobalFlagsOnly(trimmed) {
			continue
		}
		ins, err := st.parseEffectiveLine(trimmed, fallbackHTTPS)
		if err != nil {
			return nil, err
		}
		if ins.repoSpec == "" {
			continue
		}

		dest, remoteHTTPS, err := plannedDestination(st, ins, fallbackLocal)
		if err != nil {
			return nil, err
		}
		addPath(dest)

		if !ins.isAtBranch {
			fallbackHTTPS = remoteHTTPS
			fallbackLocal = dest
			knownRemoteLocal[remoteHTTPS] = dest
			continue
		}

		if nextBase, ok := knownRemoteLocal[fallbackHTTPS]; ok {
			fallbackLocal = nextBase
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	slices.Sort(repos)
	return repos, nil
}

func plannedDestination(st *state, ins instruction, fallbackLocal string) (string, string, error) {
	repoURLNoRef, ref := splitRepoSpec(ins.repoSpec)
	repoURL, repoDir, err := parseRepoURL(repoURLNoRef)
	if err != nil {
		return "", "", err
	}
	_ = repoURL
	remoteHTTPS := specToHTTPS(repoURLNoRef)

	if ins.isAtBranch && ins.isWorktree {
		if fallbackLocal == "" {
			return "", "", fmt.Errorf("error: no fallback local path available for %s", ins.repoSpec)
		}
		dest := ""
		if ins.targetDir != "" {
			dest = filepath.Join(st.parentDir, ins.targetDir)
		} else {
			dest = filepath.Join(st.parentDir, filepath.Base(fallbackLocal)+"-"+sanitizeBranchName(ref))
		}
		return dest, remoteHTTPS, nil
	}

	if ins.targetDir != "" {
		return filepath.Join(st.parentDir, ins.targetDir), remoteHTTPS, nil
	}
	if ref != "" {
		if st.remoteRefCount(remoteHTTPS) > 1 {
			return filepath.Join(st.parentDir, repoDir+"-"+sanitizeBranchName(ref)), remoteHTTPS, nil
		}
		return filepath.Join(st.parentDir, repoDir), remoteHTTPS, nil
	}
	return filepath.Join(st.parentDir, repoDir), remoteHTTPS, nil
}

func hasMirrorChanges(src, dst string) (bool, error) {
	srcInfo, err := os.Lstat(src)
	if err != nil {
		return false, err
	}
	dstInfo, err := os.Lstat(dst)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return true, nil
		}
		return false, err
	}

	if srcInfo.IsDir() != dstInfo.IsDir() {
		return true, nil
	}
	if srcInfo.Mode()&os.ModeSymlink != dstInfo.Mode()&os.ModeSymlink {
		return true, nil
	}
	if srcInfo.Mode().IsRegular() && dstInfo.Mode().IsRegular() {
		if srcInfo.Size() != dstInfo.Size() || srcInfo.Mode().Perm() != dstInfo.Mode().Perm() {
			return true, nil
		}
		srcData, err := os.ReadFile(src)
		if err != nil {
			return false, err
		}
		dstData, err := os.ReadFile(dst)
		if err != nil {
			return false, err
		}
		if string(srcData) != string(dstData) {
			return true, nil
		}
		return false, nil
	}
	if srcInfo.Mode()&os.ModeSymlink != 0 {
		srcTarget, err := os.Readlink(src)
		if err != nil {
			return false, err
		}
		dstTarget, err := os.Readlink(dst)
		if err != nil {
			return false, err
		}
		return srcTarget != dstTarget, nil
	}

	srcEntries, err := os.ReadDir(src)
	if err != nil {
		return false, err
	}
	dstEntries, err := os.ReadDir(dst)
	if err != nil {
		return false, err
	}
	srcNames := map[string]struct{}{}
	for _, e := range srcEntries {
		srcNames[e.Name()] = struct{}{}
		changed, err := hasMirrorChanges(filepath.Join(src, e.Name()), filepath.Join(dst, e.Name()))
		if err != nil {
			return false, err
		}
		if changed {
			return true, nil
		}
	}
	for _, e := range dstEntries {
		if _, ok := srcNames[e.Name()]; !ok {
			return true, nil
		}
	}
	return false, nil
}

func updateScriptsUsage() {
	fmt.Print(`Usage: repos update-scripts [--file <repo-list>] [--stage] [--dry-run]

Mirror shared infrastructure from the current repository into managed repositories
listed in repos.list (or repos-to-clone.list).

By default, these paths are mirrored to each managed repository:
  - .github/workflows
  - scripts

Options:
  -f, --file <file>   Path to repos list file (default: repos.list)
      --stage         Stage mirrored changes in each target repo with git add
      --dry-run       Show repositories that would change without writing files
  -h, --help          Show this help message.
`)
}
