package main

import (
	"errors"
	"fmt"
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
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), branchRemote+"@hotfix/urgent\n")

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
		repoTwoRemote,
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

func TestHasNonLocalRemotesInFile(t *testing.T) {
	tmp := t.TempDir()
	list := filepath.Join(tmp, "repos.list")

	tests := []struct {
		name    string
		lines   []string
		want    bool
		wantErr bool
	}{
		{
			name: "all-local-and-at-branch",
			lines: []string{
				"--worktree",
				"--depth 1",
				"/tmp/local/repo.git",
				"file:///tmp/local2/repo.git",
				"@feature-x",
			},
			want: false,
		},
		{
			name: "github-owner-repo",
			lines: []string{
				"acme/repo",
			},
			want: true,
		},
		{
			name: "https-remote",
			lines: []string{
				"https://github.com/acme/repo.git",
			},
			want: true,
		},
		{
			name: "huggingface-remote",
			lines: []string{
				"hf:datasets/acme/data",
			},
			want: false,
		},
		{
			name: "ssh-scp-github-remote",
			lines: []string{
				"git@github.com:acme/repo.git",
			},
			want: true,
		},
		{
			name: "ssh-url-github-remote",
			lines: []string{
				"ssh://git@github.com/acme/repo.git",
			},
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := os.WriteFile(list, []byte(strings.Join(tt.lines, "\n")+"\n"), 0o644); err != nil {
				t.Fatalf("write repos.list: %v", err)
			}
			got, err := hasNonLocalRemotesInFile(list)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("expected error")
				}
				return
			}
			if err != nil {
				t.Fatalf("hasNonLocalRemotesInFile error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("expected %v, got %v", tt.want, got)
			}
		})
	}
}

func TestRunCloneSkipsAuthCheckWhenOnlyLocalRemotes(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	localRemote := createBareRepo(t, remotes, "local-only", "dev")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, localRemote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), localRemote+"\n")

	oldHasNonLocal := hasNonLocalRemotesInFileFunc
	oldAuthCheck := checkNonInteractiveAuthForCloneFunc
	defer func() {
		hasNonLocalRemotesInFileFunc = oldHasNonLocal
		checkNonInteractiveAuthForCloneFunc = oldAuthCheck
	}()

	hasNonLocalRemotesInFileFunc = func(reposFile string) (bool, error) { return false, nil }
	authCheckCalled := false
	checkNonInteractiveAuthForCloneFunc = func() error {
		authCheckCalled = true
		return errors.New("should not be called")
	}

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
	if authCheckCalled {
		t.Fatalf("expected auth check not to run for local-only remotes")
	}
}

func TestRunCloneFailsWhenAuthCheckFailsForNonLocalRemotes(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "workspace")
	mustMkdir(t, projectDir)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "acme/repo\n")

	oldHasNonLocal := hasNonLocalRemotesInFileFunc
	oldAuthCheck := checkNonInteractiveAuthForCloneFunc
	defer func() {
		hasNonLocalRemotesInFileFunc = oldHasNonLocal
		checkNonInteractiveAuthForCloneFunc = oldAuthCheck
	}()

	hasNonLocalRemotesInFileFunc = func(reposFile string) (bool, error) { return true, nil }
	checkNonInteractiveAuthForCloneFunc = func() error { return errors.New("auth missing") }

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

	err = runClone([]string{"-f", "repos.list"})
	if err == nil {
		t.Fatalf("expected auth check error")
	}
	if !strings.Contains(err.Error(), "auth missing") {
		t.Fatalf("expected auth error, got: %v", err)
	}
}

