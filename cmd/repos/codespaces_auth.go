package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
	"github.com/MiguelRodo/repos/internal/parser"
	"golang.org/x/term"
)

// stringSliceFlag is a flag.Value that accumulates multiple --flag values into a slice.
type stringSliceFlag []string

func (s *stringSliceFlag) String() string { return strings.Join(*s, ", ") }
func (s *stringSliceFlag) Set(v string) error {
	*s = append(*s, v)
	return nil
}

func runCodespacesAuth(args []string) error {
	defaultFile := "repos.list"
	if _, err := os.Stat(defaultFile); err != nil {
		if _, err2 := os.Stat("repos-to-clone.list"); err2 == nil {
			defaultFile = "repos-to-clone.list"
		}
	}

	// Pre-process --debug-file to support the optional-value form.
	processedArgs, autoDebugPath, err := preProcessDebugFileFlag(args)
	if err != nil {
		return err
	}
	if autoDebugPath != "" {
		fmt.Fprintf(os.Stderr, "Debug output will be written to: %s\n", autoDebugPath)
	}

	cfs := flag.NewFlagSet("codespaces", flag.ContinueOnError)
	cfs.SetOutput(os.Stderr)
	reposFile := cfs.String("file", defaultFile, "repos list file")
	cfs.StringVar(reposFile, "f", defaultFile, "repos list file")
	help := cfs.Bool("help", false, "show help")
	cfs.BoolVar(help, "h", false, "show help")

	// Devcontainer modification flags
	var devcontainerPaths stringSliceFlag
	cfs.Var(&devcontainerPaths, "devcontainer", "path relative to .devcontainer/ to update (can be specified multiple times; default: devcontainer.json)")
	cfs.Var(&devcontainerPaths, "d", "path relative to .devcontainer/ to update (shorthand for --devcontainer)")
	allDevcontainers := cfs.Bool("all", false, "update all devcontainer.json files under .devcontainer/")
	permissions := cfs.String("permissions", "default", `permissions level for repositories block: "default", "all", or "contents"`)
	dryRun := cfs.Bool("dry-run", false, "print devcontainer.json changes to stdout without writing; also skips setting GH_TOKEN secret")
	cfs.BoolVar(dryRun, "n", false, "same as --dry-run")

	// Debug flags
	debug := cfs.Bool("debug", false, "enable debug output")
	debugFile := cfs.String("debug-file", "", "write debug output to file (auto-generate temp if no path given)")

	if err := cfs.Parse(processedArgs); err != nil {
		return err
	}
	if *help {
		codespacesAuthUsage()
		return nil
	}
	if len(cfs.Args()) > 0 {
		codespacesAuthUsage()
		return errors.New("unexpected positional arguments")
	}

	// A non-empty --debug-file implies --debug.
	if *debugFile != "" {
		*debug = true
	}

	debugWriter, closeDebug, err := openDebugWriter(*debugFile)
	if err != nil {
		return err
	}
	defer closeDebug()

	dbg := func(format string, a ...any) {
		if !*debug {
			return
		}
		w := debugWriter
		if w == nil {
			w = os.Stderr
		}
		fmt.Fprintf(w, "[DEBUG codespaces-go] "+format+"\n", a...)
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
	dbg("using repos file: %s", absReposFile)
	repos, err := parseManagedReposFromFile(absReposFile)
	if err != nil {
		return err
	}
	dbg("found %d managed repositories", len(repos))

	// Set GH_TOKEN Codespaces secret for each repository.
	if *dryRun {
		fmt.Printf("DRY-RUN: would set GH_TOKEN Codespaces secret for %d repositories:\n", len(repos))
		for _, repo := range repos {
			fmt.Printf("  - %s\n", repo)
		}
	} else {
		repoWord := "repositories"
		if len(repos) == 1 {
			repoWord = "repository"
		}
		fmt.Printf("Setting GH_TOKEN secret for %d %s...\n", len(repos), repoWord)
		for _, repo := range repos {
			fmt.Printf("  - %s\n", repo)
			dbg("setting GH_TOKEN secret for %s", repo)
			if err := setRepoCodespacesSecret(repo, token); err != nil {
				return err
			}
		}
		fmt.Println("Done.")
	}

	// Determine devcontainer.json paths to update.
	var dcPaths []string
	if *allDevcontainers {
		dbg("scanning .devcontainer/ for all devcontainer.json files")
		dcPaths, err = findAllDevcontainerFiles(".devcontainer")
		if err != nil {
			return err
		}
		dbg("found %d devcontainer.json files", len(dcPaths))
	} else if len(devcontainerPaths) > 0 {
		for _, p := range devcontainerPaths {
			if err := validateDevcontainerRelPath(p); err != nil {
				return err
			}
			resolved := filepath.Join(".devcontainer", filepath.FromSlash(p))
			dbg("resolved devcontainer path: %s", resolved)
			dcPaths = append(dcPaths, resolved)
		}
	} else {
		// Default: .devcontainer/devcontainer.json
		dcPaths = []string{filepath.Join(".devcontainer", "devcontainer.json")}
		dbg("using default devcontainer path: %s", dcPaths[0])
	}

	// Update each devcontainer.json.
	for _, p := range dcPaths {
		dbg("updating %s", p)
		if err := updateDevcontainerFile(p, repos, *permissions, *dryRun); err != nil {
			return err
		}
	}

	return nil
}

func codespacesAuthUsage() {
	fmt.Print(`Usage: repos codespaces [--file <repo-list>] [--devcontainer <path>...] [--all]
                        [--permissions default|all|contents] [--dry-run]
                        [--debug] [--debug-file [file]]

Sets the GH_TOKEN Codespaces secret for each managed repository and updates
devcontainer.json with the customizations.codespaces.repositories block.

Token lookup order:
  1) GH_TOKEN
  2) CODESPACES_TOKEN
  3) Secure terminal prompt

Options:
  -f, --file <file>           Path to repo list file (default: repos.list,
                              fallback repos-to-clone.list)
  -d, --devcontainer <path>   Path relative to .devcontainer/ to update
                              (can be specified multiple times;
                              default: devcontainer.json)
  --all                       Update all devcontainer.json files found under
                              .devcontainer/
  --permissions <level>       Permissions level for the repositories block:
                                default  - actions/contents write, packages read,
                                           workflows write (default)
                                all      - write-all
                                contents - contents write only
  -n, --dry-run               Print devcontainer.json changes to stdout without
                              writing; also skips setting GH_TOKEN secret
  --debug                     Enable debug output to stderr.
  --debug-file [file]         Enable debug output to file (auto-generate temp
                              if no path given).
  -h, --help                  Show this help message.
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
		if strings.HasPrefix(repoNoRef, "-") || hasPathTraversal(repoNoRef) {
			return nil, fmt.Errorf("invalid repository spec on line %d: %s", lineNum, gitcmd.SanitizeURL(first))
		}
		ownerRepo, err := parser.OwnerRepoFromRemote(specToHTTPS(repoNoRef))
		if err != nil {
			fmt.Fprintf(
				os.Stderr,
				"Warning: skipping unsupported repository on line %d (%s): %s\n",
				lineNum,
				err.Error(),
				gitcmd.SanitizeURL(first),
			)
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

func hasPathTraversal(spec string) bool {
	candidates := []string{spec}
	if decoded, err := url.PathUnescape(spec); err == nil {
		candidates = append(candidates, decoded)
	}
	for _, c := range candidates {
		normalized := strings.ReplaceAll(c, `\`, "/")
		for _, part := range strings.Split(normalized, "/") {
			if part == ".." {
				return true
			}
		}
		cleaned := filepath.Clean(normalized)
		if cleaned == ".." || strings.HasPrefix(cleaned, "../") {
			return true
		}
	}
	return false
}

// findAllDevcontainerFiles returns all devcontainer.json files found under dir.
func findAllDevcontainerFiles(dir string) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, werr error) error {
		if werr != nil {
			return werr
		}
		if !d.IsDir() && d.Name() == "devcontainer.json" {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf(".devcontainer/ directory not found")
		}
		return nil, fmt.Errorf("scanning %s: %w", dir, err)
	}
	if len(paths) == 0 {
		return nil, fmt.Errorf("no devcontainer.json files found under %s", dir)
	}
	return paths, nil
}

// stripJSONC removes // line comments and /* */ block comments, and strips
// trailing commas before } or ], yielding valid JSON from JSONC input.
func stripJSONC(data []byte) []byte {
	out := make([]byte, 0, len(data))
	i := 0
	for i < len(data) {
		b := data[i]

		// String literal: copy verbatim, handling escapes.
		if b == '"' {
			start := i
			i++
			for i < len(data) {
				if data[i] == '\\' {
					i++ // skip the backslash
					if i < len(data) {
						i++ // skip the escaped character
					}
					continue
				}
				if data[i] == '"' {
					i++
					break
				}
				i++
			}
			out = append(out, data[start:i]...)
			continue
		}

		// Line comment: skip to end of line.
		if b == '/' && i+1 < len(data) && data[i+1] == '/' {
			for i < len(data) && data[i] != '\n' {
				i++
			}
			continue
		}

		// Block comment: skip to */ (or EOF if unclosed).
		if b == '/' && i+1 < len(data) && data[i+1] == '*' {
			i += 2
			closed := false
			for i+1 < len(data) {
				if data[i] == '*' && data[i+1] == '/' {
					i += 2
					closed = true
					break
				}
				i++
			}
			if !closed {
				// Consume the last remaining byte of the unclosed comment.
				i++
			}
			continue
		}

		// Trailing comma: , followed (possibly by whitespace) by } or ].
		if b == ',' {
			j := i + 1
			for j < len(data) && (data[j] == ' ' || data[j] == '\t' || data[j] == '\n' || data[j] == '\r') {
				j++
			}
			if j < len(data) && (data[j] == '}' || data[j] == ']') {
				i++ // skip the comma
				continue
			}
		}

		out = append(out, b)
		i++
	}
	return out
}

// buildRepoPermissionsBlock constructs the JSON object for the repositories block.
func buildRepoPermissionsBlock(repos []string, permissions string) map[string]interface{} {
	block := make(map[string]interface{}, len(repos))
	for _, repo := range repos {
		switch permissions {
		case "all":
			block[repo] = map[string]interface{}{
				"permissions": "write-all",
			}
		case "contents":
			block[repo] = map[string]interface{}{
				"permissions": map[string]interface{}{
					"contents": "write",
				},
			}
		default:
			block[repo] = map[string]interface{}{
				"permissions": map[string]interface{}{
					"actions":   "write",
					"contents":  "write",
					"packages":  "read",
					"workflows": "write",
				},
			}
		}
	}
	return block
}

// mergeRepoPermissions drills into doc["customizations"]["codespaces"]["repositories"]
// and merges reposBlock, creating intermediate maps as needed.
func mergeRepoPermissions(doc map[string]interface{}, reposBlock map[string]interface{}) {
	customizations, _ := doc["customizations"].(map[string]interface{})
	if customizations == nil {
		customizations = make(map[string]interface{})
		doc["customizations"] = customizations
	}

	codespaces, _ := customizations["codespaces"].(map[string]interface{})
	if codespaces == nil {
		codespaces = make(map[string]interface{})
		customizations["codespaces"] = codespaces
	}

	repositories, _ := codespaces["repositories"].(map[string]interface{})
	if repositories == nil {
		repositories = make(map[string]interface{})
		codespaces["repositories"] = repositories
	}

	for k, v := range reposBlock {
		repositories[k] = v
	}
}

// validateDevcontainerRelPath checks that a path relative to .devcontainer/ is safe.
func validateDevcontainerRelPath(p string) error {
	if filepath.IsAbs(p) {
		return fmt.Errorf("devcontainer path must be relative, not absolute: %s", p)
	}
	clean := filepath.Clean(p)
	if clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return fmt.Errorf("devcontainer path cannot traverse outside .devcontainer/: %s", p)
	}
	if strings.HasPrefix(p, "-") {
		return fmt.Errorf("devcontainer path cannot start with a hyphen: %s", p)
	}
	return nil
}

// updateDevcontainerFile reads (or creates) a devcontainer.json file at path,
// merges the repositories permissions block, and writes it back.
// When dryRun is true the result is printed to stdout instead.
func updateDevcontainerFile(path string, repos []string, permissions string, dryRun bool) error {
	reposBlock := buildRepoPermissionsBlock(repos, permissions)

	var doc map[string]interface{}
	data, err := os.ReadFile(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("reading %s: %w", path, err)
		}
		// File does not exist – start with an empty JSON object.
		doc = make(map[string]interface{})
	} else {
		clean := stripJSONC(data)
		if err := json.Unmarshal(clean, &doc); err != nil {
			return fmt.Errorf("parsing %s: %w", path, err)
		}
	}

	mergeRepoPermissions(doc, reposBlock)

	out, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return fmt.Errorf("marshalling devcontainer JSON: %w", err)
	}
	out = append(out, '\n')

	if dryRun {
		fmt.Printf("=== DRY-RUN OUTPUT for %s ===\n", path)
		_, err = os.Stdout.Write(out)
		return err
	}

	// Create parent directory if it doesn't exist.
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return fmt.Errorf("creating directory for %s: %w", path, err)
	}

	// Write via a temp file then rename for atomicity.
	tmpFile, err := os.CreateTemp(filepath.Dir(path), ".devcontainer-*.json.tmp")
	if err != nil {
		return fmt.Errorf("creating temp file near %s: %w", path, err)
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath) // clean up if rename fails

	if _, err := tmpFile.Write(out); err != nil {
		tmpFile.Close()
		return fmt.Errorf("writing temp file: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("closing temp file: %w", err)
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf("writing %s: %w", path, err)
	}

	fmt.Printf("Updated '%s'.\n", path)
	return nil
}
