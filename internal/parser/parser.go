package parser

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
)

type Options struct {
	InitialFallbackRemote string
	InitialBaseDir        string
	GlobalWorktree        bool
	GlobalFetchMode       string
	CLIForce              bool
	CLIWorktreeSet        bool
	CLIFetchModeSet       bool
}

type Instruction struct {
	RemoteURL   string
	CloneURL    string
	Branch      string
	TargetDir   string
	BaseDir     string
	IsWorktree  bool
	IsAtBranch  bool
	AllBranches bool
	FetchMode   string
	Warnings    []string
}

var ownerRepoRegex = regexp.MustCompile(`^[^/]+/[^/]+$`)
var branchValidationCache sync.Map

func ParseList(r io.Reader, opts Options) ([]Instruction, error) {
	content, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	lines := strings.Split(string(content), "\n")

	globalWorktree := opts.GlobalWorktree
	globalFetchMode := opts.GlobalFetchMode
	if globalFetchMode == "" {
		globalFetchMode = "deferred"
	}
	globalWorktreeForced := false
	globalFetchModeForced := false

	for _, raw := range lines {
		line := trimLine(raw)
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
					globalWorktree = true
					if lineForce {
						globalWorktreeForced = true
					}
				}
			case "--fetch-all-deferred":
				if !opts.CLIFetchModeSet {
					globalFetchMode = "deferred"
					globalFetchModeForced = lineForce
				}
			case "--fetch-single":
				if !opts.CLIFetchModeSet {
					globalFetchMode = "single"
					globalFetchModeForced = lineForce
				}
			case "--fetch-all":
				if !opts.CLIFetchModeSet {
					globalFetchMode = "all"
					globalFetchModeForced = lineForce
				}
			}
		}
	}

	remoteRefCount := map[string]int{}
	fallbackForCount := opts.InitialFallbackRemote
	sc := bufio.NewScanner(strings.NewReader(string(content)))
	for sc.Scan() {
		line := trimLine(sc.Text())
		if line == "" || lineIsGlobalFlagsOnly(line) {
			continue
		}
		first := strings.Fields(line)[0]
		if strings.HasPrefix(first, "@") {
			if fallbackForCount != "" {
				remoteRefCount[specToHTTPS(fallbackForCount)]++
			}
			continue
		}
		repoNoRef, _ := splitRepoSpec(first)
		remote := specToHTTPS(repoNoRef)
		remoteRefCount[remote]++
		fallbackForCount = repoNoRef
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}

	fallbackRemote := opts.InitialFallbackRemote
	fallbackBase := opts.InitialBaseDir
	if fallbackBase == "" && fallbackRemote != "" {
		_, repoDir, err := parseRepoURL(fallbackRemote)
		if err == nil {
			fallbackBase = repoDir
		}
	}
	if fallbackBase == "" {
		fallbackBase = "repo"
	}

	instructions := make([]Instruction, 0)
	lineNum := 0
	sc = bufio.NewScanner(strings.NewReader(string(content)))
	for sc.Scan() {
		lineNum++
		trimmed := trimLine(sc.Text())
		if trimmed == "" || lineIsGlobalFlagsOnly(trimmed) {
			continue
		}

		ins := Instruction{FetchMode: globalFetchMode}
		ignoreLineFlags := opts.CLIForce
		worktreeLocked := globalWorktreeForced
		fetchModeLocked := globalFetchModeForced

		parts := strings.Fields(trimmed)
		first := parts[0]
		rest := parts[1:]

		if strings.HasPrefix(first, "@") {
			branch := strings.TrimPrefix(first, "@")
			if err := validateBranch(branch); err != nil {
				return nil, fmt.Errorf("line %d: %w", lineNum, err)
			}
			if fallbackRemote == "" {
				return nil, fmt.Errorf("line %d: no fallback repository available for %q", lineNum, trimmed)
			}
			useWorktree := globalWorktree
			for _, tok := range rest {
				switch tok {
				case "-w", "--worktree":
					if !ignoreLineFlags && !worktreeLocked {
						useWorktree = true
					}
				case "-a", "--all-branches":
					if !ignoreLineFlags && !fetchModeLocked {
						ins.AllBranches = true
					}
				case "--fetch-all-deferred":
					if !ignoreLineFlags && !fetchModeLocked {
						ins.FetchMode = "deferred"
					}
				case "--fetch-single":
					if !ignoreLineFlags && !fetchModeLocked {
						ins.FetchMode = "single"
					}
				case "--fetch-all":
					if !ignoreLineFlags && !fetchModeLocked {
						ins.FetchMode = "all"
						ins.AllBranches = true
					}
				case "--public", "--private", "--codespaces", "--force":
				default:
					if strings.HasPrefix(tok, "-") {
						return nil, fmt.Errorf("line %d: unknown option %q", lineNum, tok)
					}
					if ins.TargetDir != "" {
						return nil, fmt.Errorf("line %d: multiple target directories on one line", lineNum)
					}
					ins.TargetDir = tok
				}
			}
			ins.IsAtBranch = true
			ins.IsWorktree = useWorktree
			ins.Branch = branch
			ins.CloneURL = fallbackRemote
			ins.RemoteURL = specToHTTPS(fallbackRemote)
			ins.BaseDir = fallbackBase
			if ins.TargetDir == "" {
				ins.TargetDir = fallbackBase + "-" + sanitizeBranchName(branch)
			}
			if err := validateTargetDir(ins.TargetDir); err != nil {
				return nil, fmt.Errorf("line %d: %w", lineNum, err)
			}
			if ins.FetchMode == "all" {
				ins.AllBranches = true
			}
			instructions = append(instructions, ins)
			continue
		}

		repoNoRef, branch := splitRepoSpec(first)
		if strings.HasPrefix(repoNoRef, "-") || strings.Contains(repoNoRef, "..") {
			return nil, fmt.Errorf("line %d: invalid repository spec %q", lineNum, first)
		}
		if branch != "" {
			if err := validateBranch(branch); err != nil {
				return nil, fmt.Errorf("line %d: %w", lineNum, err)
			}
		}
		ins.Branch = branch
		ins.CloneURL = repoNoRef
		ins.RemoteURL = specToHTTPS(repoNoRef)

		for _, tok := range rest {
			switch tok {
			case "-a", "--all-branches":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.AllBranches = true
				}
			case "--fetch-all-deferred":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.FetchMode = "deferred"
				}
			case "--fetch-single":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.FetchMode = "single"
				}
			case "--fetch-all":
				if !ignoreLineFlags && !fetchModeLocked {
					ins.FetchMode = "all"
					ins.AllBranches = true
				}
			case "-w", "--worktree":
				ins.Warnings = append(ins.Warnings, "--worktree ignored on clone line")
			case "--public", "--private", "--codespaces", "--force":
			default:
				if strings.HasPrefix(tok, "-") {
					return nil, fmt.Errorf("line %d: unknown option %q", lineNum, tok)
				}
				if ins.TargetDir != "" {
					return nil, fmt.Errorf("line %d: multiple target directories on one line", lineNum)
				}
				ins.TargetDir = tok
			}
		}
		if ins.FetchMode == "all" {
			ins.AllBranches = true
		}

		_, repoDir, err := parseRepoURL(repoNoRef)
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", lineNum, err)
		}
		ins.BaseDir = repoDir
		if ins.TargetDir == "" {
			if branch != "" {
				if remoteRefCount[ins.RemoteURL] > 1 {
					ins.TargetDir = repoDir + "-" + sanitizeBranchName(branch)
				} else {
					ins.TargetDir = repoDir
				}
			} else {
				ins.TargetDir = repoDir
			}
		}
		if err := validateTargetDir(ins.TargetDir); err != nil {
			return nil, fmt.Errorf("line %d: %w", lineNum, err)
		}

		instructions = append(instructions, ins)
		fallbackRemote = repoNoRef
		fallbackBase = ins.TargetDir
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}

	return instructions, nil
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
	case "--codespaces", "--public", "--private", "--worktree", "--fetch-all-deferred", "--fetch-single", "--fetch-all", "--force":
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

