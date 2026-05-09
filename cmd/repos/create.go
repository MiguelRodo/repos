package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
	"github.com/MiguelRodo/repos/internal/sysutil"
)

var ghRepoExistsFunc = ghRepoExists
var ghCreateRepoFunc = ghCreateRepo
var githubNameRegex = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

func runCreate(args []string) error {
	defaultFile := "repos.list"
	if _, err := os.Stat(defaultFile); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			if _, err2 := os.Stat("repos-to-clone.list"); err2 == nil {
				defaultFile = "repos-to-clone.list"
			} else if err2 != nil && !errors.Is(err2, os.ErrNotExist) {
				return fmt.Errorf("error checking fallback list file: %w", err2)
			}
		} else {
			return fmt.Errorf("error checking list file '%s': %w", defaultFile, err)
		}
	}

	fs := flag.NewFlagSet("create", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	reposFile := fs.String("file", defaultFile, "repos list file")
	fs.StringVar(reposFile, "f", defaultFile, "repos list file")
	publicFlag := fs.Bool("public", false, "create repos as public by default")
	fs.BoolVar(publicFlag, "p", false, "create repos as public by default")
	privateFlag := fs.Bool("private", false, "create repos as private by default")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		createUsage()
		return nil
	}
	if *publicFlag && *privateFlag {
		return errors.New("cannot use both --public and --private")
	}
	if _, err := os.Stat(*reposFile); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("file '%s' not found", *reposFile)
		}
		return fmt.Errorf("error accessing file '%s': %w", *reposFile, err)
	}
	if err := sysutil.CheckGitHubCLIAuth(); err != nil {
		return err
	}

	privateDefault := true
	cliVisibilitySet := false
	if *publicFlag {
		privateDefault = false
		cliVisibilitySet = true
	}
	if *privateFlag {
		privateDefault = true
		cliVisibilitySet = true
	}

	if !cliVisibilitySet {
		fromFile, err := parseCreateGlobalVisibility(*reposFile, privateDefault)
		if err != nil {
			return err
		}
		privateDefault = fromFile
	}

	return processCreateFile(*reposFile, privateDefault)
}

func createUsage() {
	fmt.Print(`Usage: repos create [--file <repo-list>] [--public|--private]

Create missing GitHub repositories listed in repos.list.

Each non-blank, non-# line of <repo-list> can be:
  owner/repo[@branch] [target_directory]
  @branch [target_directory]

Only owner/repo specs are used for repository creation.
Global/line visibility flags --public/--private are supported.
`)
}

func parseCreateGlobalVisibility(reposFile string, privateDefault bool) (bool, error) {
	f, err := os.Open(reposFile)
	if err != nil {
		return privateDefault, err
	}
	defer f.Close()

	privateValue := privateDefault
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := trimLine(sc.Text())
		if line == "" || !lineIsGlobalFlagsOnly(line) {
			continue
		}
		for _, tok := range strings.Fields(line) {
			switch tok {
			case "--public":
				privateValue = false
			case "--private":
				privateValue = true
			}
		}
	}
	if err := sc.Err(); err != nil {
		return privateDefault, err
	}
	return privateValue, nil
}

func processCreateFile(reposFile string, privateDefault bool) error {
	f, err := os.Open(reposFile)
	if err != nil {
		return err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := trimLine(sc.Text())
		if line == "" || lineIsGlobalFlagsOnly(line) {
			continue
		}
		if err := processCreateLine(line, privateDefault); err != nil {
			return err
		}
	}
	return sc.Err()
}

func processCreateLine(line string, privateDefault bool) error {
	parts := strings.Fields(line)
	if len(parts) == 0 {
		return nil
	}
	repoSpec := parts[0]
	if strings.HasPrefix(repoSpec, "@") {
		return nil
	}

	privateValue := privateDefault
	for _, tok := range parts[1:] {
		switch tok {
		case "--public":
			privateValue = false
		case "--private":
			privateValue = true
		}
	}

	ownerRepo, err := extractOwnerRepo(repoSpec)
	if err != nil {
		return err
	}

	exists, err := ghRepoExistsFunc(ownerRepo)
	if err != nil {
		return err
	}
	if exists {
		fmt.Printf("Exists: %s\n", ownerRepo)
		return nil
	}

	fmt.Printf("Creating repo %s ... ", ownerRepo)
	if err := ghCreateRepoFunc(ownerRepo, privateValue); err != nil {
		fmt.Println("failed.")
		return err
	}
	fmt.Println("done.")
	return nil
}

func extractOwnerRepo(repoSpec string) (string, error) {
	sanitizedSpec := gitcmd.SanitizeURL(repoSpec)
	repoNoRef, _ := splitRepoSpec(repoSpec)
	// Normalize from the raw spec so credentialed/SSH GitHub URLs are parsed
	// correctly; use sanitizedSpec only for user-facing errors.
	normalizedSpec := normaliseRemoteToHTTPS(repoNoRef)
	switch {
	case strings.HasPrefix(normalizedSpec, "https://github.com/"):
		repoNoRef = strings.TrimPrefix(normalizedSpec, "https://github.com/")
	case strings.HasPrefix(normalizedSpec, "http://github.com/"):
		repoNoRef = strings.TrimPrefix(normalizedSpec, "http://github.com/")
	}
	repoNoRef = strings.TrimSuffix(repoNoRef, ".git")
	repoNoRef = strings.TrimSpace(repoNoRef)

	if !ownerRepoRegex.MatchString(repoNoRef) {
		return "", fmt.Errorf("error: repository spec must be in 'owner/repo' format: %s", sanitizedSpec)
	}
	owner, repo, ok := strings.Cut(repoNoRef, "/")
	if !ok || !githubNameRegex.MatchString(owner) || !githubNameRegex.MatchString(repo) {
		return "", fmt.Errorf("error: repository spec must be in 'owner/repo' format: %s", sanitizedSpec)
	}
	return repoNoRef, nil
}

func ghRepoExists(ownerRepo string) (bool, error) {
	cmd := exec.Command("gh", "repo", "view", ownerRepo, "--json", "nameWithOwner")
	out, err := cmd.CombinedOutput()
	if err == nil {
		return true, nil
	}
	if isRepoNotFoundError(string(out)) {
		return false, nil
	}
	return false, fmt.Errorf("error checking repository %s: %s", ownerRepo, strings.TrimSpace(string(out)))
}

func ghCreateRepo(ownerRepo string, private bool) error {
	visibility := "--private"
	if !private {
		visibility = "--public"
	}
	cmd := exec.Command("gh", "repo", "create", ownerRepo, visibility, "--confirm")
	cmd.Env = append(os.Environ(), "GH_PROMPT_DISABLED=1")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error creating repository %s: %s", ownerRepo, strings.TrimSpace(string(out)))
	}
	return nil
}

func isRepoNotFoundError(out string) bool {
	s := strings.ToLower(out)
	return strings.Contains(s, "could not resolve to a repository") ||
		strings.Contains(s, "not found") ||
		strings.Contains(s, "http 404")
}
