package main

import (
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

	repos, err := parseManagedRepos(strings.NewReader(input), "https://github.com/example/current")
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

func TestParseManagedRepos_UsesInitialFallbackForAtBranch(t *testing.T) {
	input := `
@feature/test
`

	repos, err := parseManagedRepos(strings.NewReader(input), "https://github.com/acme/root")
	if err != nil {
		t.Fatalf("parseManagedRepos returned error: %v", err)
	}

	if len(repos) != 1 || repos[0] != "acme/root" {
		t.Fatalf("unexpected repos: %v", repos)
	}
}

func TestParseManagedRepos_SkipsUnsupportedRepoSpecs(t *testing.T) {
	input := `
/tmp/local-repo
@branch
`

	repos, err := parseManagedRepos(strings.NewReader(input), "https://github.com/acme/root")
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

	_, err := parseManagedRepos(strings.NewReader(input), "https://github.com/acme/root")
	if err == nil {
		t.Fatal("expected error for invalid repository spec, got nil")
	}
}
