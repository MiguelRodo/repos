package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

type counters struct {
	total        int
	clonedFull   int
	clonedBranch int
	worktrees    int
	skipped      int
	errors       int
}

type state struct {
	startDir          string
	parentDir         string
	reposFile         string
	debug             bool
	globalWorktree    bool
	globalFetchMode   string
	currentRepoHTTPS  string
	fallbackRepoHTTPS string
	fallbackRepoLocal string
	cloneDest         string
	seenRemoteLocal   map[string]string
	plan              map[string]planInfo
	counts            counters
}

type planInfo struct {
	hasFull  bool
	baseName string
	refCount int
}

type instruction struct {
	repoSpec    string
	targetDir   string
	allBranches bool
	isWorktree  bool
	isAtBranch  bool
	fetchMode   string
}

var sanitizeURLRegex = regexp.MustCompile(`https?://[^/@\s]+@`)
var ownerRepoRegex = regexp.MustCompile(`^[^/]+/[^/]+$`)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	sub := os.Args[1]
	switch sub {
	case "clone":
		if err := runClone(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "-h", "--help", "help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown command '%s'\n\n", sub)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Print(`Usage: repos <command> [options]

Commands:
  clone       Clone repositories listed in repos.list into the parent directory

Run 'repos clone --help' for more information.
`)
}

func cloneUsage() {
	fmt.Print(`Usage: repos clone [--file <repo-list>] [--debug] [--worktree]

Fetch modes:
  --fetch-all-deferred   (default) clone with --single-branch then restore wildcard refspec
  --fetch-single         keep strict single-branch refspec
  --fetch-all            full clone of all branches
`)
}

func runClone(args []string) error {
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}

	defaultFile := "repos.list"
	if _, err := os.Stat(defaultFile); err != nil {
		if _, err2 := os.Stat("repos-to-clone.list"); err2 == nil {
			defaultFile = "repos-to-clone.list"
		}
	}

	fs := flag.NewFlagSet("clone", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	reposFile := fs.String("file", defaultFile, "repos list file")
	fs.StringVar(reposFile, "f", defaultFile, "repos list file")
	debug := fs.Bool("debug", false, "enable debug")
	fs.BoolVar(debug, "d", false, "enable debug")
	globalWorktree := fs.Bool("worktree", false, "create @branch as worktrees by default")
	fetchDeferred := fs.Bool("fetch-all-deferred", false, "deferred fetch mode")
	fetchSingle := fs.Bool("fetch-single", false, "single fetch mode")
	fetchAll := fs.Bool("fetch-all", false, "all fetch mode")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		cloneUsage()
		return nil
	}

	globalFetchMode := "deferred"
	if *fetchSingle {
		globalFetchMode = "single"
	}
	if *fetchAll {
		globalFetchMode = "all"
	}
	if *fetchDeferred {
		globalFetchMode = "deferred"
	}

	st := &state{
		startDir:        cwd,
		parentDir:       filepath.Dir(cwd),
		reposFile:       *reposFile,
		debug:           *debug,
		globalWorktree:  *globalWorktree,
		globalFetchMode: globalFetchMode,
		seenRemoteLocal: map[string]string{},
		plan:            map[string]planInfo{},
	}

	if _, err := os.Stat(st.reposFile); err != nil {
		return fmt.Errorf("file '%s' not found", st.reposFile)
	}

	if err := st.applyGlobalFlagsFromFile(); err != nil {
		return err
	}
	if err := checkPrerequisites(); err != nil {
		return err
	}
	if err := st.initFallback(); err != nil {
		return err
	}
	if err := st.planForward(); err != nil {
		return err
	}
	if err := st.processFile(); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println("Summary:")
	fmt.Printf("  Instructions processed: %d\n", st.counts.total)
	fmt.Printf("  Skipped (already present): %d\n", st.counts.skipped)
	fmt.Printf("  Cloned (full): %d\n", st.counts.clonedFull)
	fmt.Printf("  Cloned (single-branch): %d\n", st.counts.clonedBranch)
	fmt.Printf("  Worktrees added: %d\n", st.counts.worktrees)
	fmt.Printf("  Errors: %d\n", st.counts.errors)

	if st.counts.errors > 0 {
		return errors.New("clone finished with errors")
	}
	return nil
}