func TestRunCloneWithCLIDepthCreatesShallowClone(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-depth", "dev")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "file://"+remote+"@dev\n")

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

	if err := runClone([]string{"-f", "repos.list", "--depth", "1"}); err != nil {
		t.Fatalf("runClone returned error: %v", err)
	}

	cloneDir := filepath.Join(tmp, "repo-depth")
	assertDirExists(t, cloneDir)
	if got := strings.TrimSpace(runGit(t, cloneDir, "rev-parse", "--is-shallow-repository")); got != "true" {
		t.Fatalf("expected shallow clone, got %q", got)
	}
	if got := strings.TrimSpace(runGit(t, cloneDir, "rev-list", "--count", "HEAD")); got != "1" {
		t.Fatalf("expected depth-limited history count 1, got %q", got)
	}
}

func TestRunClonePerLineDepthOverridesGlobalDepth(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-depth-override", "dev")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), strings.Join([]string{
		"--depth 2",
		"file://" + remote + "@dev --depth 1",
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

	cloneDir := filepath.Join(tmp, "repo-depth-override")
	assertDirExists(t, cloneDir)
	if got := strings.TrimSpace(runGit(t, cloneDir, "rev-list", "--count", "HEAD")); got != "1" {
		t.Fatalf("expected per-line depth override to limit history to 1, got %q", got)
	}
}

func TestRunCloneRejectsInvalidDepth(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "workspace")
	mustMkdir(t, projectDir)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "acme/repo\n")

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

	err = runClone([]string{"-f", "repos.list", "--depth", "0"})
	if err == nil {
		t.Fatalf("expected invalid --depth error")
	}
	if !strings.Contains(err.Error(), "--depth") {
		t.Fatalf("expected --depth error message, got %v", err)
	}
}

func TestRunCloneMissingBranchRequiresCreateFlag(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-one")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), remote+"@feature/new-api\n")

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

	err = runCloneExpectCreateGuidance(t, []string{"-f", "repos.list"})
	if branchExistsInBare(t, remote, "feature/new-api") {
		t.Fatalf("branch should not be created unless --create is set")
	}
}

func TestRunCloneCreateFlagCreatesMissingBranch(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-one")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), remote+"@feature/new-api\n")

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

	if err := runClone([]string{"-f", "repos.list", "--create"}); err != nil {
		t.Fatalf("runClone returned error: %v", err)
	}
	if !branchExistsInBare(t, remote, "feature/new-api") {
		t.Fatalf("expected branch to be created when --create is set")
	}
}

func TestRunCloneWorktreeMissingBranchRequiresCreateFlag(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-one")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "@feature/needs-create --worktree\n")

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

	err = runCloneExpectCreateGuidance(t, []string{"-f", "repos.list"})
	if branchExistsInBare(t, remote, "feature/needs-create") {
		t.Fatalf("branch should not be created unless --create is set")
	}
}

func TestCheckNonInteractiveAuthForCloneHasActionableError(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("PATH", tmp)
	t.Setenv("GH_TOKEN", "")
	t.Setenv("SSH_AUTH_SOCK", "")

	err := checkNonInteractiveAuthForClone()
	if err == nil {
		t.Fatalf("expected auth check error")
	}
	msg := err.Error()
	for _, expected := range []string{"GH_TOKEN", "gh auth login", "SSH agent", "credential.helper"} {
		if !strings.Contains(msg, expected) {
			t.Fatalf("expected error to mention %q, got: %q", expected, msg)
		}
	}
}

func TestRunCloneHuggingFaceRequiresCLIWhenHFRepoPresent(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-one")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "hf:datasets/acme/data\n")

	gitPath, err := exec.LookPath("git")
	if err != nil {
		t.Fatalf("lookpath git: %v", err)
	}
	binDir := filepath.Join(tmp, "bin-no-hf")
	mustMkdir(t, binDir)
	if err := os.Symlink(gitPath, filepath.Join(binDir, "git")); err != nil {
		t.Fatalf("symlink git: %v", err)
	}
	t.Setenv("PATH", binDir)

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

	err = runClone([]string{"-f", "repos.list"})
	if err == nil {
		t.Fatalf("expected missing huggingface-cli error")
	}
	if !strings.Contains(err.Error(), "huggingface_hub[cli]") {
		t.Fatalf("expected install guidance in error, got: %v", err)
	}
}

