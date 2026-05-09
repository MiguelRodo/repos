package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
	"github.com/MiguelRodo/repos/internal/parser"
	"golang.org/x/term"
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

	absReposFile, err := filepath.Abs(*reposFile)
	if err != nil {
		return fmt.Errorf("resolving repos file path: %w", err)
	}
	repos, err := parseManagedReposFromFile(absReposFile)
	if err != nil {
		return err
	}

	repoWord := "repositories"
	if len(repos) == 1 {
		repoWord = "repository"
	}
	fmt.Printf("Setting GH_TOKEN secret for %d %s...\n", len(repos), repoWord)
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
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", errors.New("no GH_TOKEN or CODESPACES_TOKEN set and stdin is not interactive")
	}

	fmt.Fprint(os.Stderr, "Enter token to store as GH_TOKEN secret: ")
	line, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return "", fmt.Errorf("reading token: %w", err)
	}
	token := strings.TrimSpace(string(line))
	if token == "" {
		return "", errors.New("token cannot be empty")
	}
	return token, nil
}

func parseManagedReposFromFile(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("opening repos file %q: %w", path, err)
	}
	defer f.Close()
	listDir := filepath.Dir(path)
	return parseManagedRepos(f, func() (string, error) {
		return getCurrentRepoRemoteHTTPS(listDir)
	})
}

func parseManagedRepos(r io.Reader, resolveFallbackRemote func() (string, error)) ([]string, error) {
	var fallbackRepo string
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
			if fallbackRepo == "" {
				fallbackRemote, err := resolveFallbackRemote()
				if err != nil {
					return nil, fmt.Errorf("line %d: cannot resolve fallback repository for %q: %w", lineNum, first, err)
				}
				fallbackRepo, err = parser.OwnerRepoFromRemote(fallbackRemote)
				if err != nil {
					return nil, fmt.Errorf("line %d: invalid fallback repository remote %q: %w", lineNum, fallbackRemote, err)
				}
			}
			seen[fallbackRepo] = struct{}{}
			continue
		}

		repoNoRef, _ := splitRepoSpec(first)
		if strings.HasPrefix(repoNoRef, "-") || strings.Contains(repoNoRef, "..") {
			return nil, fmt.Errorf("invalid repository spec on line %d: %s", lineNum, gitcmd.SanitizeURL(first))
		}
		ownerRepo, err := parser.OwnerRepoFromRemote(specToHTTPS(repoNoRef))
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

func setRepoCodespacesSecret(repo, token string) error {
	cmd := exec.Command("gh", "secret", "set", "GH_TOKEN", "--repo", repo, "--app", "codespaces")
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