func (s *state) dbg(format string, args ...any) {
	if s.debug {
		fmt.Fprintf(os.Stderr, "[DEBUG clone-go] "+format+"\n", args...)
	}
}

func checkPrerequisites() error {
	for _, tool := range []string{"git"} {
		if _, err := exec.LookPath(tool); err != nil {
			return fmt.Errorf("error: '%s' is required but not found in PATH", tool)
		}
	}
	return nil
}

func runGit(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	out, err := cmd.CombinedOutput()
	trimmed := strings.TrimSpace(string(out))
	if err != nil {
		return trimmed, fmt.Errorf("git %s failed: %s", strings.Join(args, " "), sanitizeURL(trimmed))
	}
	return trimmed, nil
}

func sanitizeURL(in string) string {
	return sanitizeURLRegex.ReplaceAllString(in, "https://")
}

func (s *state) initFallback() error {
	remote, err := getCurrentRepoRemoteHTTPS(s.startDir)
	if err != nil {
		return err
	}
	s.currentRepoHTTPS = remote
	s.fallbackRepoHTTPS = remote
	s.fallbackRepoLocal = s.startDir
	s.seenRemoteLocal[remote] = s.startDir
	return nil
}

func getCurrentRepoRemoteHTTPS(dir string) (string, error) {
	if _, err := runGit(dir, "rev-parse", "--is-inside-work-tree"); err != nil {
		return "", errors.New("error: not inside a Git working tree; cannot derive fallback repo")
	}
	var remoteURL string
	if out, err := runGit(dir, "remote", "get-url", "--push", "--", "origin"); err == nil {
		remoteURL = out
	} else if out, err := runGit(dir, "remote", "get-url", "--", "origin"); err == nil {
		remoteURL = out
	} else {
		remotes, err := runGit(dir, "remote")
		if err != nil || strings.TrimSpace(remotes) == "" {
			return "", errors.New("error: no Git remotes found in the current repository")
		}
		first := strings.Fields(remotes)[0]
		if out, err := runGit(dir, "remote", "get-url", "--push", "--", first); err == nil {
			remoteURL = out
		} else if out, err := runGit(dir, "remote", "get-url", "--", first); err == nil {
			remoteURL = out
		}
	}
	if remoteURL == "" {
		return "", errors.New("error: no Git remotes found in the current repository")
	}
	n := normaliseRemoteToHTTPS(remoteURL)
	if strings.Contains(n, "..") {
		return "", fmt.Errorf("error: current repository remote contains path traversal: %s", n)
	}
	return n, nil
}

func normaliseRemoteToHTTPS(url string) string {
	u := strings.TrimSpace(url)
	u = strings.TrimSuffix(u, ".git")
	if strings.HasPrefix(u, "file://") {
		u = strings.TrimPrefix(u, "file://")
	}
	u = strings.ReplaceAll(u, "\\", "/")
	if strings.HasPrefix(u, "http://") || strings.HasPrefix(u, "https://") {
		if i := strings.Index(u, "://"); i >= 0 {
			prefix := u[:i+3]
			rest := u[i+3:]
			if at := strings.Index(rest, "@"); at >= 0 {
				rest = rest[at+1:]
			}
			u = prefix + rest
		}
		return strings.TrimSuffix(u, "/")
	}
	if strings.HasPrefix(u, "ssh://git@") {
		t := strings.TrimPrefix(u, "ssh://git@")
		parts := strings.SplitN(t, "/", 2)
		if len(parts) == 2 {
			return "https://" + parts[0] + "/" + strings.TrimSuffix(parts[1], ".git")
		}
	}
	if strings.HasPrefix(u, "git@") && strings.Contains(u, ":") {
		t := strings.TrimPrefix(u, "git@")
		parts := strings.SplitN(t, ":", 2)
		if len(parts) == 2 {
			return "https://" + parts[0] + "/" + strings.TrimSuffix(parts[1], ".git")
		}
	}
	return strings.TrimSuffix(u, "/")
}

func specToHTTPS(spec string) string {
	s := strings.TrimSpace(spec)
	s = strings.TrimSuffix(s, ".git")
	if strings.HasPrefix(s, "file://") || strings.HasPrefix(s, "/") || isWindowsAbsPath(s) {
		return normaliseRemoteToHTTPS(s)
	}
	if strings.HasPrefix(s, "https://") || strings.HasPrefix(s, "http://") {
		return normaliseRemoteToHTTPS(s)
	}
	if ownerRepoRegex.MatchString(s) {
		return normaliseRemoteToHTTPS("https://github.com/" + s)
	}
	return normaliseRemoteToHTTPS(s)
}

