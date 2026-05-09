package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunCloneSingleBranchRestoresWildcardRefspec(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)

	fallbackRemote := createBareRepo(t, remotes, "fallback-repo", "dev")
	branchRemote := createBareRepo(t, remotes, "repo-two", "hotfix/urgent")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, fallbackRemote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "file://"+branchRemote+"@hotfix/urgent\n")

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(oldWD); err != nil {
			t.Logf("restore working directory: %v", err)
		}
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir project dir: %v", err)
	}

	if err := runClone([]string{"-f", "repos.list"}); err != nil {
		t.Fatalf("runClone returned error: %v", err)
	}

	cloneDir := filepath.Join(tmp, "repo-two")
	assertDirExists(t, cloneDir)
	if got := strings.TrimSpace(runGit(t, cloneDir, "rev-parse", "--abbrev-ref", "HEAD")); got != "hotfix/urgent" {
		t.Fatalf("expected branch hotfix/urgent, got %q", got)
	}

	fetchCfg := runGit(t, cloneDir, "config", "--get-all", "remote.origin.fetch")
	if !strings.Contains(fetchCfg, "+refs/heads/*:refs/remotes/origin/*") {
		t.Fatalf("expected wildcard fetch refspec in clone config, got %q", fetchCfg)
	}
}

func TestRunCloneWorktreeAndFallbackTracking(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)

	repoOneRemote := createBareRepo(t, remotes, "repo-one", "dev")
	repoTwoRemote := createBareRepo(t, remotes, "repo-two", "staging")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, repoOneRemote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), strings.Join([]string{
		"@dev --worktree",
		"file://" + repoTwoRemote,
		"@staging",
		"",
	}, "\n"))

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(oldWD); err != nil {
			t.Logf("restore working directory: %v", err)
		}
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir project dir: %v", err)
	}

	if err := runClone([]string{"-f", "repos.list"}); err != nil {
		t.Fatalf("runClone returned error: %v", err)
	}

	worktreeDir := filepath.Join(tmp, "workspace-dev")
	assertDirExists(t, worktreeDir)
	if got := strings.TrimSpace(runGit(t, worktreeDir, "rev-parse", "--abbrev-ref", "HEAD")); got != "dev" {
		t.Fatalf("expected worktree branch dev, got %q", got)
	}

	worktreeList := runGit(t, projectDir, "worktree", "list")
	if !strings.Contains(worktreeList, worktreeDir) {
		t.Fatalf("expected %s in worktree list, got %q", worktreeDir, worktreeList)
	}

	repoTwoClone := filepath.Join(tmp, "repo-two")
	assertDirExists(t, repoTwoClone)

	fallbackClone := filepath.Join(tmp, "repo-two-staging")
	assertDirExists(t, fallbackClone)
	if got := strings.TrimSpace(runGit(t, fallbackClone, "rev-parse", "--abbrev-ref", "HEAD")); got != "staging" {
		t.Fatalf("expected fallback clone on staging branch, got %q", got)
	}
	originURL := runGit(t, fallbackClone, "remote", "get-url", "origin")
	if !strings.Contains(originURL, "repo-two") {
		t.Fatalf("expected fallback clone origin to be repo-two remote, got %q", originURL)
	}
}

func enableBareRepoAccess(t *testing.T) {
	t.Helper()
	t.Setenv("GIT_CONFIG_COUNT", "1")
	t.Setenv("GIT_CONFIG_KEY_0", "safe.bareRepository")
	t.Setenv("GIT_CONFIG_VALUE_0", "all")
}

func mustMkdir(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", dir, err)
	}
}

func createBareRepo(t *testing.T, root, repoName string, branches ...string) string {
	t.Helper()

	barePath := filepath.Join(root, repoName+".git")
	runGit(t, "", "init", "--bare", barePath)

	seedPath := filepath.Join(root, repoName+"-seed")
	runGit(t, "", "clone", barePath, seedPath)
	runGit(t, seedPath, "config", "user.email", "test@example.com")
	runGit(t, seedPath, "config", "user.name", "Test User")

	mustWriteFile(t, filepath.Join(seedPath, "README.md"), "# "+repoName+"\n")
	runGit(t, seedPath, "add", "README.md")
	runGit(t, seedPath, "commit", "-m", "Initial commit")
	defaultBranch := strings.TrimSpace(runGit(t, seedPath, "symbolic-ref", "--short", "HEAD"))
	runGit(t, seedPath, "push", "origin", defaultBranch)

	for _, branch := range branches {
		runGit(t, seedPath, "checkout", defaultBranch)
		runGit(t, seedPath, "checkout", "-b", branch)
		mustWriteFile(t, filepath.Join(seedPath, "README.md"), "# "+repoName+"\n"+branch+"\n")
		runGit(t, seedPath, "add", "README.md")
		runGit(t, seedPath, "commit", "-m", branch+" commit")
		runGit(t, seedPath, "push", "origin", branch)
	}

	runGit(t, "", "--git-dir", barePath, "symbolic-ref", "HEAD", "refs/heads/"+defaultBranch)
	return barePath
}

func mustInitWorkspaceRepo(t *testing.T, repoDir, originBare string) {
	t.Helper()
	mustMkdir(t, repoDir)
	runGit(t, repoDir, "init")
	runGit(t, repoDir, "config", "user.email", "test@example.com")
	runGit(t, repoDir, "config", "user.name", "Test User")
	runGit(t, repoDir, "remote", "add", "origin", "file://"+originBare)
	mustWriteFile(t, filepath.Join(repoDir, "README.md"), "# workspace\n")
	runGit(t, repoDir, "add", "README.md")
	runGit(t, repoDir, "commit", "-m", "Initial commit")
	runGit(t, repoDir, "fetch", "origin")
}

func runGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %s failed: %v\n%s", strings.Join(args, " "), err, string(out))
	}
	return string(out)
}

func assertDirExists(t *testing.T, dir string) {
	t.Helper()
	st, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("expected dir %s to exist: %v", dir, err)
	}
	if !st.IsDir() {
		t.Fatalf("expected %s to be a directory", dir)
	}
}
