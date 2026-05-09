package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveCodespacesScriptPathFromCWD(t *testing.T) {
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "scripts", "helper", "codespaces-auth-add.sh")
	if err := os.MkdirAll(filepath.Dir(scriptPath), 0o755); err != nil {
		t.Fatalf("mkdir script dir: %v", err)
	}
	if err := os.WriteFile(scriptPath, []byte("#!/usr/bin/env bash\nexit 0\n"), 0o755); err != nil {
		t.Fatalf("write script: %v", err)
	}

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	t.Cleanup(func() { _ = os.Chdir(oldWD) })
	if err := os.Chdir(tmp); err != nil {
		t.Fatalf("chdir tmp: %v", err)
	}

	got, err := resolveCodespacesScriptPath()
	if err != nil {
		t.Fatalf("resolveCodespacesScriptPath error: %v", err)
	}
	if got != scriptPath {
		t.Fatalf("expected %q, got %q", scriptPath, got)
	}
}

func TestRunCodespacesAuthExecutesHelperWithArgs(t *testing.T) {
	tmp := t.TempDir()
	argsFile := filepath.Join(tmp, "args.txt")
	scriptPath := filepath.Join(tmp, "codespaces-auth-add.sh")
	scriptBody := "#!/usr/bin/env bash\nprintf '%s' \"$*\" > \"$ARGS_FILE\"\n"
	if err := os.WriteFile(scriptPath, []byte(scriptBody), 0o755); err != nil {
		t.Fatalf("write helper script: %v", err)
	}

	origResolver := resolveCodespacesScriptPathFunc
	resolveCodespacesScriptPathFunc = func() (string, error) { return scriptPath, nil }
	t.Cleanup(func() {
		resolveCodespacesScriptPathFunc = origResolver
	})

	oldEnv := os.Getenv("ARGS_FILE")
	if err := os.Setenv("ARGS_FILE", argsFile); err != nil {
		t.Fatalf("setenv: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Setenv("ARGS_FILE", oldEnv)
	})

	if err := runCodespacesAuth([]string{"-f", "repos.list", "-d", ".devcontainer/devcontainer.json"}); err != nil {
		t.Fatalf("runCodespacesAuth returned error: %v", err)
	}

	raw, err := os.ReadFile(argsFile)
	if err != nil {
		t.Fatalf("read args file: %v", err)
	}
	got := strings.TrimSpace(string(raw))
	if got != "-f repos.list -d .devcontainer/devcontainer.json" {
		t.Fatalf("unexpected helper args: %q", got)
	}
}
