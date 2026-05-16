package gitcmd

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestSafeGetOriginURL(t *testing.T) {
	tmp := t.TempDir()
	repoDir := filepath.Join(tmp, "repo")
	mustGit(t, "", "init", repoDir)

	originURL := "https://github.com/user/repo.git"
	mustGit(t, repoDir, "remote", "add", "origin", originURL)

	got := SafeGetOriginURL(repoDir)
	if got != originURL {
		t.Errorf("SafeGetOriginURL() = %q, want %q", got, originURL)
	}

	// Test fallback to config
	mustGit(t, repoDir, "remote", "remove", "origin")
	mustGit(t, repoDir, "config", "remote.origin.url", originURL)

	got = SafeGetOriginURL(repoDir)
	if got != originURL {
		t.Errorf("SafeGetOriginURL() fallback = %q, want %q", got, originURL)
	}

	// Test empty
	mustGit(t, repoDir, "config", "--unset", "remote.origin.url")
	got = SafeGetOriginURL(repoDir)
	if got != "" {
		t.Errorf("SafeGetOriginURL() empty = %q, want \"\"", got)
	}
}

func TestLocalBranchExists(t *testing.T) {
	tmp := t.TempDir()
	repoDir := filepath.Join(tmp, "repo")
	mustGit(t, "", "init", repoDir)
	mustGit(t, repoDir, "commit", "--allow-empty", "-m", "initial")

	if !LocalBranchExists(repoDir, "main") && !LocalBranchExists(repoDir, "master") {
		t.Errorf("LocalBranchExists() could not find default branch")
	}

	mustGit(t, repoDir, "checkout", "-b", "feature")
	if !LocalBranchExists(repoDir, "feature") {
		t.Errorf("LocalBranchExists(feature) = false, want true")
	}

	if LocalBranchExists(repoDir, "non-existent") {
		t.Errorf("LocalBranchExists(non-existent) = true, want false")
	}
}

func TestRemoteBranchExists(t *testing.T) {
	tmp := t.TempDir()
	remoteDir := filepath.Join(tmp, "remote")
	mustGit(t, "", "init", "--bare", remoteDir)

	repoDir := filepath.Join(tmp, "repo")
	mustGit(t, "", "clone", remoteDir, repoDir)
	mustGit(t, repoDir, "commit", "--allow-empty", "-m", "initial")

	defaultBranch := getActiveBranch(t, repoDir)
	mustGit(t, repoDir, "push", "origin", defaultBranch)

	// Need to fetch to ensure remote tracking branches exist
	mustGit(t, repoDir, "fetch", "origin")

	if !RemoteBranchExists(repoDir, defaultBranch) {
		t.Errorf("RemoteBranchExists(%s) = false, want true", defaultBranch)
	}

	if RemoteBranchExists(repoDir, "non-existent") {
		t.Errorf("RemoteBranchExists(non-existent) = true, want false")
	}
}

func TestDefaultRemoteBranch(t *testing.T) {
	tmp := t.TempDir()
	remoteDir := filepath.Join(tmp, "remote")
	mustGit(t, "", "init", "--bare", remoteDir)

	repoDir := filepath.Join(tmp, "repo")
	mustGit(t, "", "clone", remoteDir, repoDir)
	mustGit(t, repoDir, "commit", "--allow-empty", "-m", "initial")

	defaultBranch := getActiveBranch(t, repoDir)
	mustGit(t, repoDir, "push", "origin", defaultBranch)
	mustGit(t, repoDir, "remote", "set-head", "origin", defaultBranch)

	got := DefaultRemoteBranch(repoDir)
	if got != defaultBranch {
		t.Errorf("DefaultRemoteBranch() = %q, want %q", got, defaultBranch)
	}

	// Test fallbacks
	mustGit(t, repoDir, "remote", "set-head", "origin", "--delete")

	// If it was main, it should return main by default if no master exists
	// If it was master, it should return master.
	got = DefaultRemoteBranch(repoDir)
	if got != defaultBranch {
		t.Errorf("DefaultRemoteBranch() fallback = %q, want %q", got, defaultBranch)
	}
}

func TestFindWorktreeForBranch(t *testing.T) {
	tmp := t.TempDir()
	repoDir := filepath.Join(tmp, "repo")
	mustGit(t, "", "init", repoDir)
	mustGit(t, repoDir, "commit", "--allow-empty", "-m", "initial")

	mustGit(t, repoDir, "branch", "feature")
	wtDir := filepath.Join(tmp, "feature-wt")
	mustGit(t, repoDir, "worktree", "add", wtDir, "feature")

	got := FindWorktreeForBranch(repoDir, "feature")

	evalGot, err := filepath.EvalSymlinks(got)
	if err != nil {
		evalGot = got
	}
	evalWant, err := filepath.EvalSymlinks(wtDir)
	if err != nil {
		evalWant = wtDir
	}

	if evalGot != evalWant {
		t.Errorf("FindWorktreeForBranch(feature) = %q (eval: %q), want %q (eval: %q)", got, evalGot, wtDir, evalWant)
	}

	if got := FindWorktreeForBranch(repoDir, "non-existent"); got != "" {
		t.Errorf("FindWorktreeForBranch(non-existent) = %q, want \"\"", got)
	}
}

func mustGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %s failed: %v\n%s", strings.Join(args, " "), err, string(out))
	}
}

func getActiveBranch(t *testing.T, dir string) string {
	t.Helper()
	cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("git rev-parse failed: %v", err)
	}
	return strings.TrimSpace(string(out))
}
