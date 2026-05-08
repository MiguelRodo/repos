package gitcmd

import (
	"strings"
)

func SafeGetOriginURL(dir string) string {
	if out, err := RunGit(dir, "remote", "get-url", "origin"); err == nil {
		return out
	}
	if out, err := RunGit(dir, "config", "--get", "remote.origin.url"); err == nil {
		return out
	}
	return ""
}

func LocalBranchExists(base, branch string) bool {
	_, err := RunGit(base, "rev-parse", "--verify", "--quiet", "refs/heads/"+branch)
	return err == nil
}

func RemoteBranchExists(base, branch string) bool {
	_, err := RunGit(base, "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+branch)
	return err == nil
}

func DefaultRemoteBranch(base string) string {
	if out, err := RunGit(base, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"); err == nil {
		return strings.TrimPrefix(strings.TrimSpace(out), "origin/")
	}
	if RemoteBranchExists(base, "master") {
		return "master"
	}
	return "main"
}

func FindWorktreeForBranch(base, branch string) string {
	out, err := RunGit(base, "worktree", "list", "--porcelain")
	if err != nil {
		return ""
	}
	want := "refs/heads/" + branch
	var wt string
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "worktree ") {
			wt = strings.TrimPrefix(line, "worktree ")
		}
		if strings.HasPrefix(line, "branch ") && strings.TrimPrefix(line, "branch ") == want {
			return wt
		}
	}
	return ""
}