func TestRunCloneHuggingFaceRoutesToCLIAndPassesHFToken(t *testing.T) {
	enableBareRepoAccess(t)

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-one")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "HF://datasets/acme/data@dev --fetch-all --worktree\n")

	gitPath, err := exec.LookPath("git")
	if err != nil {
		t.Fatalf("lookpath git: %v", err)
	}
	binDir := filepath.Join(tmp, "bin-with-hf")
	mustMkdir(t, binDir)
	if err := os.Symlink(gitPath, filepath.Join(binDir, "git")); err != nil {
		t.Fatalf("symlink git: %v", err)
	}

	logFile := filepath.Join(tmp, "hf.log")
	hfShim := filepath.Join(binDir, "huggingface-cli")
	script := fmt.Sprintf(`#!/bin/sh
echo "$@" >> %q
echo "HF_TOKEN=$HF_TOKEN" >> %q
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--local-dir" ]; then
    shift
    mkdir -p "$1"
  fi
  shift
done
`, logFile, logFile)
	if err := os.WriteFile(hfShim, []byte(script), 0o755); err != nil {
		t.Fatalf("write huggingface shim: %v", err)
	}

	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("HF_TOKEN", "token-123")

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

	content, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatalf("read hf log: %v", err)
	}
	logs := string(content)
	if !strings.Contains(logs, "download datasets/acme/data --revision dev --local-dir") {
		t.Fatalf("expected huggingface-cli download invocation, got: %s", logs)
	}
	if !strings.Contains(logs, "HF_TOKEN=token-123") {
		t.Fatalf("expected HF_TOKEN to be passed through, got: %s", logs)
	}
}

func TestRunCloneHuggingFaceAuthIntegrationSkipsWithoutHFToken(t *testing.T) {
	enableBareRepoAccess(t)

	privateRepo := strings.TrimSpace(os.Getenv("REPOS_TEST_HF_PRIVATE_REPO"))
	if privateRepo == "" {
		t.Skip("set REPOS_TEST_HF_PRIVATE_REPO to run authenticated Hugging Face integration test")
	}
	if strings.TrimSpace(os.Getenv("HF_TOKEN")) == "" {
		t.Skip("set HF_TOKEN to run authenticated Hugging Face integration test")
	}
	if _, err := exec.LookPath("huggingface-cli"); err != nil {
		t.Skip("huggingface-cli not found in PATH")
	}

	tmp := t.TempDir()
	remotes := filepath.Join(tmp, "remotes")
	mustMkdir(t, remotes)
	remote := createBareRepo(t, remotes, "repo-one")

	projectDir := filepath.Join(tmp, "workspace")
	mustInitWorkspaceRepo(t, projectDir, remote)
	mustWriteFile(t, filepath.Join(projectDir, "repos.list"), "hf:"+privateRepo+"\n")

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

	targetDir := filepath.Join(tmp, filepath.Base(privateRepo))
	entries, err := os.ReadDir(targetDir)
	if err != nil {
		t.Fatalf("read target dir %s: %v", targetDir, err)
	}
	if len(entries) == 0 {
		t.Fatalf("expected downloaded files in %s", targetDir)
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
	runGit(t, repoDir, "remote", "add", "origin", originBare)
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

func branchExistsInBare(t *testing.T, barePath, branch string) bool {
	t.Helper()
	cmd := exec.Command("git", "--git-dir", barePath, "show-ref", "--verify", "--", "refs/heads/"+branch)
	return cmd.Run() == nil
}

func runCloneExpectCreateGuidance(t *testing.T, args []string) error {
	t.Helper()
	var err error
	stderr := captureStderr(t, func() {
		err = runClone(args)
	})
	if err == nil {
		t.Fatalf("expected missing-branch error")
	}
	if !strings.Contains(stderr, "--create") {
		t.Fatalf("expected guidance to use --create, got stderr: %s", stderr)
	}
	return err
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
