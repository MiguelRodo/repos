package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

const testLongLineSize = 2 * 1024 * 1024

func TestDetectRProjectPrefersRenvLock(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "DESCRIPTION"), []byte("Package: demo\n"), 0o644); err != nil {
		t.Fatalf("write DESCRIPTION: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "renv.lock"), []byte("{}\n"), 0o644); err != nil {
		t.Fatalf("write renv.lock: %v", err)
	}

	mode, ok, err := detectRProject(dir)
	if err != nil {
		t.Fatalf("detectRProject returned error: %v", err)
	}
	if !ok {
		t.Fatalf("expected R project detection")
	}
	if mode != "renv.lock" {
		t.Fatalf("expected renv.lock mode, got %q", mode)
	}
}

func TestCollectManagedRepoPathsBasicAndFallbackBranch(t *testing.T) {
	t.Parallel()

	tmp := t.TempDir()
	startDir := filepath.Join(tmp, "workspace", "repos")
	if err := os.MkdirAll(startDir, 0o755); err != nil {
		t.Fatalf("mkdir startDir: %v", err)
	}
	parentDir := filepath.Dir(startDir)

	reposList := filepath.Join(startDir, "repos.list")
	content := "org/alpha\n@feature\norg/beta custom-beta\n"
	if err := os.WriteFile(reposList, []byte(content), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}

	st := &state{
		startDir:         startDir,
		parentDir:        parentDir,
		reposFile:        reposList,
		globalFetchMode:  "deferred",
		currentRepoHTTPS: "https://github.com/example/current",
		seenRemoteLocal: map[string]string{
			"https://github.com/example/current": startDir,
		},
		plan: map[string]planInfo{},
	}

	if err := st.planForward(); err != nil {
		t.Fatalf("planForward failed: %v", err)
	}
	repos, err := st.collectManagedRepoPaths()
	if err != nil {
		t.Fatalf("collectManagedRepoPaths failed: %v", err)
	}

	if len(repos) != 3 {
		t.Fatalf("expected 3 managed repos, got %d", len(repos))
	}

	want := []string{
		filepath.Join(parentDir, "alpha"),
		filepath.Join(parentDir, "alpha-feature"),
		filepath.Join(parentDir, "custom-beta"),
	}
	for i := range want {
		if repos[i].path != want[i] {
			t.Fatalf("repo %d path mismatch: got %q want %q", i, repos[i].path, want[i])
		}
	}
}

func TestStreamPrefixedOutputHandlesVeryLongLines(t *testing.T) {
	t.Parallel()

	longLine := strings.Repeat("x", testLongLineSize) // larger than old scanner max
	in := bytes.NewBufferString(longLine + "\n")
	var out bytes.Buffer

	var wg sync.WaitGroup
	errCh := make(chan error, 1)
	wg.Add(1)
	go streamPrefixedOutput("repo-a", in, &out, &wg, errCh)
	wg.Wait()
	close(errCh)

	for err := range errCh {
		if err != nil {
			t.Fatalf("unexpected stream error: %v", err)
		}
	}

	got := out.String()
	wantPrefix := "[repo-a] "
	if !strings.HasPrefix(got, wantPrefix) {
		t.Fatalf("missing prefix %q in output", wantPrefix)
	}
	if !strings.Contains(got, longLine) {
		t.Fatalf("long line content was not fully streamed")
	}
}

type failingReader struct {
	data []byte
	read bool
	err  error
}

func (r *failingReader) Read(p []byte) (int, error) {
	if r.read {
		return 0, r.err
	}
	r.read = true
	n := copy(p, r.data)
	return n, r.err
}

func TestStreamPrefixedOutputReportsReaderError(t *testing.T) {
	t.Parallel()

	readErr := errors.New("forced read error")
	in := &failingReader{
		data: []byte("partial line"),
		err:  readErr,
	}
	var out bytes.Buffer

	var wg sync.WaitGroup
	errCh := make(chan error, 1)
	wg.Add(1)
	go streamPrefixedOutput("repo-b", in, &out, &wg, errCh)
	wg.Wait()
	close(errCh)

	var gotErr error
	for err := range errCh {
		gotErr = err
	}
	if gotErr == nil {
		t.Fatalf("expected stream error")
	}
	if !errors.Is(gotErr, readErr) {
		t.Fatalf("expected %v, got %v", readErr, gotErr)
	}
}
