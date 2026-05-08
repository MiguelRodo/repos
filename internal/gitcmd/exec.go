package gitcmd

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
)

var sanitizeURLRegex = regexp.MustCompile(`(https?://)[^/@\s]+@`)

func RunGit(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
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

func SanitizeURL(in string) string {
	return sanitizeURLRegex.ReplaceAllString(in, "$1")
}
