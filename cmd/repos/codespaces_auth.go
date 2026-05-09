package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

var scriptPathResolver = resolveCodespacesScriptPath

func runCodespacesAuth(args []string) error {
	scriptPath, err := scriptPathResolver()
	if err != nil {
		return err
	}

	cmdArgs := append([]string{scriptPath}, args...)
	cmd := exec.Command("bash", cmdArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("codespaces command failed with exit code %d", exitErr.ExitCode())
		}
		return fmt.Errorf("running codespaces helper: %w", err)
	}
	return nil
}

func resolveCodespacesScriptPath() (string, error) {
	exePath, exeErr := os.Executable()
	exeDir := filepath.Dir(exePath)

	// Lookup order:
	// 1) CWD-relative path for source checkouts and local development.
	// 2) executable directory relative path for install layouts that keep scripts beside binary assets.
	// 3) parent of executable directory for layouts that place binaries under bin/ (e.g. package managers).
	// The first match is returned as an absolute path.
	candidates := []string{
		filepath.Join("scripts", "helper", "codespaces-auth-add.sh"),
		filepath.Join(exeDir, "scripts", "helper", "codespaces-auth-add.sh"),
		filepath.Join(exeDir, "..", "scripts", "helper", "codespaces-auth-add.sh"),
	}
	for _, p := range candidates {
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			abs, err := filepath.Abs(p)
			if err != nil {
				return "", fmt.Errorf("resolving helper path %q: %w", p, err)
			}
			return abs, nil
		}
	}
	if exeErr != nil {
		return "", fmt.Errorf("could not find scripts/helper/codespaces-auth-add.sh (also failed to resolve executable path: %w)", exeErr)
	}
	return "", fmt.Errorf("could not find scripts/helper/codespaces-auth-add.sh")
}
