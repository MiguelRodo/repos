package main

import (
	"errors"
	"strings"
	"testing"
)

func TestParseManagedRepos_TracksFallbackAndDeduplicates(t *testing.T) {
	input := `
--worktree
# comment
acme/base
@dev
acme/next@feature/x ./next-dir
@hotfix
`

	repos, err := parseManagedRepos(strings.NewReader(input), func() (string, error) {
		return "https://github.com/acme/current", nil
	})
	if err != nil {
		t.Fatalf("parseManagedRepos returned error: %v", err)
	}

	want := []string{"acme/base", "acme/next"}
	if len(repos) != len(want) {
		t.Fatalf("unexpected repo count: got %d, want %d (%v)", len(repos), len(want), repos)
	}
	for i := range want {
		if repos[i] != want[i] {
			t.Fatalf("unexpected repos[%d]: got %q, want %q (all=%v)", i, repos[i], want[i], repos)
		}
	}
}

func TestHasPathTraversal(t *testing.T) {
	tests := []struct {
		spec string
		want bool
	}{
		{spec: "acme/repo", want: false},
		{spec: "../repo", want: true},
		{spec: "acme/../repo", want: true},
		{spec: `..\repo`, want: true},
		{spec: "%2e%2e/repo", want: true},
	}

	for _, tt := range tests {
		got := hasPathTraversal(tt.spec)
		if got != tt.want {
			t.Fatalf("hasPathTraversal(%q)=%v, want %v", tt.spec, got, tt.want)
		}
	}
}

func TestParseManagedRepos_UsesInitialFallbackForAtBranch(t *testing.T) {
	input := `
@feature/test
`

	repos, err := parseManagedRepos(strings.NewReader(input), func() (string, error) {
		return "https://github.com/acme/root", nil
	})
	if err != nil {
		t.Fatalf("parseManagedRepos returned error: %v", err)
	}

	if len(repos) != 1 || repos[0] != "acme/root" {
		t.Fatalf("unexpected repos: %v", repos)
	}
}

func TestParseManagedRepos_SkipsLocalPaths(t *testing.T) {
	input := `
/tmp/local-repo
@branch
`

	repos, err := parseManagedRepos(strings.NewReader(input), func() (string, error) {
		return "https://github.com/acme/root", nil
	})
	if err != nil {
		t.Fatalf("parseManagedRepos returned error: %v", err)
	}

	if len(repos) != 1 || repos[0] != "acme/root" {
		t.Fatalf("unexpected repos: %v", repos)
	}
}

func TestParseManagedRepos_ErrorsForInvalidSpec(t *testing.T) {
	input := `
-bad/repo
`

	_, err := parseManagedRepos(strings.NewReader(input), func() (string, error) {
		return "https://github.com/acme/root", nil
	})
	if err == nil {
		t.Fatal("expected error for invalid repository spec, got nil")
	}
}

func TestParseManagedRepos_DoesNotRequireFallbackWithoutAtBranch(t *testing.T) {
	input := `
acme/base
acme/next
`
	_, err := parseManagedRepos(strings.NewReader(input), func() (string, error) {
		return "", errors.New("should not be called")
	})
	if err != nil {
		t.Fatalf("unexpected error without @branch lines: %v", err)
	}
}

func TestParseManagedRepos_ErrorsWhenAtBranchNeedsFallback(t *testing.T) {
	input := `
@feature/test
`
	_, err := parseManagedRepos(strings.NewReader(input), func() (string, error) {
		return "", errors.New("not in a git working tree")
	})
	if err == nil {
		t.Fatal("expected fallback resolution error, got nil")
	}
}
