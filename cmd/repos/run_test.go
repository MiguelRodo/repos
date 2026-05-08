package main

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunExecutesCommandInAllRepos(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "project")
	repo1 := filepath.Join(tmp, "repo-one")
	repo2 := filepath.Join(tmp, "repo-two")

	mustMkdirAll(t, projectDir, repo1, repo2)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "example/repo-one\nexample/repo-two\n")

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Chdir(oldWD)
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir project dir: %v", err)
	}

	err = runRun([]string{"sh", "-c", "echo ran > .ran"})
	if err != nil {
		t.Fatalf("runRun returned error: %v", err)
	}

	assertFileExists(t, filepath.Join(repo1, ".ran"))
	assertFileExists(t, filepath.Join(repo2, ".ran"))
}

func TestRunReturnsErrorButContinuesAfterFailure(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "project")
	repo1 := filepath.Join(tmp, "repo-one")
	repo2 := filepath.Join(tmp, "repo-two")

	mustMkdirAll(t, projectDir, repo1, repo2)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "example/repo-one\nexample/repo-two\n")

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Chdir(oldWD)
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir project dir: %v", err)
	}

	err = runRun([]string{"sh", "-c", `if [ "$(basename "$PWD")" = "repo-one" ]; then exit 3; fi; echo ok > .ok`})
	if err == nil {
		t.Fatalf("expected error when one repository command fails")
	}
	assertFileExists(t, filepath.Join(repo2, ".ok"))
}

func TestRunPrefixesStdoutAndStderrLines(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "project")
	repo1 := filepath.Join(tmp, "repo-one")

	mustMkdirAll(t, projectDir, repo1)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "example/repo-one\n")

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Chdir(oldWD)
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir project dir: %v", err)
	}

	output := captureStdout(t, func() {
		if err := runRun([]string{"sh", "-c", "echo out; echo err 1>&2"}); err != nil {
			t.Fatalf("runRun returned error: %v", err)
		}
	})

	if !strings.Contains(output, "[repo-one] out") {
		t.Fatalf("expected prefixed stdout line, got: %q", output)
	}
	if !strings.Contains(output, "[repo-one] err") {
		t.Fatalf("expected prefixed stderr line, got: %q", output)
	}
}

func TestRunConcurrentExecutesCommandInAllRepos(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "project")
	repo1 := filepath.Join(tmp, "repo-one")
	repo2 := filepath.Join(tmp, "repo-two")

	mustMkdirAll(t, projectDir, repo1, repo2)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "example/repo-one\nexample/repo-two\n")

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Chdir(oldWD)
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir project dir: %v", err)
	}

	err = runRun([]string{"--concurrent", "sh", "-c", "echo ran > .ran.concurrent"})
	if err != nil {
		t.Fatalf("runRun returned error: %v", err)
	}

	assertFileExists(t, filepath.Join(repo1, ".ran.concurrent"))
	assertFileExists(t, filepath.Join(repo2, ".ran.concurrent"))
}

func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	oldStdout := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("creating pipe: %v", err)
	}
	os.Stdout = w
	t.Cleanup(func() {
		os.Stdout = oldStdout
	})
	t.Cleanup(func() {
		_ = w.Close()
		_ = r.Close()
	})

	done := make(chan string, 1)
	copyErr := make(chan error, 1)
	go func() {
		var b strings.Builder
		_, err := io.Copy(&b, r)
		copyErr <- err
		done <- b.String()
	}()

	fn()
	_ = w.Close()
	out := <-done
	if err := <-copyErr; err != nil {
		t.Fatalf("copy stdout: %v", err)
	}
	return out
}

func mustMkdirAll(t *testing.T, dirs ...string) {
	t.Helper()
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", dir, err)
		}
	}
}

func mustWriteFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write file %s: %v", path, err)
	}
}

func assertFileExists(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("expected file %s to exist: %v", path, err)
	}
}
