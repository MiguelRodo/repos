// Package parser provides a unified engine for reading and resolving
// repos.list files.  It exposes a single public entry-point, ParseList,
// that reads the file top-to-bottom, applies global flags, initialises the
// fallback-remote state machine, and returns a fully-resolved slice of
// Instructions ready for execution by any subcommand.
package parser

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
)

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

// GlobalOptions carries the settings that control how a repos list is parsed.
// CLI-level flags are set before calling ParseList; file-level global flags
// (e.g. --worktree in repos.list) may further update the fields if the
// corresponding CLI flag was not already set.
type GlobalOptions struct {
	Debug                 bool
	GlobalWorktree        bool
	GlobalWorktreeForced  bool
	GlobalFetchMode       string // "deferred" | "single" | "all"
	GlobalFetchModeForced bool
	CLIWorktreeSet        bool
	CLIFetchModeSet       bool
	CLIForce              bool
	// StartDir is the working directory that contains repos.list.
	// It is used to derive the current repo's remote URL (fallback).
	StartDir string
	// ParentDir is the directory into which repositories are cloned
	// (usually filepath.Dir(StartDir)).
	ParentDir string
}

// Instruction is a fully-resolved clone or worktree action derived from one
// non-blank, non-comment, non-global-flag line in the repos list.
type Instruction struct {
	// RemoteURL is the normalised remote identifier derived from the repo spec
	// (never contains @branch).  SSH, HTTPS, and local filesystem remotes are
	// all normalised to a canonical form so they can be compared across
	// instructions — e.g. `git@github.com:org/repo` and
	// `https://github.com/org/repo` both normalise to the same HTTPS URL.
	// Local file:// and absolute-path remotes normalise to the stripped path.
	// Use CloneURL when invoking git directly to preserve the original scheme.
	RemoteURL string
	// CloneURL is the URL that should be passed to `git clone` / `git ls-remote`.
	// It is derived from the raw spec via ParseRepoURL and preserves SSH,
	// HTTPS, file://, and absolute-path schemes exactly as the user wrote them
	// (short owner/repo specs expand to https://github.com/<owner>/<repo>).
	CloneURL string
	// Branch is the branch name, or "" for the default branch.
	Branch string
	// TargetDir is the absolute path of the intended clone/worktree
	// destination.  It is derived from explicit per-line target options and
	// the forward-planning pass; the caller may still discover the directory
	// already exists.
	TargetDir string
	// BaseDir is set only for worktree instructions and contains the absolute
	// path of the base repository into which the worktree is added.
	BaseDir string
	// IsWorktree is true when the instruction should be executed as
	// `git worktree add` rather than `git clone`.
	IsWorktree bool
	// IsAtBranch is true when the line started with @<branch>.
	IsAtBranch bool
	// AllBranches is true when all remote branches should be fetched.
	AllBranches bool
	// FetchMode is "deferred", "single", or "all".
	FetchMode string
	// Warnings contains non-fatal diagnostic messages produced during parsing
	// (e.g. ignored flags).  Callers should print or log these as appropriate.
	Warnings []string
}

// ---------------------------------------------------------------------------
// Private types
// ---------------------------------------------------------------------------

type planInfo struct {
	hasFull  bool
	baseName string
	refCount int
}

