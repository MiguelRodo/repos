package sysutil

import (
	"errors"
	"os"
	"os/exec"
	"strings"
	"sync"
)

var (
	activeToken string
	tokenErr    error
	authOnce    sync.Once
)

func DiscoverGitHubToken() (string, error) {
	authOnce.Do(func() {
		// Track A: Environment Context Inspection
		for _, env := range []string{"GITHUB_PAT", "GH_TOKEN", "GITHUB_TOKEN"} {
			if val := strings.TrimSpace(os.Getenv(env)); val != "" {
				activeToken = val
				return
			}
		}

		// Track B: GitHub CLI Engine Query
		if path, err := exec.LookPath("gh"); err == nil {
			cmd := exec.Command(path, "auth", "token")
			if out, err := cmd.Output(); err == nil {
				val := strings.TrimSpace(string(out))
				if val != "" {
					activeToken = val
					return
				}
			}
		}

		// Track C: System Git Credential Helper Interrogation
		cmd := exec.Command("git", "credential", "fill")
		cmd.Stdin = strings.NewReader("protocol=https\nhost=github.com\n\n")
		if out, err := cmd.Output(); err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				if strings.HasPrefix(line, "password=") {
					activeToken = strings.TrimPrefix(line, "password=")
					return
				}
			}
		}

		tokenErr = errors.New("Error: GitHub authentication token not found.\n" +
			"Authentication is required to interact with remote repositories via git push or fetch.\n\n" +
			"To resolve this, please execute one of the following options:\n" +
			"Option A (Environment Variable):\n" +
			"    Set the GITHUB_PAT environment variable in your active terminal profile.\n" +
			"Option B (GitHub CLI):\n" +
			"    Install the 'gh' utility and run 'gh auth login' to authenticate your host.\n" +
			"Option C (Git Helper Setup):\n" +
			"    Approve host access directly inside your local system credential helper:\n" +
			"    git credential approve < echo -e \"protocol=https\\nhost=github.com\\nusername=user\\npassword=YOUR_PAT\"")
	})

	return activeToken, tokenErr
}

// ResetAuthCache is used for testing
func ResetAuthCache() {
	authOnce = sync.Once{}
	activeToken = ""
	tokenErr = nil
}