func splitRepoSpec(spec string) (string, string) {
	s := strings.TrimSpace(spec)
	if strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://") {
		i := strings.Index(s, "://")
		slash := strings.Index(s[i+3:], "/")
		start := i + 3
		if slash >= 0 {
			start = i + 3 + slash + 1
		}
		at := strings.LastIndex(s[start:], "@")
		if at >= 0 {
			idx := start + at
			return s[:idx], s[idx+1:]
		}
		return s, ""
	}
	idx := strings.LastIndex(s, "@")
	if idx < 0 {
		return s, ""
	}
	return s[:idx], s[idx+1:]
}

// sanitizeBranchName converts a branch name into a filesystem-safe suffix
// by replacing "/" with "-" (for directory names only, not git refs).
func sanitizeBranchName(branch string) string {
	return strings.ReplaceAll(branch, "/", "-")
}

func isWindowsAbsPath(s string) bool {
	return len(s) >= 3 && ((s[1] == ':' && (s[2] == '/' || s[2] == '\\')) || strings.HasPrefix(s, `\\`))
}

func trimLine(line string) string {
	t := strings.TrimSpace(strings.TrimSuffix(line, "\r"))
	if t == "" || strings.HasPrefix(t, "#") {
		return ""
	}
	if i := strings.Index(t, " #"); i >= 0 {
		t = strings.TrimSpace(t[:i])
	}
	return strings.TrimSpace(t)
}

func isGlobalFlagLine(line string) bool {
	for _, p := range []string{"--codespaces", "--public", "--private", "--worktree", "--fetch-all-deferred", "--fetch-single", "--fetch-all"} {
		if line == p || strings.HasPrefix(line, p+" ") {
			return true
		}
	}
	return false
}

func (s *state) applyGlobalFlagsFromFile() error {
	f, err := os.Open(s.reposFile)
	if err != nil {
		return err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := trimLine(sc.Text())
		if line == "" {
			continue
		}
		switch {
		case line == "--worktree" || strings.HasPrefix(line, "--worktree "):
			s.globalWorktree = true
		case line == "--fetch-all-deferred" || strings.HasPrefix(line, "--fetch-all-deferred "):
			s.globalFetchMode = "deferred"
		case line == "--fetch-single" || strings.HasPrefix(line, "--fetch-single "):
			s.globalFetchMode = "single"
		case line == "--fetch-all" || strings.HasPrefix(line, "--fetch-all "):
			s.globalFetchMode = "all"
		}
	}
	return sc.Err()
}

func validateBranch(branch string) error {
	if branch == "" || strings.HasPrefix(branch, "-") {
		return fmt.Errorf("error: '%s' is not a valid Git branch name", branch)
	}
	_, err := runGit("", "check-ref-format", "--allow-onelevel", branch)
	if err != nil {
		return fmt.Errorf("error: '%s' is not a valid Git branch name", branch)
	}
	return nil
}

func validateTargetDir(target string) error {
	if target == "" {
		return nil
	}
	if strings.HasPrefix(target, "/") || strings.Contains(target, "..") || strings.HasPrefix(target, "-") {
		return fmt.Errorf("error: target directory cannot be absolute, contain '..', or start with a hyphen: %s", target)
	}
	return nil
}

