package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunWorkspaceGeneratesFoldersFromReposList(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "workspace")
	if err := os.MkdirAll(projectDir, 0o755); err != nil {
		t.Fatalf("mkdir project dir: %v", err)
	}
	listPath := filepath.Join(projectDir, "repos.list")
	content := strings.Join([]string{
		"@dev",
		"acme/repo",
		"@feature --worktree",
		"",
	}, "\n")
	if err := os.WriteFile(listPath, []byte(content), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Chdir(oldWD)
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir: %v", err)
	}

	if err := runWorkspace(nil); err != nil {
		t.Fatalf("runWorkspace error: %v", err)
	}

	wsPath := findWorkspaceFile(projectDir)
	data, err := os.ReadFile(wsPath)
	if err != nil {
		t.Fatalf("read workspace file: %v", err)
	}
	got := string(data)
	for _, want := range []string{
		`"path": "."`,
		`"path": "../workspace-dev"`,
		`"path": "../repo"`,
		`"path": "../repo-feature"`,
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("workspace missing %q:\n%s", want, got)
		}
	}
}

func TestRunWorkspacePreservesExistingExtraFields(t *testing.T) {
	tmp := t.TempDir()
	projectDir := filepath.Join(tmp, "workspace")
	if err := os.MkdirAll(projectDir, 0o755); err != nil {
		t.Fatalf("mkdir project dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(projectDir, "repos.list"), []byte("acme/repo\n"), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}
	wsPath := filepath.Join(projectDir, "entire-project.code-workspace")
	existing := `{"folders":[{"path":"old"}],"settings":{"x":1}}`
	if err := os.WriteFile(wsPath, []byte(existing), 0o644); err != nil {
		t.Fatalf("write workspace: %v", err)
	}

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Chdir(oldWD)
	})
	if err := os.Chdir(projectDir); err != nil {
		t.Fatalf("chdir: %v", err)
	}

	if err := runWorkspace(nil); err != nil {
		t.Fatalf("runWorkspace error: %v", err)
	}

	data, err := os.ReadFile(wsPath)
	if err != nil {
		t.Fatalf("read workspace file: %v", err)
	}
	got := string(data)
	if !strings.Contains(got, `"settings": {`) {
		t.Fatalf("expected settings to be preserved, got:\n%s", got)
	}
	if !strings.Contains(got, `"path": "../repo"`) {
		t.Fatalf("expected regenerated folders, got:\n%s", got)
	}
}
