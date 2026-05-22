package gitcmd

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"

	"github.com/MiguelRodo/repos/v2/internal/sysutil"
)

var sanitizeURLRegex = regexp.MustCompile(`(https?://)[^/\s]+@`)

func RunGit(dir string, args ...string) (string, error) {
	needsAuth := false
	for _, arg := range args {
		if arg == "push" || arg == "fetch" || arg == "clone" || arg == "ls-remote" {
			needsAuth = true
			break
		}
	}

	finalArgs := args
	if needsAuth {
		token, err := sysutil.DiscoverGitHubToken()
		if err == nil && token != "" {
			inlineHelper := fmt.Sprintf("!f() { echo \"password=%s\"; }; f", token)
			finalArgs = append([]string{"-c", "credential.helper=" + inlineHelper}, args...)
		}
	}

	cmd := exec.Command("git", finalArgs...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.Stdin = nil
	cmd.Env = NonInteractiveGitEnv()
	out, err := cmd.CombinedOutput()
	trimmed := strings.TrimSpace(string(out))
	if err != nil {
		return trimmed, fmt.Errorf("git %s failed: %s", SanitizeURL(strings.Join(args, " ")), SanitizeURL(trimmed))
	}
	return trimmed, nil
}

func RunHuggingFaceCLI(dir string, args ...string) (string, error) {
	cmd := exec.Command("huggingface-cli", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.Stdin = nil
	cmd.Env = NonInteractiveHFEnv()
	out, err := cmd.CombinedOutput()
	trimmed := strings.TrimSpace(string(out))
	if err != nil {
		return trimmed, fmt.Errorf("huggingface-cli %s failed: %s", strings.Join(args, " "), trimmed)
	}
	return trimmed, nil
}

func NonInteractiveGitEnv() []string {
	env := os.Environ()
	env = append(env, "GIT_TERMINAL_PROMPT=0")
	if runtime.GOOS != "windows" {
		env = append(env, "GIT_ASKPASS=/bin/false")
		if _, ok := os.LookupEnv("GIT_SSH_COMMAND"); !ok {
			env = append(env, "GIT_SSH_COMMAND=ssh -oBatchMode=yes")
		}
	}
	return env
}

func NonInteractiveHFEnv() []string {
	env := make([]string, 0, len(os.Environ())+1)
	for _, entry := range os.Environ() {
		if strings.HasPrefix(entry, "HF_TOKEN=") {
			continue
		}
		env = append(env, entry)
	}
	if token, ok := os.LookupEnv("HF_TOKEN"); ok {
		env = append(env, "HF_TOKEN="+token)
	}
	return env
}

func SanitizeURL(in string) string {
	return sanitizeURLRegex.ReplaceAllString(in, "$1")
}