func (s *state) parseEffectiveLine(trimmed string, fallbackHTTPS string) (instruction, error) {
	ins := instruction{fetchMode: s.globalFetchMode}
	parts := strings.Fields(trimmed)
	if len(parts) == 0 {
		return ins, nil
	}
	first := parts[0]
	rest := parts[1:]

	if strings.HasPrefix(first, "@") {
		branch := strings.TrimPrefix(first, "@")
		if err := validateBranch(branch); err != nil {
			return ins, err
		}
		useWorktree := false
		for _, tok := range rest {
			switch tok {
			case "-w", "--worktree":
				useWorktree = true
			case "-a", "--all-branches":
				ins.allBranches = true
			case "--fetch-all-deferred":
				ins.fetchMode = "deferred"
			case "--fetch-single":
				ins.fetchMode = "single"
			case "--fetch-all":
				ins.fetchMode = "all"
			case "--public", "--private", "--codespaces":
			default:
				if strings.HasPrefix(tok, "-") {
					return ins, fmt.Errorf("error: unknown option '%s' on line: %s", tok, trimmed)
				}
				if ins.targetDir != "" {
					return ins, fmt.Errorf("error: multiple target directories on one line: %s", trimmed)
				}
				ins.targetDir = tok
			}
		}
		if fallbackHTTPS == "" {
			return ins, fmt.Errorf("error: no fallback repo available for '%s'", trimmed)
		}
		if !useWorktree && s.globalWorktree {
			useWorktree = true
		}
		if err := validateTargetDir(ins.targetDir); err != nil {
			return ins, err
		}
		ins.isWorktree = useWorktree
		ins.isAtBranch = true
		ins.repoSpec = fallbackHTTPS + "@" + branch
		if ins.fetchMode == "all" {
			ins.allBranches = true
		}
		return ins, nil
	}

	repoURL, _ := splitRepoSpec(first)
	if strings.HasPrefix(repoURL, "-") || strings.Contains(repoURL, "..") {
		return ins, fmt.Errorf("error: repository spec cannot start with a hyphen or contain '..': %s", first)
	}
	ins.repoSpec = first
	for _, tok := range rest {
		switch tok {
		case "-a", "--all-branches":
			ins.allBranches = true
		case "--fetch-all-deferred":
			ins.fetchMode = "deferred"
		case "--fetch-single":
			ins.fetchMode = "single"
		case "--fetch-all":
			ins.fetchMode = "all"
			ins.allBranches = true
		case "-w", "--worktree":
			fmt.Fprintf(os.Stderr, "Warning: '--worktree' ignored on clone line: %s\n", trimmed)
		case "--public", "--private", "--codespaces":
		default:
			if strings.HasPrefix(tok, "-") {
				return ins, fmt.Errorf("error: unknown option '%s' on line: %s", tok, trimmed)
			}
			if ins.targetDir != "" {
				return ins, fmt.Errorf("error: multiple target directories on one line: %s", trimmed)
			}
			ins.targetDir = tok
		}
	}
	if ins.fetchMode == "all" {
		ins.allBranches = true
	}
	if err := validateTargetDir(ins.targetDir); err != nil {
		return ins, err
	}
	return ins, nil
}

func (s *state) planForward() error {
	f, err := os.Open(s.reposFile)
	if err != nil {
		return err
	}
	defer f.Close()

	fallback := s.currentRepoHTTPS
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		trimmed := trimLine(sc.Text())
		if trimmed == "" || isGlobalFlagLine(trimmed) {
			continue
		}
		parts := strings.Fields(trimmed)
		if len(parts) == 0 {
			continue
		}
		first := parts[0]
		rest := parts[1:]
		if strings.HasPrefix(first, "@") {
			useWorktree := s.globalWorktree
			for _, tok := range rest {
				if tok == "-w" || tok == "--worktree" {
					useWorktree = true
				}
			}
			if useWorktree {
				pi := s.plan[fallback]
				pi.refCount++
				s.plan[fallback] = pi
			}
			continue
		}

		repoNoRef, ref := splitRepoSpec(first)
		if strings.HasPrefix(repoNoRef, "-") || strings.Contains(repoNoRef, "..") {
			continue
		}
		remote := specToHTTPS(repoNoRef)
		target := ""
		for _, tok := range rest {
			if !strings.HasPrefix(tok, "-") {
				target = tok
				break
			}
		}
		pi := s.plan[remote]
		pi.refCount++
		if ref == "" {
			pi.hasFull = true
			if pi.baseName == "" {
				if target != "" {
					pi.baseName = target
				} else {
					pi.baseName = filepath.Base(remote)
				}
			}
		}
		s.plan[remote] = pi
		fallback = remote
	}
	return sc.Err()
}

