package parser

import (
	"strings"
	"testing"
)

func TestParseListFallbackStateMachine(t *testing.T) {
	input := strings.NewReader(`
https://example.com/acme/repo-one.git
@dev
https://example.com/acme/repo-two.git custom-two
@staging
`)

	got, err := ParseList(input, Options{InitialFallbackRemote: "https://example.com/acme/root.git", InitialBaseDir: "workspace"})
	if err != nil {
		t.Fatalf("ParseList returned error: %v", err)
	}

	if len(got) != 4 {
		t.Fatalf("expected 4 instructions, got %d", len(got))
	}

	if got[1].CloneURL != "https://example.com/acme/repo-one.git" || got[1].Branch != "dev" {
		t.Fatalf("@dev should use repo-one fallback, got cloneURL=%q branch=%q", got[1].CloneURL, got[1].Branch)
	}
	if got[3].CloneURL != "https://example.com/acme/repo-two.git" || got[3].Branch != "staging" {
		t.Fatalf("@staging should use repo-two fallback, got cloneURL=%q branch=%q", got[3].CloneURL, got[3].Branch)
	}
}

func TestParseListTargetDirectoryResolution(t *testing.T) {
	input := strings.NewReader(`
@feature/test
https://example.com/acme/repo-two.git
@release/v1.0
https://example.com/acme/repo-three.git@hotfix/urgent
https://example.com/acme/repo-three.git@dev
`)

	got, err := ParseList(input, Options{InitialFallbackRemote: "https://example.com/acme/root.git", InitialBaseDir: "workspace"})
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

	got, err := ParseList(input, Options{InitialFallbackRemote: "https://example.com/acme/root.git", InitialBaseDir: "workspace"})
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

func TestParseListRejectsInvalidBranchNames(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			name:  "invalid at-branch",
			input: "@bad..branch\n",
		},
		{
			name:  "invalid repo branch suffix",
			input: "owner/repo@bad..branch\n",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseList(strings.NewReader(tt.input), Options{
				InitialFallbackRemote: "https://example.com/acme/root.git",
				InitialBaseDir:        "workspace",
			})
			if err == nil {
				t.Fatalf("expected error for invalid branch input %q", strings.TrimSpace(tt.input))
			}
		})
	}
}

func TestParseListRejectsInvalidTargetDirs(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			name:  "target contains traversal",
			input: "owner/repo ../bad-target\n",
		},
		{
			name:  "target starts with hyphen",
			input: "@dev -bad-target\n",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseList(strings.NewReader(tt.input), Options{
				InitialFallbackRemote: "https://example.com/acme/root.git",
				InitialBaseDir:        "workspace",
			})
			if err == nil {
				t.Fatalf("expected error for invalid target input %q", strings.TrimSpace(tt.input))
			}
		})
	}
}

func TestParseListHuggingFaceFallbackAndFlagStripping(t *testing.T) {
	input := strings.NewReader(`
hf:datasets/acme/data
@dev --worktree --fetch-all
`)

	got, err := ParseList(input, Options{})
	if err != nil {
		t.Fatalf("ParseList returned error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 instructions, got %d", len(got))
	}

	if got[0].RepoType != "huggingface" {
		t.Fatalf("expected first instruction to be huggingface, got %q", got[0].RepoType)
	}
	if got[0].RemoteURL != "hf:datasets/acme/data" {
		t.Fatalf("unexpected remote URL: %q", got[0].RemoteURL)
	}
	if got[0].TargetDir != "data" {
		t.Fatalf("unexpected target dir: %q", got[0].TargetDir)
	}

	if got[1].CloneURL != "hf:datasets/acme/data" || got[1].Branch != "dev" {
		t.Fatalf("unexpected fallback resolution for @dev: cloneURL=%q branch=%q", got[1].CloneURL, got[1].Branch)
	}
	if got[1].IsWorktree {
		t.Fatalf("expected --worktree to be ignored for huggingface fallback")
	}
	if len(got[1].Warnings) == 0 {
		t.Fatalf("expected warnings for ignored git-specific flags on huggingface line")
	}
}

func TestParseListHuggingFaceFallbackAcceptsNonGitRevisionToken(t *testing.T) {
	input := strings.NewReader(`
hf:datasets/acme/data
@main~1
`)

	got, err := ParseList(input, Options{})
	if err != nil {
		t.Fatalf("ParseList returned error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 instructions, got %d", len(got))
	}
	if got[1].CloneURL != "hf:datasets/acme/data" || got[1].Branch != "main~1" {
		t.Fatalf("unexpected fallback resolution for @main~1: cloneURL=%q branch=%q", got[1].CloneURL, got[1].Branch)
	}
}

func TestParseListHuggingFaceRepoSpecAcceptsNonGitRevisionSuffix(t *testing.T) {
	input := strings.NewReader("hf:datasets/acme/data@main~1\n")

	got, err := ParseList(input, Options{})
	if err != nil {
		t.Fatalf("ParseList returned error: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected 1 instruction, got %d", len(got))
	}
	if got[0].Branch != "main~1" {
		t.Fatalf("expected branch/revision main~1, got %q", got[0].Branch)
	}
}

func TestSpecToHTTPSNormalizesHuggingFaceSlashes(t *testing.T) {
	tests := []string{
		"hf:datasets/acme/data",
		"hf:/datasets/acme/data",
		"hf://datasets/acme/data",
		"HF://datasets/acme/data",
	}
	for _, in := range tests {
		if got := SpecToHTTPS(in); got != "hf:datasets/acme/data" {
			t.Fatalf("SpecToHTTPS(%q) = %q, want %q", in, got, "hf:datasets/acme/data")
		}
	}
}