// rawInstruction is the internal result of parseEffectiveLine before TargetDir
// is resolved to an absolute path.
type rawInstruction struct {
	repoSpec            string // may be "<url>@<branch>" for @branch lines
	targetDir           string // relative, possibly empty
	allBranches         bool
	isWorktree          bool
	isAtBranch          bool
	fetchMode           string
	worktreeOnCloneLine bool // --worktree appeared on a regular clone line
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// ParseList reads filePath top-to-bottom and returns a slice of fully-resolved
// Instructions.  The opts argument carries CLI-level settings; any global
// flags found in the file are applied on top (unless the corresponding CLI
// flag was already set).
//
// The function calls GetRepoRemoteHTTPS(opts.StartDir) to initialise the
// @branch fallback; callers must ensure opts.StartDir is inside a Git working
// tree.
func ParseList(filePath string, opts GlobalOptions) ([]Instruction, error) {
	if opts.GlobalFetchMode == "" {
		opts.GlobalFetchMode = "deferred"
	}

	// Step 1: overlay global flags from the file.
	if err := applyGlobalFlagsFromFile(filePath, &opts); err != nil {
		return nil, err
	}

	// Step 2: initialise fallback from current repo.
	currentHTTPS, err := GetRepoRemoteHTTPS(opts.StartDir)
	if err != nil {
		return nil, err
	}

	// Step 3: forward-planning pass (builds plan map for disambiguation).
	plan, err := planForward(filePath, opts, currentHTTPS)
	if err != nil {
		return nil, err
	}

	// Step 4: resolve each line into a fully-resolved Instruction.
	return resolveInstructions(filePath, opts, currentHTTPS, plan)
}

// GetRepoRemoteHTTPS returns the HTTPS URL of the "origin" remote for the Git
// repository rooted at (or containing) dir.
func GetRepoRemoteHTTPS(dir string) (string, error) {
	if _, err := gitcmd.RunGit(dir, "rev-parse", "--is-inside-work-tree"); err != nil {
		return "", errors.New("error: not inside a Git working tree; cannot derive fallback repo")
	}
	var remoteURL string
	if out, err := gitcmd.RunGit(dir, "remote", "get-url", "--push", "--", "origin"); err == nil {
		remoteURL = out
	} else if out, err := gitcmd.RunGit(dir, "remote", "get-url", "--", "origin"); err == nil {
		remoteURL = out
	} else {
		remotes, err := gitcmd.RunGit(dir, "remote")
		if err != nil || strings.TrimSpace(remotes) == "" {
			return "", errors.New("error: no Git remotes found in the current repository")
		}
		first := strings.Fields(remotes)[0]
		if out, err := gitcmd.RunGit(dir, "remote", "get-url", "--push", "--", first); err == nil {
			remoteURL = out
		} else if out, err := gitcmd.RunGit(dir, "remote", "get-url", "--", first); err == nil {
			remoteURL = out
		}
	}
	if remoteURL == "" {
		return "", errors.New("error: no Git remotes found in the current repository")
	}
	if strings.Contains(remoteURL, "..") {
		return "", fmt.Errorf("error: current repository remote contains path traversal: %s", gitcmd.SanitizeURL(remoteURL))
	}
	n := NormaliseRemoteToHTTPS(remoteURL)
	if strings.Contains(n, "..") {
		return "", fmt.Errorf("error: current repository remote contains path traversal: %s", n)
	}
	return n, nil
}

// ---------------------------------------------------------------------------
// URL / spec helpers (exported so clone.go can reuse them)
// ---------------------------------------------------------------------------

var ownerRepoRegex = regexp.MustCompile(`^[^/]+/[^/]+$`)

// NormaliseRemoteToHTTPS converts any Git remote URL format to a plain HTTPS
// URL with no trailing ".git", no trailing slash, and no embedded credentials.
func NormaliseRemoteToHTTPS(url string) string {
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

// SpecToHTTPS converts an owner/repo shorthand or any Git URL to a normalised
// HTTPS URL.
func SpecToHTTPS(spec string) string {
	s := strings.TrimSpace(spec)
	s = strings.TrimSuffix(s, ".git")
	if strings.HasPrefix(s, "file://") || strings.HasPrefix(s, "/") || isWindowsAbsPath(s) {
		return NormaliseRemoteToHTTPS(s)
	}
	if strings.HasPrefix(s, "https://") || strings.HasPrefix(s, "http://") {
		return NormaliseRemoteToHTTPS(s)
	}
	if ownerRepoRegex.MatchString(s) {
		return NormaliseRemoteToHTTPS("https://github.com/" + s)
	}
	return NormaliseRemoteToHTTPS(s)
}

// SplitRepoSpec splits a repo spec of the form <url>[@<branch>] into the URL
// part and the branch part (which may be empty).
func SplitRepoSpec(spec string) (string, string) {
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

// ParseRepoURL resolves a remote URL (without a @branch suffix) into the clone
// URL and the local directory name.
func ParseRepoURL(repoURLNoRef string) (repoURL, repoDir string, err error) {
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

// SanitizeBranchName converts a branch name to a filesystem-safe suffix by
// replacing "/" with "-".
func SanitizeBranchName(branch string) string {
	return strings.ReplaceAll(branch, "/", "-")
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

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

func isGlobalFlagToken(tok string) bool {
	switch tok {
	case "--codespaces", "--public", "--private", "--worktree",
		"--fetch-all-deferred", "--fetch-single", "--fetch-all", "--force":
		return true
	default:
		return false
	}
}

func lineIsGlobalFlagsOnly(line string) bool {
	parts := strings.Fields(line)
	if len(parts) == 0 {
		return false
	}
	for _, tok := range parts {
		if !isGlobalFlagToken(tok) {
			return false
		}
	}
	return true
}

func validateBranch(branch string) error {
	if branch == "" || strings.HasPrefix(branch, "-") {
		return fmt.Errorf("error: '%s' is not a valid Git branch name", branch)
	}
	_, err := gitcmd.RunGit("", "check-ref-format", "--allow-onelevel", branch)
	if err != nil {
		return fmt.Errorf("error: '%s' is not a valid Git branch name", branch)
	}
	return nil
}

func validateTargetDir(target string) error {
	if target == "" {
		return nil
	}
	if strings.HasPrefix(target, "/") || strings.HasPrefix(target, `\\`) ||
		isWindowsAbsPath(target) || strings.Contains(target, "..") ||
		strings.HasPrefix(target, "-") {
		return fmt.Errorf(
			"error: target directory cannot be absolute, contain '..', or start with a hyphen: %s",
			target,
		)
	}
	return nil
}

// applyGlobalFlagsFromFile scans the repos list for lines that contain only
// global flag tokens and applies them to opts.  CLI-set flags take precedence.
func applyGlobalFlagsFromFile(filePath string, opts *GlobalOptions) error {
	f, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := trimLine(sc.Text())
		if line == "" || !lineIsGlobalFlagsOnly(line) {
			continue
		}
		parts := strings.Fields(line)
		lineForce := false
		for _, tok := range parts {
			if tok == "--force" {
				lineForce = true
				break
			}
		}
		for _, tok := range parts {
			switch tok {
			case "--worktree":
				if !opts.CLIWorktreeSet {
					opts.GlobalWorktree = true
					if lineForce {
						opts.GlobalWorktreeForced = true
					}
				}
			case "--fetch-all-deferred":
				if !opts.CLIFetchModeSet {
					opts.GlobalFetchMode = "deferred"
					opts.GlobalFetchModeForced = lineForce
				}
			case "--fetch-single":
				if !opts.CLIFetchModeSet {
					opts.GlobalFetchMode = "single"
					opts.GlobalFetchModeForced = lineForce
				}
			case "--fetch-all":
				if !opts.CLIFetchModeSet {
					opts.GlobalFetchMode = "all"
					opts.GlobalFetchModeForced = lineForce
				}
			}
		}
	}
	return sc.Err()
}

// planForward performs a first pass over the repos list to build a map from
// remote HTTPS URL to planInfo.  This is used in the second pass to disambiguate
// target directory names when the same remote appears with multiple refs.
func planForward(filePath string, opts GlobalOptions, currentHTTPS string) (map[string]planInfo, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	plan := map[string]planInfo{}
	fallback := currentHTTPS

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		trimmed := trimLine(sc.Text())
		if trimmed == "" || lineIsGlobalFlagsOnly(trimmed) {
			continue
		}
		ins, err := parseEffectiveLine(trimmed, fallback, opts)
		if err != nil {
			return nil, err
		}
		if ins.repoSpec == "" {
			continue
		}
		if ins.isAtBranch {
			if ins.isWorktree {
				pi := plan[fallback]
				pi.refCount++
				plan[fallback] = pi
			}
			continue
		}

		repoNoRef, ref := SplitRepoSpec(ins.repoSpec)
		if strings.HasPrefix(repoNoRef, "-") || strings.Contains(repoNoRef, "..") {
			continue
		}
		remote := SpecToHTTPS(repoNoRef)
		pi := plan[remote]
		pi.refCount++
		if ref == "" {
			pi.hasFull = true
			if pi.baseName == "" {
				if ins.targetDir != "" {
					pi.baseName = ins.targetDir
				} else {
					pi.baseName = filepath.Base(remote)
				}
			}
		}
		plan[remote] = pi
		fallback = remote
	}
	return plan, sc.Err()
}

// planBaseName returns the planned local directory name for a remote.
func planBaseName(plan map[string]planInfo, remote string) string {
	if pi, ok := plan[remote]; ok && pi.baseName != "" {
		return pi.baseName
	}
	return filepath.Base(remote)
}

// parseEffectiveLine converts a single trimmed, non-empty line into a
// rawInstruction.  fallbackHTTPS is the current fallback remote URL used to
// resolve @branch lines.
func parseEffectiveLine(trimmed, fallbackHTTPS string, opts GlobalOptions) (rawInstruction, error) {
	ins := rawInstruction{fetchMode: opts.GlobalFetchMode}
	ignoreLineFlags := opts.CLIForce
	worktreeLocked := opts.GlobalWorktreeForced
	fetchModeLocked := opts.GlobalFetchModeForced

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
		useWorktree := opts.GlobalWorktree
		for _, tok := range rest {
			switch tok {
			case "-w", "--worktree":
				if !ignoreLineFlags && !worktreeLocked {
					useWorktree = true
				}
			case "-a", "--all-branches":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.allBranches = true
				}
			case "--fetch-all-deferred":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.fetchMode = "deferred"
				}
			case "--fetch-single":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.fetchMode = "single"
				}
			case "--fetch-all":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.fetchMode = "all"
				}
			case "--public", "--private", "--codespaces", "--force":
				// ignore on @branch lines
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

	// Regular clone line.
	repoURL, _ := SplitRepoSpec(first)
	if strings.HasPrefix(repoURL, "-") || strings.Contains(repoURL, "..") {
		return ins, fmt.Errorf(
			"error: repository spec cannot start with a hyphen or contain '..': %s", first)
	}
	ins.repoSpec = first
	for _, tok := range rest {
		switch tok {
		case "-a", "--all-branches":
			if !ignoreLineFlags && !fetchModeLocked {
				ins.allBranches = true
			}
		case "--fetch-all-deferred":
			if !ignoreLineFlags && !fetchModeLocked {
				ins.fetchMode = "deferred"
			}
		case "--fetch-single":
			if !ignoreLineFlags && !fetchModeLocked {
				ins.fetchMode = "single"
			}
		case "--fetch-all":
			if !ignoreLineFlags && !fetchModeLocked {
				ins.fetchMode = "all"
				ins.allBranches = true
			}
		case "-w", "--worktree":
			ins.worktreeOnCloneLine = true
		case "--public", "--private", "--codespaces", "--force":
			// ignore
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

// resolveInstructions performs the second pass over the repos list, converting
// each raw line into a fully-resolved Instruction with absolute TargetDir and
// (for worktrees) BaseDir.
func resolveInstructions(
	filePath string,
	opts GlobalOptions,
	currentHTTPS string,
	plan map[string]planInfo,
) ([]Instruction, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	// Fallback tracking (mirrors processFile in clone.go).
	fallbackHTTPS := currentHTTPS
	fallbackBaseName := filepath.Base(opts.StartDir)

	var instructions []Instruction
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		trimmed := trimLine(sc.Text())
		if trimmed == "" || lineIsGlobalFlagsOnly(trimmed) {
			continue
		}

		raw, err := parseEffectiveLine(trimmed, fallbackHTTPS, opts)
		if err != nil {
			return nil, err
		}
		if raw.repoSpec == "" {
			continue
		}

		ins := Instruction{
			IsWorktree:  raw.isWorktree,
			IsAtBranch:  raw.isAtBranch,
			AllBranches: raw.allBranches,
			FetchMode:   raw.fetchMode,
		}

		// Surface non-fatal warnings from parsing so the caller controls UX.
		if raw.worktreeOnCloneLine {
			ins.Warnings = append(ins.Warnings,
				fmt.Sprintf("Warning: '--worktree' is ignored on clone lines: %s", raw.repoSpec))
		}

		repoNoRef, branch := SplitRepoSpec(raw.repoSpec)

		if raw.isAtBranch {
			// @branch line: RemoteURL = fallback, BaseDir = fallback local path.
			ins.RemoteURL = repoNoRef // already = fallbackHTTPS from parseEffectiveLine
			ins.CloneURL = repoNoRef  // for worktrees the "clone URL" is the base remote
			ins.Branch = branch
			if fallbackHTTPS == currentHTTPS {
				ins.BaseDir = opts.StartDir
			} else {
				ins.BaseDir = filepath.Join(opts.ParentDir, fallbackBaseName)
			}
			if raw.targetDir != "" {
				ins.TargetDir = filepath.Join(opts.ParentDir, raw.targetDir)
			} else {
				ins.TargetDir = filepath.Join(opts.ParentDir, fallbackBaseName+"-"+SanitizeBranchName(branch))
			}
			// @branch lines do not update the fallback.
		} else {
			// Regular clone line.
			remoteHTTPS := SpecToHTTPS(repoNoRef)
			cloneURL, repoDir, err := ParseRepoURL(repoNoRef)
			if err != nil {
				return nil, err
			}

			ins.RemoteURL = remoteHTTPS
			// CloneURL preserves the original scheme (SSH, HTTPS, local path)
			// so that `git clone` uses the user's intended transport.
			ins.CloneURL = cloneURL
			ins.Branch = branch

			switch {
			case raw.targetDir != "":
				ins.TargetDir = filepath.Join(opts.ParentDir, raw.targetDir)
			case branch != "" && plan[remoteHTTPS].refCount > 1:
				ins.TargetDir = filepath.Join(opts.ParentDir, repoDir+"-"+SanitizeBranchName(branch))
			default:
				ins.TargetDir = filepath.Join(opts.ParentDir, planBaseName(plan, remoteHTTPS))
			}

			// Update fallback for subsequent lines.
			fallbackHTTPS = remoteHTTPS
			if raw.targetDir != "" {
				fallbackBaseName = raw.targetDir
			} else if branch == "" {
				// Full clone: use planned base name.
				fallbackBaseName = planBaseName(plan, remoteHTTPS)
			} else if plan[remoteHTTPS].hasFull {
				// Branch clone when the plan also has a full clone: base is the
				// planned full-clone directory.
				fallbackBaseName = planBaseName(plan, remoteHTTPS)
			} else {
				fallbackBaseName = repoDir + "-" + SanitizeBranchName(branch)
			}
		}

		instructions = append(instructions, ins)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return instructions, nil
}