func parseRepoURL(repoURLNoRef string) (repoURL, repoDir string, err error) {
	s := repoURLNoRef
	sNoGit := strings.TrimSuffix(s, ".git")
	switch {
	case strings.HasPrefix(s, "file://"):
		repoURL = s
		repoDir = filepath.Base(strings.TrimPrefix(sNoGit, "file://"))
	case strings.HasPrefix(s, "/") || isWindowsAbsPath(s):
		repoURL = s
		repoDir = filepath.Base(sNoGit)
	case strings.HasPrefix(s, "https://") || strings.HasPrefix(s, "http://"):
		repoURL = s
		repoDir = filepath.Base(sNoGit)
	case ownerRepoRegex.MatchString(s):
		repoURL = "https://github.com/" + s
		repoDir = strings.SplitN(s, "/", 2)[1]
	case strings.Contains(s, "/"):
		repoURL = s
		repoDir = filepath.Base(sNoGit)
	default:
		return "", "", fmt.Errorf("error: invalid repo spec '%s'", s)
	}
	if repoDir == "" {
		return "", "", fmt.Errorf("error: invalid repo spec '%s'", s)
	}
	return repoURL, repoDir, nil
}

func (s *state) remoteRefCount(remote string) int {
	return s.plan[remote].refCount
}

func (s *state) planHasFull(remote string) bool {
	return s.plan[remote].hasFull
}

func (s *state) planBaseName(remote string) string {
	if pi, ok := s.plan[remote]; ok && pi.baseName != "" {
		return pi.baseName
	}
	return filepath.Base(remote)
}

func dirExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && st.IsDir()
}

func isNonEmptyDir(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	_, err = f.Readdirnames(1)
	return err == nil
}

func (s *state) ensureWildcardFetchRefspec(base string) {
	wild := "+refs/heads/*:refs/remotes/origin/*"
	out, err := runGit(base, "config", "--get-all", "--", "remote.origin.fetch")
	if err == nil {
		for _, l := range strings.Split(out, "\n") {
			if strings.TrimSpace(l) == wild {
				return
			}
		}
	}
	if _, err := runGit(base, "config", "--add", "--", "remote.origin.fetch", wild); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not add wildcard fetch refspec in %s: %v\n", base, err)
	}
}

func (s *state) ensureBaseExists(remote, base, fetchMode string) (int, error) {
	if _, err := runGit(base, "rev-parse", "--is-inside-work-tree"); err == nil {
		return 0, nil
	}
	if dirExists(base) && isNonEmptyDir(base) {
		fmt.Fprintf(os.Stderr, "Error: intended base '%s' exists and is not a Git repo (non-empty). Skipping.\n", base)
		return 2, nil
	}
	if err := os.MkdirAll(base, 0o755); err != nil {
		return 1, err
	}
	cloneArgs := []string{"clone"}
	if fetchMode != "all" {
		cloneArgs = append(cloneArgs, "--single-branch")
	}
	cloneArgs = append(cloneArgs, "--", remote, base)
	if _, err := runGit("", cloneArgs...); err != nil {
		return 1, fmt.Errorf("error: failed to clone '%s' into '%s': %w", remote, base, err)
	}
	if fetchMode == "all" {
		s.counts.clonedFull++
	} else {
		s.counts.clonedBranch++
		if fetchMode == "deferred" {
			s.ensureWildcardFetchRefspec(base)
		}
	}
	s.seenRemoteLocal[remote] = base
	return 0, nil
}

func localBranchExists(base, branch string) bool {
	_, err := runGit(base, "rev-parse", "--verify", "--quiet", "refs/heads/"+branch)
	return err == nil
}

func remoteBranchExists(base, branch string) bool {
	_, err := runGit(base, "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+branch)
	return err == nil
}

func defaultRemoteBranch(base string) string {
	if out, err := runGit(base, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"); err == nil {
		return strings.TrimPrefix(strings.TrimSpace(out), "origin/")
	}
	if remoteBranchExists(base, "master") {
		return "master"
	}
	return "main"
}

func findWorktreeForBranch(base, branch string) string {
	out, err := runGit(base, "worktree", "list", "--porcelain")
	if err != nil {
		return ""
	}
	want := "refs/heads/" + branch
	var wt string
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "worktree ") {
			wt = strings.TrimPrefix(line, "worktree ")
		}
		if strings.HasPrefix(line, "branch ") && strings.TrimPrefix(line, "branch ") == want {
			return wt
		}
	}
	return ""
}

func safeGetOriginURL(dir string) string {
	if out, err := runGit(dir, "remote", "get-url", "origin"); err == nil {
		return out
	}
	if out, err := runGit(dir, "config", "--get", "remote.origin.url"); err == nil {
		return out
	}
	return ""
}