func isWindowsAbsPath(s string) bool {
	return len(s) >= 3 && ((s[1] == ':' && (s[2] == '/' || s[2] == '\\')) || strings.HasPrefix(s, `\\`) || strings.HasPrefix(s, `\`))
}

func validateBranch(branch string) error {
	if branch == "" {
		return fmt.Errorf("missing branch name")
	}
	if strings.HasPrefix(branch, "-") {
		return fmt.Errorf("'%s' is not a valid Git branch name", branch)
	}
	if cached, ok := branchValidationCache.Load(branch); ok {
		if valid, ok := cached.(bool); ok && valid {
			return nil
		}
		return fmt.Errorf("'%s' is not a valid Git branch name", branch)
	}
	cmd := exec.Command("git", "check-ref-format", "--allow-onelevel", branch)
	if err := cmd.Run(); err == nil {
		branchValidationCache.Store(branch, true)
		return nil
	}
	branchValidationCache.Store(branch, false)
	return fmt.Errorf("'%s' is not a valid Git branch name", branch)
}

func validateTargetDir(target string) error {
	if target == "" {
		return nil
	}
	if strings.HasPrefix(target, "/") || strings.HasPrefix(target, `\\`) || isWindowsAbsPath(target) {
		return fmt.Errorf("target directory cannot be absolute: %s", target)
	}
	if strings.Contains(target, "..") {
		return fmt.Errorf("target directory cannot contain '..': %s", target)
	}
	if strings.HasPrefix(target, "-") {
		return fmt.Errorf("target directory cannot start with a hyphen: %s", target)
	}
	return nil
}

func sanitizeBranchName(branch string) string {
	return strings.ReplaceAll(branch, "/", "-")
}

func specToHTTPS(spec string) string {
	s := strings.TrimSpace(spec)
	s = strings.TrimSuffix(s, ".git")
	if strings.HasPrefix(s, "file://") ||
		strings.HasPrefix(s, "/") ||
		strings.HasPrefix(s, `\`) ||
		strings.HasPrefix(s, `.\\`) ||
		strings.HasPrefix(s, `..\\`) ||
		isWindowsAbsPath(s) {
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
	if strings.HasPrefix(s, "ssh://") {
		if i := strings.Index(s, "://"); i >= 0 {
			rest := s[i+3:]
			slash := strings.Index(rest, "/")
			if slash >= 0 {
				start := i + 3 + slash + 1
				if at := strings.LastIndex(s[start:], "@"); at >= 0 {
					idx := start + at
					return s[:idx], s[idx+1:]
				}
			}
		}
		return s, ""
	}
	if strings.HasPrefix(s, "git@") && strings.Contains(s, ":") {
		start := strings.Index(s, ":") + 1
		if at := strings.LastIndex(s[start:], "@"); at >= 0 {
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

func parseRepoURL(repoURLNoRef string) (repoURL, repoDir string, err error) {
	s := repoURLNoRef
	sNoGit := strings.TrimSuffix(s, ".git")
	switch {
	case strings.HasPrefix(s, "file://"):
		repoURL = s
		repoDir = filepath.Base(strings.TrimPrefix(sNoGit, "file://"))
	case strings.HasPrefix(s, "/") ||
		strings.HasPrefix(s, `\`) ||
		strings.HasPrefix(s, `.\\`) ||
		strings.HasPrefix(s, `..\\`) ||
		isWindowsAbsPath(s):
		repoURL = s
		repoDir = filepath.Base(strings.ReplaceAll(sNoGit, `\`, "/"))
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
		return "", "", fmt.Errorf("error: invalid repo spec %q", s)
	}
	if repoDir == "" {
		return "", "", fmt.Errorf("error: invalid repo spec %q", s)
	}
	return repoURL, repoDir, nil
}
