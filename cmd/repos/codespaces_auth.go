package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"sort"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
)

func runCodespacesAuth(args []string) error {
	defaultFile := "repos.list"
	if _, err := os.Stat(defaultFile); err != nil {
		if _, err2 := os.Stat("repos-to-clone.list"); err2 == nil {
			defaultFile = "repos-to-clone.list"
		}
	}

	fs := flag.NewFlagSet("codespaces-auth", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	reposFile := fs.String("file", defaultFile, "repos list file")
	fs.StringVar(reposFile, "f", defaultFile, "repos list file")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		codespacesAuthUsage()
		return nil
	}
	if len(fs.Args()) > 0 {
		codespacesAuthUsage()
		return errors.New("unexpected positional arguments")
	}
	if _, err := exec.LookPath("gh"); err != nil {
		return errors.New("gh CLI is required but was not found on PATH")
	}

	token, err := resolveCodespacesToken()
	if err != nil {
		return err
	}

	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getting working directory: %w", err)
	}
	fallbackRemote, err := getCurrentRepoRemoteHTTPS(cwd)
	if err != nil {
		return err
	}

	repos, err := parseManagedReposFromFile(*reposFile, fallbackRemote)
	if err != nil {
		return err
	}

	fmt.Printf("Setting GH_TOKEN secret for %d repositories...\n", len(repos))
	for _, repo := range repos {
		fmt.Printf("  - %s\n", repo)
		if err := setRepoCodespacesSecret(repo, token); err != nil {
			return err
		}
	}
	fmt.Println("Done.")
	return nil
}

func codespacesAuthUsage() {
	fmt.Print(`Usage: repos codespaces-auth [--file <repo-list>]

Sets the GH_TOKEN Codespaces secret for each managed repository in repos.list.

Token lookup order:
  1) GH_TOKEN
  2) CODESPACES_TOKEN
  3) Secure terminal prompt

Options:
  -f, --file <file>   Path to repo list file (default: repos.list, fallback repos-to-clone.list)
  -h, --help          Show this help message.
`)
}

func resolveCodespacesToken() (string, error) {
	if tok := strings.TrimSpace(os.Getenv("GH_TOKEN")); tok != "" {
		return tok, nil
	}
	if tok := strings.TrimSpace(os.Getenv("CODESPACES_TOKEN")); tok != "" {
		return tok, nil
	}
	return promptTokenSecurely()
}

func promptTokenSecurely() (string, error) {
	stdinInfo, err := os.Stdin.Stat()
	if err != nil {
		return "", fmt.Errorf("checking stdin: %w", err)
	}
	if stdinInfo.Mode()&os.ModeCharDevice == 0 {
		return "", errors.New("no GH_TOKEN or CODESPACES_TOKEN set and stdin is not interactive")
	}

	fmt.Fprint(os.Stderr, "Enter token to store as GH_TOKEN secret: ")
	disable := exec.Command("stty", "-echo")
	disable.Stdin = os.Stdin
	if err := disable.Run(); err != nil {
		fmt.Fprintln(os.Stderr)
		return "", fmt.Errorf("unable to prompt securely (failed to disable terminal echo): %w", err)
	}
	defer func() {
		enable := exec.Command("stty", "echo")
		enable.Stdin = os.Stdin
		_ = enable.Run()
		fmt.Fprintln(os.Stderr)
	}()

	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", fmt.Errorf("reading token: %w", err)
	}
	token := strings.TrimSpace(line)
	if token == "" {
		return "", errors.New("token cannot be empty")
	}
	return token, nil
}

func parseManagedReposFromFile(path string, fallbackRemote string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("opening repos file %q: %w", path, err)
	}
	defer f.Close()
	return parseManagedRepos(f, fallbackRemote)
}

func parseManagedRepos(r io.Reader, fallbackRemote string) ([]string, error) {
	fallbackRepo, err := ownerRepoFromRemote(fallbackRemote)
	if err != nil {
		return nil, fmt.Errorf("invalid fallback repository remote %q: %w", fallbackRemote, err)
	}

	seen := map[string]struct{}{}
	sc := bufio.NewScanner(r)
	lineNum := 0
	for sc.Scan() {
		lineNum++
		trimmed := trimLine(sc.Text())
		if trimmed == "" || lineIsGlobalFlagsOnly(trimmed) {
			continue
		}

		tokens := strings.Fields(trimmed)
		if len(tokens) == 0 {
			continue
		}
		first := tokens[0]
		if strings.HasPrefix(first, "@") {
			seen[fallbackRepo] = struct{}{}
			continue
		}

		repoNoRef, _ := splitRepoSpec(first)
		if strings.HasPrefix(repoNoRef, "-") || strings.Contains(repoNoRef, "..") {
			return nil, fmt.Errorf("invalid repository spec on line %d: %s", lineNum, gitcmd.SanitizeURL(first))
		}
		ownerRepo, err := ownerRepoFromRemote(specToHTTPS(repoNoRef))
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: skipping unsupported repository on line %d: %s\n", lineNum, gitcmd.SanitizeURL(first))
			continue
		}
		seen[ownerRepo] = struct{}{}
		fallbackRepo = ownerRepo
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("reading repos list: %w", err)
	}
	if len(seen) == 0 {
		return nil, errors.New("no managed repositories found in repos list")
	}

	repos := make([]string, 0, len(seen))
	for repo := range seen {
		repos = append(repos, repo)
	}
	sort.Strings(repos)
	return repos, nil
}

func ownerRepoFromRemote(remote string) (string, error) {
	trimmed := strings.TrimSpace(strings.TrimSuffix(remote, ".git"))
	if ownerRepoRegex.MatchString(trimmed) {
		return trimmed, nil
	}
	u, err := url.Parse(trimmed)
	if err != nil || u.Path == "" || u.Host == "" {
		return "", errors.New("not a valid repository URL")
	}
	parts := strings.Split(strings.Trim(u.Path, "/"), "/")
	if len(parts) < 2 {
		return "", errors.New("missing owner/repo path")
	}
	candidate := parts[0] + "/" + parts[1]
	if !ownerRepoRegex.MatchString(candidate) {
		return "", errors.New("invalid owner/repo")
	}
	return candidate, nil
}

func setRepoCodespacesSecret(repo, token string) error {
	cmd := exec.Command("gh", "secret", "set", "GH_TOKEN", "--repo", repo, "--app", "codespaces")
	cmd.Env = append(os.Environ(), "GH_TOKEN="+token)
	cmd.Stdin = strings.NewReader(token)
	out, err := cmd.CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			return fmt.Errorf("failed setting GH_TOKEN secret for %s: %w", repo, err)
		}
		return fmt.Errorf("failed setting GH_TOKEN secret for %s: %s", repo, gitcmd.SanitizeURL(msg))
	}
	return nil
}