func (s *state) cloneOneRepo(ins instruction) (int, error) {
	repoURLNoRef, ref := splitRepoSpec(ins.repoSpec)
	if ref != "" {
		if err := validateBranch(ref); err != nil {
			return 1, err
		}
	}
	repoURL, repoDir, err := parseRepoURL(repoURLNoRef)
	if err != nil {
		return 1, err
	}
	remoteHTTPS := specToHTTPS(repoURLNoRef)

	dest := ""
	switch {
	case ins.targetDir != "":
		dest = filepath.Join(s.parentDir, ins.targetDir)
	case ref != "":
		if s.remoteRefCount(remoteHTTPS) > 1 {
			dest = filepath.Join(s.parentDir, repoDir+"-"+sanitizeBranchName(ref))
		} else {
			dest = filepath.Join(s.parentDir, repoDir)
		}
	default:
		dest = filepath.Join(s.parentDir, repoDir)
	}

	if dirExists(filepath.Join(dest, ".git")) {
		existingHTTPS := normaliseRemoteToHTTPS(safeGetOriginURL(dest))
		if existingHTTPS != "" && existingHTTPS == remoteHTTPS {
			fmt.Printf("Already exists: %s (matches %s)\n", dest, remoteHTTPS)
			s.cloneDest = dest
			s.seenRemoteLocal[remoteHTTPS] = dest
			s.counts.skipped++
			return 2, nil
		}
		fmt.Printf("Skip: %s is a Git repo for '%s' (wanted '%s'); leaving as-is.\n", dest, existingHTTPS, remoteHTTPS)
		s.counts.skipped++
		return 2, nil
	}

	if dirExists(dest) && isNonEmptyDir(dest) {
		fmt.Printf("Skip: %s exists and is not empty (non-Git); leaving as-is.\n", dest)
		s.counts.skipped++
		return 2, nil
	}

	cloneArgs := []string{"clone"}
	if !ins.allBranches {
		cloneArgs = append(cloneArgs, "--single-branch")
	}

	if ref != "" {
		if _, err := runGit("", "ls-remote", "--exit-code", "--heads", "--", repoURL, ref); err == nil {
			cloneArgs2 := append(append([]string{}, cloneArgs...), "--branch", ref, "--", repoURL, dest)
			fmt.Printf("Cloning %s → %s (branch %s)\n", remoteHTTPS, dest, ref)
			if _, err := runGit("", cloneArgs2...); err != nil {
				return 1, err
			}
		} else {
			fmt.Printf("Remote branch '%s' not found on %s; creating it.\n", ref, remoteHTTPS)
			fmt.Printf("Cloning default branch of %s → %s\n", remoteHTTPS, dest)
			cloneArgs2 := append(cloneArgs, "--", repoURL, dest)
			if _, err := runGit("", cloneArgs2...); err != nil {
				return 1, err
			}
			if _, err := runGit(dest, "switch", "-c", ref, "--"); err != nil {
				return 1, err
			}
			if _, err := runGit(dest, "push", "-u", "origin", "--", "HEAD:"+ref); err != nil {
				return 1, err
			}
		}
		s.counts.clonedBranch++
	} else {
		cloneArgs = append(cloneArgs, "--", repoURL, dest)
		fmt.Printf("Cloning %s → %s\n", remoteHTTPS, dest)
		if _, err := runGit("", cloneArgs...); err != nil {
			return 1, err
		}
		s.counts.clonedFull++
	}

	if !ins.allBranches && ins.fetchMode == "deferred" {
		s.ensureWildcardFetchRefspec(dest)
	}
	s.cloneDest = dest
	s.seenRemoteLocal[remoteHTTPS] = dest
	return 0, nil
}

