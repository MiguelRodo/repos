package sysutil

import (
	"bufio"
	"fmt"
	"os"
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

func CheckClonePrerequisites(reposFile string) error {
	if err := CheckPrerequisites(); err != nil {
		return err
	}
	needsHFCLI, err := clonePlanRequiresHuggingFaceCLI(reposFile)
	if err != nil {
		return err
	}
	if needsHFCLI {
		if _, err := exec.LookPath("huggingface-cli"); err != nil {
			return fmt.Errorf("error: 'huggingface-cli' is required for hf: repositories but was not found in PATH (install with: pip install huggingface_hub[cli])")
		}
	}
	return nil
}

func clonePlanRequiresHuggingFaceCLI(reposFile string) (bool, error) {
	f, err := os.Open(reposFile)
	if err != nil {
		return false, err
	}
	defer f.Close()

	fallbackIsHuggingFace := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := trimClonePrereqLine(sc.Text())
		if line == "" || lineIsGlobalFlagsOnly(line) {
			continue
		}
		first := strings.Fields(line)[0]
		if strings.HasPrefix(first, "@") {
			if fallbackIsHuggingFace {
				return true, nil
			}
			continue
		}
		repoNoRef := repoSpecWithoutRef(first)
		fallbackIsHuggingFace = isHuggingFaceSpec(repoNoRef)
		if fallbackIsHuggingFace {
			return true, nil
		}
	}
	if err := sc.Err(); err != nil {
		return false, err
	}
	return false, nil
}

func trimClonePrereqLine(line string) string {
	t := strings.TrimSpace(strings.TrimSuffix(line, "\r"))
	if t == "" || strings.HasPrefix(t, "#") {
		return ""
	}
	if i := strings.Index(t, " #"); i >= 0 {
		t = strings.TrimSpace(t[:i])
	}
	return strings.TrimSpace(t)
}

func lineIsGlobalFlagsOnly(line string) bool {
	parts := strings.Fields(line)
	if len(parts) == 0 {
		return false
	}
	for i := 0; i < len(parts); i++ {
		tok := parts[i]
		if tok == "--depth" {
			if i+1 >= len(parts) {
				return false
			}
			i++
			continue
		}
		if strings.HasPrefix(tok, "--depth=") {
			if strings.TrimPrefix(tok, "--depth=") == "" {
				return false
			}
			continue
		}
		switch tok {
		case "--codespaces", "--public", "--private", "--worktree", "--fetch-all-deferred", "--fetch-single", "--fetch-all", "--force":
		default:
			return false
		}
	}
	return true
}

func repoSpecWithoutRef(spec string) string {
	trimmed := strings.TrimSpace(spec)
	if idx := strings.LastIndex(trimmed, "@"); idx > 0 {
		return trimmed[:idx]
	}
	return trimmed
}

func isHuggingFaceSpec(spec string) bool {
	return strings.HasPrefix(strings.ToLower(strings.TrimSpace(spec)), "hf:")
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
