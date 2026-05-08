package sysutil

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestCheckGitHubCLIAuthMissingGh(t *testing.T) {
	origPath := os.Getenv("PATH")
	t.Cleanup(func() { _ = os.Setenv("PATH", origPath) })
	if err := os.Setenv("PATH", t.TempDir()); err != nil {
		t.Fatalf("set PATH: %v", err)
	}

	err := CheckGitHubCLIAuth()
	if err == nil || !strings.Contains(err.Error(), "'gh' is required") {
		t.Fatalf("expected missing gh error, got: %v", err)
	}
}

func TestCheckGitHubCLIAuthStatusSuccess(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX gh stub script is not supported on Windows")
	}
	origPath := os.Getenv("PATH")
	t.Cleanup(func() { _ = os.Setenv("PATH", origPath) })

	tmp := t.TempDir()
	ghPath := filepath.Join(tmp, "gh")
	script := `#!/bin/sh
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then exit 0; fi
exit 1
`
	if err := os.WriteFile(ghPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake gh: %v", err)
	}
	if err := os.Setenv("PATH", tmp); err != nil {
		t.Fatalf("set PATH: %v", err)
	}

	if err := CheckGitHubCLIAuth(); err != nil {
		t.Fatalf("expected success, got error: %v", err)
	}
}

func TestCheckGitHubCLIAuthStatusFailure(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX gh stub script is not supported on Windows")
	}
	origPath := os.Getenv("PATH")
	t.Cleanup(func() { _ = os.Setenv("PATH", origPath) })

	tmp := t.TempDir()
	ghPath := filepath.Join(tmp, "gh")
	script := `#!/bin/sh
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then echo "not logged in"; exit 1; fi
exit 1
`
	if err := os.WriteFile(ghPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake gh: %v", err)
	}
	if err := os.Setenv("PATH", tmp); err != nil {
		t.Fatalf("set PATH: %v", err)
	}

	err := CheckGitHubCLIAuth()
	if err == nil || !strings.Contains(err.Error(), "not logged in") {
		t.Fatalf("expected auth status failure with output, got: %v", err)
	}
}
