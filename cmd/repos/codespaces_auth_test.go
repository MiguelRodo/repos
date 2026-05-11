package main

import (
	"errors"
	"os"
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

func TestStripJSONC_RemovesLineComments(t *testing.T) {
	input := `{
  // this is a comment
  "key": "value" // inline comment
}`
	got := string(stripJSONC([]byte(input)))
	if strings.Contains(got, "//") {
		t.Fatalf("line comments not stripped: %q", got)
	}
	if !strings.Contains(got, `"key"`) {
		t.Fatalf("key not preserved: %q", got)
	}
}

func TestStripJSONC_RemovesBlockComments(t *testing.T) {
	input := `{
  /* block comment */
  "key": /* inline block */ "value"
}`
	got := string(stripJSONC([]byte(input)))
	if strings.Contains(got, "/*") {
		t.Fatalf("block comments not stripped: %q", got)
	}
	if !strings.Contains(got, `"value"`) {
		t.Fatalf("value not preserved: %q", got)
	}
}

func TestStripJSONC_RemovesTrailingCommas(t *testing.T) {
	input := `{"a":1,"b":2,}`
	got := string(stripJSONC([]byte(input)))
	if strings.Contains(got, ",}") {
		t.Fatalf("trailing comma not stripped: %q", got)
	}
}

func TestStripJSONC_PreservesCommasInStrings(t *testing.T) {
	input := `{"url":"https://example.com/a,b","key":"value"}`
	got := string(stripJSONC([]byte(input)))
	if !strings.Contains(got, "https://example.com/a,b") {
		t.Fatalf("comma inside string was incorrectly removed: %q", got)
	}
}

func TestBuildRepoPermissionsBlock_Default(t *testing.T) {
	block := buildRepoPermissionsBlock([]string{"acme/api"}, "default")
	entry, ok := block["acme/api"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected map entry for acme/api, got %T", block["acme/api"])
	}
	perms, ok := entry["permissions"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected permissions map, got %T", entry["permissions"])
	}
	if perms["actions"] != "write" || perms["contents"] != "write" {
		t.Fatalf("unexpected default permissions: %v", perms)
	}
}

func TestBuildRepoPermissionsBlock_All(t *testing.T) {
	block := buildRepoPermissionsBlock([]string{"acme/api"}, "all")
	entry, ok := block["acme/api"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected map entry for acme/api, got %T", block["acme/api"])
	}
	if entry["permissions"] != "write-all" {
		t.Fatalf("expected write-all, got %v", entry["permissions"])
	}
}

func TestBuildRepoPermissionsBlock_Contents(t *testing.T) {
	block := buildRepoPermissionsBlock([]string{"acme/api"}, "contents")
	entry, ok := block["acme/api"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected map entry for acme/api, got %T", block["acme/api"])
	}
	perms, ok := entry["permissions"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected permissions map, got %T", entry["permissions"])
	}
	if perms["contents"] != "write" {
		t.Fatalf("expected contents:write, got %v", perms)
	}
}

func TestMergeRepoPermissions_CreatesNestedKeys(t *testing.T) {
	doc := make(map[string]interface{})
	block := buildRepoPermissionsBlock([]string{"acme/api"}, "default")
	mergeRepoPermissions(doc, block)

	custom, ok := doc["customizations"].(map[string]interface{})
	if !ok {
		t.Fatalf("customizations not created")
	}
	cs, ok := custom["codespaces"].(map[string]interface{})
	if !ok {
		t.Fatalf("codespaces not created")
	}
	repos, ok := cs["repositories"].(map[string]interface{})
	if !ok {
		t.Fatalf("repositories not created")
	}
	if _, ok := repos["acme/api"]; !ok {
		t.Fatalf("acme/api not found in repositories")
	}
}

func TestMergeRepoPermissions_MergesIntoExisting(t *testing.T) {
	doc := map[string]interface{}{
		"customizations": map[string]interface{}{
			"codespaces": map[string]interface{}{
				"repositories": map[string]interface{}{
					"existing/repo": map[string]interface{}{},
				},
			},
		},
	}
	block := buildRepoPermissionsBlock([]string{"acme/new"}, "default")
	mergeRepoPermissions(doc, block)

	cs := doc["customizations"].(map[string]interface{})["codespaces"].(map[string]interface{})
	repos := cs["repositories"].(map[string]interface{})
	if _, ok := repos["existing/repo"]; !ok {
		t.Fatalf("existing/repo was removed")
	}
	if _, ok := repos["acme/new"]; !ok {
		t.Fatalf("acme/new was not added")
	}
}

func TestUpdateDevcontainerFile_CreatesNewFile(t *testing.T) {
	dir := t.TempDir()
	dcFile := dir + "/devcontainer.json"

	if err := updateDevcontainerFile(dcFile, []string{"acme/api"}, "default", false); err != nil {
		t.Fatalf("updateDevcontainerFile error: %v", err)
	}

	data, err := os.ReadFile(dcFile)
	if err != nil {
		t.Fatalf("reading created file: %v", err)
	}
	if !strings.Contains(string(data), "acme/api") {
		t.Fatalf("expected acme/api in file, got: %s", string(data))
	}
}

func TestUpdateDevcontainerFile_UpdatesExistingFile(t *testing.T) {
	dir := t.TempDir()
	dcFile := dir + "/devcontainer.json"
	existing := `{"customizations":{"codespaces":{"repositories":{"old/repo":{}}}}}`
	if err := os.WriteFile(dcFile, []byte(existing), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}

	if err := updateDevcontainerFile(dcFile, []string{"acme/api"}, "default", false); err != nil {
		t.Fatalf("updateDevcontainerFile error: %v", err)
	}

	data, err := os.ReadFile(dcFile)
	if err != nil {
		t.Fatalf("reading file: %v", err)
	}
	content := string(data)
	if !strings.Contains(content, "acme/api") {
		t.Fatalf("expected acme/api in updated file, got: %s", content)
	}
	if !strings.Contains(content, "old/repo") {
		t.Fatalf("expected old/repo to be preserved, got: %s", content)
	}
}

func TestUpdateDevcontainerFile_DryRunDoesNotWrite(t *testing.T) {
	dir := t.TempDir()
	dcFile := dir + "/devcontainer.json"

	if err := updateDevcontainerFile(dcFile, []string{"acme/api"}, "default", true); err != nil {
		t.Fatalf("updateDevcontainerFile dry-run error: %v", err)
	}

	// File should not have been created in dry-run mode.
	if _, err := os.Stat(dcFile); err == nil {
		t.Fatal("dry-run should not create the file")
	}
}

func TestUpdateDevcontainerFile_HandlesJSONC(t *testing.T) {
	dir := t.TempDir()
	dcFile := dir + "/devcontainer.json"
	jsonc := `{
  // existing settings
  "name": "My Dev Container",
  "customizations": {
    "codespaces": {
      "repositories": {
        "old/repo": {} // keep me
      }
    }
  },
}`
	if err := os.WriteFile(dcFile, []byte(jsonc), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}

	if err := updateDevcontainerFile(dcFile, []string{"new/repo"}, "default", false); err != nil {
		t.Fatalf("updateDevcontainerFile error: %v", err)
	}

	data, err := os.ReadFile(dcFile)
	if err != nil {
		t.Fatalf("reading file: %v", err)
	}
	content := string(data)
	if !strings.Contains(content, "new/repo") {
		t.Fatalf("expected new/repo in updated file, got: %s", content)
	}
	if !strings.Contains(content, "old/repo") {
		t.Fatalf("expected old/repo to be preserved, got: %s", content)
	}
	if !strings.Contains(content, `"name"`) {
		t.Fatalf("expected name field to be preserved, got: %s", content)
	}
}

func TestStripJSONC_HandlesBackslashAtEndOfString(t *testing.T) {
	// A well-formed JSON string with an escaped quote.
	input := `{"key": "value with \"escaped\" quotes"}`
	got := string(stripJSONC([]byte(input)))
	if !strings.Contains(got, "escaped") {
		t.Fatalf("escaped content not preserved: %q", got)
	}
}

func TestStripJSONC_HandlesUnclosedBlockComment(t *testing.T) {
	// Should not panic or produce garbled output with unclosed /* comment.
	input := `{"key": "value" /* unclosed block comment`
	// Should not panic; result may be incomplete but must not include the comment text.
	got := string(stripJSONC([]byte(input)))
	if strings.Contains(got, "unclosed block comment") {
		t.Fatalf("unclosed comment content leaked into output: %q", got)
	}
}

func TestPreProcessDebugFileFlag_NoFlag(t *testing.T) {
	args := []string{"--file", "repos.list", "--debug"}
	got, auto, err := preProcessDebugFileFlag(args)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if auto != "" {
		t.Fatalf("expected no auto path, got %q", auto)
	}
	if len(got) != len(args) {
		t.Fatalf("args should be unchanged, got %v", got)
	}
}

func TestPreProcessDebugFileFlag_WithValue(t *testing.T) {
	args := []string{"--debug-file", "/tmp/my.log", "--debug"}
	got, auto, err := preProcessDebugFileFlag(args)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if auto != "" {
		t.Fatalf("expected no auto path when value is provided, got %q", auto)
	}
	if len(got) != len(args) {
		t.Fatalf("args should be unchanged, got %v", got)
	}
}

func TestPreProcessDebugFileFlag_BareAtEnd(t *testing.T) {
	args := []string{"--debug-file"}
	got, auto, err := preProcessDebugFileFlag(args)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if auto == "" {
		t.Fatalf("expected auto-generated path")
	}
	if len(got) != 2 || got[0] != "--debug-file" || got[1] != auto {
		t.Fatalf("unexpected processed args: %v", got)
	}
	// Clean up
	os.Remove(auto)
}

func TestPreProcessDebugFileFlag_BareBeforeFlag(t *testing.T) {
	args := []string{"--debug-file", "--debug"}
	got, auto, err := preProcessDebugFileFlag(args)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if auto == "" {
		t.Fatalf("expected auto-generated path")
	}
	if len(got) != 3 || got[0] != "--debug-file" || got[1] != auto || got[2] != "--debug" {
		t.Fatalf("unexpected processed args: %v", got)
	}
	// Clean up
	os.Remove(auto)
}

func TestValidateDevcontainerRelPath_Safe(t *testing.T) {
	for _, p := range []string{"devcontainer.json", "sub/devcontainer.json"} {
		if err := validateDevcontainerRelPath(p); err != nil {
			t.Fatalf("unexpected error for %q: %v", p, err)
		}
	}
}

func TestValidateDevcontainerRelPath_Unsafe(t *testing.T) {
	for _, p := range []string{"../escape", "/absolute", "-flag"} {
		if err := validateDevcontainerRelPath(p); err == nil {
			t.Fatalf("expected error for unsafe path %q", p)
		}
	}
}
