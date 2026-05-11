package sysutil

import (
	"fmt"
	"os/exec"
	"strings"
)

func CheckPrerequisites() error {
	for _, tool := range []string{"git"} {
		if _, err := exec.LookPath(tool); err != nil {
			return fmt.Errorf("error: '%s' is required but not found in PATH", tool)
		}
	}
	return nil
}

func CheckGitHubCLIAuth() error {
	if _, err := exec.LookPath("gh"); err != nil {
		return fmt.Errorf("error: 'gh' is required but not found in PATH")
	}
	out, err := exec.Command("gh", "auth", "status").CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = "run 'gh auth login'"
		}
		return fmt.Errorf("error: GitHub CLI authentication required: %s", msg)
	}
	return nil
}
