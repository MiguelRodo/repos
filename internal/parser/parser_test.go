package parser

import (
	"strings"
	"testing"
)

func TestParseListFallbackStateMachine(t *testing.T) {
	input := strings.NewReader(`
file:///tmp/repo-one.git
@dev
file:///tmp/repo-two.git custom-two
@staging
`)

	got, err := ParseList(input, Options{InitialFallbackRemote: "file:///tmp/root.git", InitialBaseDir: "workspace"})
	if err != nil {
		t.Fatalf("ParseList returned error: %v", err)
	}

	if len(got) != 4 {
		t.Fatalf("expected 4 instructions, got %d", len(got))
	}

	if got[1].CloneURL != "file:///tmp/repo-one.git" || got[1].Branch != "dev" {
		t.Fatalf("@dev should use repo-one fallback, got cloneURL=%q branch=%q", got[1].CloneURL, got[1].Branch)
	}
	if got[3].CloneURL != "file:///tmp/repo-two.git" || got[3].Branch != "staging" {
		t.Fatalf("@staging should use repo-two fallback, got cloneURL=%q branch=%q", got[3].CloneURL, got[3].Branch)
	}
}

func TestParseListTargetDirectoryResolution(t *testing.T) {
	input := strings.NewReader(`
@feature/test
file:///tmp/repo-two.git
@release/v1.0
file:///tmp/repo-three.git@hotfix/urgent
file:///tmp/repo-three.git@dev
`)

	got, err := ParseList(input, Options{InitialFallbackRemote: "file:///tmp/root.git", InitialBaseDir: "workspace"})
	if err != nil {
		t.Fatalf("ParseList returned error: %v", err)
	}

	tests := []struct {
		idx        int
		wantTarget string
	}{
		{idx: 0, wantTarget: "workspace-feature-test"},
		{idx: 2, wantTarget: "repo-two-release-v1.0"},
		{idx: 3, wantTarget: "repo-three-hotfix-urgent"},
		{idx: 4, wantTarget: "repo-three-dev"},
	}

	for _, tt := range tests {
		if got[tt.idx].TargetDir != tt.wantTarget {
			t.Fatalf("instruction %d target dir mismatch: got %q, want %q", tt.idx, got[tt.idx].TargetDir, tt.wantTarget)
		}
	}
}

func TestParseListGlobalFlagOverrides(t *testing.T) {
	input := strings.NewReader(`
--worktree --fetch-all --force
@dev --fetch-single
owner/repo@feature/test --fetch-single
`)

	got, err := ParseList(input, Options{InitialFallbackRemote: "file:///tmp/root.git", InitialBaseDir: "workspace"})
	if err != nil {
		t.Fatalf("ParseList returned error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 instructions, got %d", len(got))
	}

	if !got[0].IsWorktree {
		t.Fatalf("expected @branch line to be worktree due to global --worktree")
	}
	if got[0].FetchMode != "all" {
		t.Fatalf("expected fetch mode 'all' to remain locked by global --force, got %q", got[0].FetchMode)
	}
	if !got[0].AllBranches {
		t.Fatalf("expected allBranches=true when fetch mode is all")
	}

	if got[1].FetchMode != "all" {
		t.Fatalf("expected repo line fetch mode to stay 'all' under locked global flags, got %q", got[1].FetchMode)
	}
	if !got[1].AllBranches {
		t.Fatalf("expected repo line allBranches=true under --fetch-all")
	}
}