func (s *state) createWorktreeForBranch(base, branch, targetDir, fetchMode string) (int, error) {
	if branch == "" {
		return 1, errors.New("error: @branch requires a branch name")
	}
	if base == "" {
		return 1, errors.New("error: no fallback base path available for worktree")
	}
	// Best-effort cleanup of stale worktree references.
	if _, err := runGit(base, "worktree", "prune"); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: ignoring worktree prune failure for %s: %v\n", base, err)
	}
	if existing := findWorktreeForBranch(base, branch); existing != "" {
		fmt.Printf("Skip: branch '%s' already checked out at %s\n", branch, existing)
		s.counts.skipped++
		return 2, nil
	}
	repoBase := filepath.Base(base)
	dest := ""
	if targetDir != "" {
		dest = filepath.Join(s.parentDir, targetDir)
	} else {
		dest = filepath.Join(s.parentDir, repoBase+"-"+sanitizeBranchName(branch))
	}
	if dirExists(filepath.Join(dest, ".git")) {
		curb, err := runGit(dest, "rev-parse", "--abbrev-ref", "HEAD")
		if err == nil && strings.TrimSpace(curb) == branch {
			fmt.Printf("Already exists: %s (branch %s)\n", dest, branch)
		} else if err == nil {
			fmt.Printf("Skip: %s already exists (branch '%s'); leaving as-is.\n", dest, strings.TrimSpace(curb))
		} else {
			fmt.Printf("Skip: %s already exists and is a Git dir; leaving as-is.\n", dest)
		}
		s.counts.skipped++
		return 2, nil
	}
	if dirExists(dest) && isNonEmptyDir(dest) {
		fmt.Fprintf(os.Stderr, "Skip: destination '%s' exists and is not empty; not touching it.\n", dest)
		s.counts.skipped++
		return 2, nil
	}
	if _, err := runGit(base, "fetch", "--prune", "origin"); err != nil {
		return 1, err
	}

	if localBranchExists(base, branch) {
		fmt.Printf("Adding worktree %s (existing local branch '%s')\n", dest, branch)
		if _, err := runGit(base, "worktree", "add", "--", dest, branch); err != nil {
			return 1, err
		}
		s.counts.worktrees++
		if remoteBranchExists(base, branch) {
			if fetchMode == "deferred" {
				s.ensureWildcardFetchRefspec(base)
			}
			if _, err := runGit(dest, "branch", "--set-upstream-to", "origin/"+branch, "--"); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to set upstream for %s: %v\n", branch, err)
			}
		} else {
			if _, err := runGit(dest, "push", "-u", "origin", "--", "HEAD:"+branch); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to push branch %s: %v\n", branch, err)
			}
		}
		return 0, nil
	}

	if _, err := runGit(base, "ls-remote", "--exit-code", "--heads", "origin", branch); err == nil {
		fmt.Printf("Branch exists: %s (on remote)\n", branch)
		fmt.Printf("Adding worktree %s (tracking origin/%s)\n", dest, branch)
		// Best-effort fetch of remote-tracking branch in single-branch clones.
		if _, err := runGit(base, "fetch", "origin", "refs/heads/"+branch+":refs/remotes/origin/"+branch); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: ignoring remote-tracking fetch failure for %s in %s: %v\n", branch, base, err)
		}
		if remoteBranchExists(base, branch) {
			if _, err := runGit(base, "worktree", "add", "-b", branch, "--", dest, "origin/"+branch); err != nil {
				return 1, err
			}
			s.counts.worktrees++
			if fetchMode == "deferred" {
				s.ensureWildcardFetchRefspec(base)
			}
			if _, err := runGit(dest, "branch", "--set-upstream-to", "origin/"+branch, "--"); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to set upstream for %s: %v\n", branch, err)
			}
			return 0, nil
		}
		defb := defaultRemoteBranch(base)
		baseRef := "origin/" + defb
		if !remoteBranchExists(base, defb) {
			baseRef = "HEAD"
		}
		fmt.Printf("Could not resolve origin/%s locally; creating from %s instead\n", branch, baseRef)
		if _, err := runGit(base, "worktree", "add", "-b", branch, "--", dest, baseRef); err != nil {
			return 1, err
		}
		s.counts.worktrees++
		if _, err := runGit(dest, "push", "-u", "origin", "--", "HEAD:"+branch); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to push branch %s: %v\n", branch, err)
		}
		return 0, nil
	}

	fmt.Printf("Branch not found: %s (on remote, creating new)\n", branch)
	defb := defaultRemoteBranch(base)
	baseRef := "origin/" + defb
	if !remoteBranchExists(base, defb) {
		baseRef = "HEAD"
	}
	fmt.Printf("Adding worktree %s (new branch '%s' from %s)\n", dest, branch, baseRef)
	if _, err := runGit(base, "worktree", "add", "-b", branch, "--", dest, baseRef); err != nil {
		return 1, err
	}
	if _, err := runGit(dest, "push", "-u", "origin", "--", "HEAD:"+branch); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to push branch %s: %v\n", branch, err)
	}
	s.counts.worktrees++
	return 0, nil
}

