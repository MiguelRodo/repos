package main

import (
	"errors"
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

func TestRunPipelineModeExecutesDefaultScript(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "project")
	repo1 := filepath.Join(tmp, "repo-one")
	repo2 := filepath.Join(tmp, "repo-two")

	mustMkdirAll(t, projectDir, repo1, repo2)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "example/repo-one\nexample/repo-two\n")
	mustWriteFile(t, filepath.Join(repo1, "run.sh"), "#!/usr/bin/env sh\ntouch .pipeline\n")
	mustWriteFile(t, filepath.Join(repo2, "run.sh"), "#!/usr/bin/env sh\ntouch .pipeline\n")

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

	if err := runRun([]string{"--skip-deps"}); err != nil {
		t.Fatalf("runRun returned error: %v", err)
	}

	assertFileExists(t, filepath.Join(repo1, ".pipeline"))
	assertFileExists(t, filepath.Join(repo2, ".pipeline"))
}

func TestRunPipelineModeHonorsIncludeFilter(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "project")
	repo1 := filepath.Join(tmp, "repo-one")
	repo2 := filepath.Join(tmp, "repo-two")

	mustMkdirAll(t, projectDir, repo1, repo2)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "example/repo-one\nexample/repo-two\n")
	mustWriteFile(t, filepath.Join(repo1, "run.sh"), "#!/usr/bin/env sh\ntouch .included\n")
	mustWriteFile(t, filepath.Join(repo2, "run.sh"), "#!/usr/bin/env sh\ntouch .excluded\n")

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

	if err := runRun([]string{"--skip-deps", "--include", "repo-one"}); err != nil {
		t.Fatalf("runRun returned error: %v", err)
	}

	assertFileExists(t, filepath.Join(repo1, ".included"))
	if _, err := os.Stat(filepath.Join(repo2, ".excluded")); err == nil {
		t.Fatal("expected repo-two script not to run")
	} else if !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expected repo-two script not to run, got stat err: %v", err)
	}
}

func TestRunPipelineModeSupportsConciseListPerLineScript(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "project")
	repo1 := filepath.Join(tmp, "repo-one")
	repo2 := filepath.Join(tmp, "repo-two")

	mustMkdirAll(t, projectDir, repo1, repo2)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "repo-one custom.sh\nrepo-two\n")
	mustWriteFile(t, filepath.Join(repo1, "custom.sh"), "#!/usr/bin/env sh\ntouch .custom\n")
	mustWriteFile(t, filepath.Join(repo2, "run.sh"), "#!/usr/bin/env sh\ntouch .default\n")

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

	if err := runRun([]string{"--skip-deps"}); err != nil {
		t.Fatalf("runRun returned error: %v", err)
	}

	assertFileExists(t, filepath.Join(repo1, ".custom"))
	assertFileExists(t, filepath.Join(repo2, ".default"))
}

func TestValidateRunScriptPath(t *testing.T) {
	bad := []string{
		"",
		"/abs/path.sh",
		"../run.sh",
		"-run.sh",
		"run;rm.sh",
	}
	for _, script := range bad {
		if err := validateRunScriptPath(script); err == nil {
			t.Fatalf("expected validateRunScriptPath(%q) to fail", script)
		}
	}
	if err := validateRunScriptPath("scripts/run.sh"); err != nil {
		t.Fatalf("expected valid script path, got error: %v", err)
	}
}

func TestValidateConciseRunRepoName(t *testing.T) {
	bad := []string{
		"/tmp/repo",
		"../repo",
		"-repo",
		"repo/one",
		"repo;one",
	}
	for _, name := range bad {
		if err := validateConciseRunRepoName(name); err == nil {
			t.Fatalf("expected validateConciseRunRepoName(%q) to fail", name)
		}
	}
	if err := validateConciseRunRepoName("repo_one-1"); err != nil {
		t.Fatalf("expected valid repo name, got error: %v", err)
	}
}

func TestShouldRunRepo(t *testing.T) {
	include := map[string]struct{}{"repo-one": {}}
	exclude := map[string]struct{}{"repo-two": {}}
	if !shouldRunRepo("repo-one", include, exclude) {
		t.Fatal("expected included repo to run")
	}
	if shouldRunRepo("repo-two", nil, exclude) {
		t.Fatal("expected excluded repo not to run")
	}
	if shouldRunRepo("repo-three", include, nil) {
		t.Fatal("expected non-included repo not to run")
	}
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
