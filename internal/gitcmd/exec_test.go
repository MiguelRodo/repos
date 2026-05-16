package gitcmd

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestSanitizeURL(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{
			in:   "https://user:pass@github.com/repo.git",
			want: "https://github.com/repo.git",
		},
		{
			in:   "http://token@github.com/repo.git",
			want: "http://github.com/repo.git",
		},
		{
			in:   "git checkout https://user:pass@github.com/repo.git",
			want: "git checkout https://github.com/repo.git",
		},
		{
			in:   "no sensitive info",
			want: "no sensitive info",
		},
	}

	for _, tt := range tests {
		if got := SanitizeURL(tt.in); got != tt.want {
			t.Errorf("SanitizeURL(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestNonInteractiveGitEnv(t *testing.T) {
	env := NonInteractiveGitEnv()
	foundTerminalPrompt := false
	for _, e := range env {
		if e == "GIT_TERMINAL_PROMPT=0" {
			foundTerminalPrompt = true
			break
		}
	}
	if !foundTerminalPrompt {
		t.Errorf("NonInteractiveGitEnv() missing GIT_TERMINAL_PROMPT=0")
	}
}

func TestRunGit(t *testing.T) {
	tmp := t.TempDir()
	repoDir := filepath.Join(tmp, "repo")

	// Test error
	_, err := RunGit(repoDir, "status")
	if err == nil {
		t.Errorf("RunGit() expected error in non-existent dir, got nil")
	}

	// Test success
	if _, err := RunGit("", "init", repoDir); err != nil {
		t.Fatalf("RunGit(init) failed: %v", err)
	}

	out, err := RunGit(repoDir, "rev-parse", "--is-inside-work-tree")
	if err != nil {
		t.Fatalf("RunGit(rev-parse) failed: %v", err)
	}
	if strings.TrimSpace(out) != "true" {
		t.Errorf("RunGit(rev-parse) = %q, want \"true\"", out)
	}
}