func (s *state) processFile() error {
	f, err := os.Open(s.reposFile)
	if err != nil {
		return err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		trimmed := trimLine(sc.Text())
		if trimmed == "" || isGlobalFlagLine(trimmed) {
			continue
		}
		fmt.Fprintf(os.Stderr, "Processing: %s\n", sanitizeURL(trimmed))
		ins, err := s.parseEffectiveLine(trimmed, s.fallbackRepoHTTPS)
		lineRC := 0
		if err != nil {
			lineRC = 1
		} else if ins.repoSpec != "" {
			if ins.isWorktree {
				_, branch := splitRepoSpec(ins.repoSpec)
				base := ""
				if s.fallbackRepoHTTPS == s.currentRepoHTTPS {
					base = s.startDir
				} else if b, ok := s.seenRemoteLocal[s.fallbackRepoHTTPS]; ok && b != "" {
					base = b
				} else {
					base = filepath.Join(s.parentDir, s.planBaseName(s.fallbackRepoHTTPS))
					rc, e := s.ensureBaseExists(s.fallbackRepoHTTPS, base, ins.fetchMode)
					if e != nil {
						err = e
						lineRC = 1
					} else if rc != 0 {
						lineRC = rc
					}
				}
				if lineRC == 0 {
					rc, e := s.createWorktreeForBranch(base, branch, ins.targetDir, ins.fetchMode)
					if e != nil {
						err = e
						lineRC = 1
					} else {
						lineRC = rc
					}
					s.fallbackRepoLocal = base
					s.seenRemoteLocal[s.fallbackRepoHTTPS] = base
				}
			} else {
				repoNoRef, ref := splitRepoSpec(ins.repoSpec)
				isBranchClone := ref != ""
				thisRemoteHTTPS := specToHTTPS(repoNoRef)
				_, seenBefore := s.seenRemoteLocal[thisRemoteHTTPS]

				if ins.isAtBranch && isBranchClone && ins.targetDir == "" {
					fallbackLocalName := ""
					if p := s.seenRemoteLocal[s.fallbackRepoHTTPS]; p != "" {
						fallbackLocalName = filepath.Base(p)
					} else if s.fallbackRepoHTTPS == s.currentRepoHTTPS {
						fallbackLocalName = filepath.Base(s.startDir)
					} else {
						fallbackLocalName = s.planBaseName(s.fallbackRepoHTTPS)
					}
					ins.targetDir = fallbackLocalName + "-" + sanitizeBranchName(ref)
				}

				rc, e := s.cloneOneRepo(ins)
				if e != nil {
					err = e
					lineRC = 1
				} else {
					lineRC = rc
				}

				s.fallbackRepoHTTPS = thisRemoteHTTPS
				if !isBranchClone {
					if s.cloneDest != "" {
						s.fallbackRepoLocal = s.cloneDest
					}
					s.seenRemoteLocal[thisRemoteHTTPS] = s.fallbackRepoLocal
				} else {
					if !seenBefore && s.planHasFull(thisRemoteHTTPS) {
						base := filepath.Join(s.parentDir, s.planBaseName(thisRemoteHTTPS))
						rc2, e2 := s.ensureBaseExists(thisRemoteHTTPS, base, ins.fetchMode)
						if e2 != nil {
							err = e2
							lineRC = 1
						} else if rc2 != 0 && lineRC == 0 {
							lineRC = rc2
						}
						s.fallbackRepoLocal = base
						s.seenRemoteLocal[thisRemoteHTTPS] = base
					} else if s.cloneDest != "" {
						s.fallbackRepoLocal = s.cloneDest
						s.seenRemoteLocal[thisRemoteHTTPS] = s.cloneDest
					}
				}
			}
		}

		s.counts.total++
		switch lineRC {
		case 0:
		case 2:
			fmt.Fprintf(os.Stderr, "SKIP: %s\n", sanitizeURL(trimmed))
		default:
			s.counts.errors++
			if err != nil {
				fmt.Fprintf(os.Stderr, "ERROR: line failed: %s\n", sanitizeURL(err.Error()))
			} else {
				fmt.Fprintf(os.Stderr, "ERROR: line failed (rc=%d): %s\n", lineRC, sanitizeURL(trimmed))
			}
		}
	}
	return sc.Err()
}
