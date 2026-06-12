package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/MiguelRodo/repos/v2/internal/parser"
	"github.com/MiguelRodo/repos/v2/internal/sysutil"
)

var hasNonLocalRemotesInFileFunc = hasNonLocalRemotesInFile
var checkNonInteractiveAuthForCloneFunc = checkNonInteractiveAuthForClone

func runClone(args []string) error {
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}

	// Pre-process --debug-file to support the optional-value form.
	processedArgs, autoDebugPath, err := preProcessDebugFileFlag(args)
	if err != nil {
		return err
	}
	if autoDebugPath != "" {
		fmt.Fprintf(os.Stderr, "Debug output will be written to: %s\n", autoDebugPath)
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
	debugFile := fs.String("debug-file", "", "write debug output to file (auto-generate temp if no path given)")
	globalWorktree := fs.Bool("worktree", false, "create @branch as worktrees by default")
	fetchDeferred := fs.Bool("fetch-all-deferred", false, "deferred fetch mode")
	fetchSingle := fs.Bool("fetch-single", false, "single fetch mode")
	fetchAll := fs.Bool("fetch-all", false, "all fetch mode")
	depth := fs.Int("depth", 0, "opt-in shallow clone depth")
	force := fs.Bool("force", false, "ignore per-line flag overrides")
	create := fs.Bool("create", false, "create missing remote branches when requested branch is absent")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(processedArgs); err != nil {
		return err
	}
	if *help {
		cloneUsage()
		return nil
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
	depthSet := false
	for i := 0; i < len(processedArgs); i++ {
		arg := processedArgs[i]
		if arg == "--depth" || strings.HasPrefix(arg, "--depth=") {
			depthSet = true
			break
		}
	}
	if depthSet && *depth <= 0 {
		return errors.New("error: --depth must be a positive integer")
	}

	st := &state{
		startDir:              cwd,
		baseDir:               cwd,
		reposFile:             *reposFile,
		debug:                 *debug,
		debugWriter:           debugWriter,
		globalWorktree:        *globalWorktree,
		globalWorktreeForced:  false,
		globalFetchMode:       globalFetchMode,
		globalFetchModeForced: false,
		globalDepth:           *depth,
		globalDepthForced:     false,
		cliWorktreeSet:        *globalWorktree,
		cliFetchModeSet:       *fetchDeferred || *fetchSingle || *fetchAll,
		cliDepthSet:           depthSet,
		cliForce:              *force,
		allowCreate:           *create,
		seenRemoteLocal:       map[string]string{},
		plan:                  map[string]planInfo{},
	}

	if _, err := os.Stat(st.reposFile); err != nil {
		return fmt.Errorf("file '%s' not found", st.reposFile)
	}

	if err := st.applyGlobalFlagsFromFile(); err != nil {
		return err
	}
	if err := sysutil.CheckClonePrerequisites(st.reposFile); err != nil {
		return err
	}
	hasNonLocal, err := hasNonLocalRemotesInFileFunc(st.reposFile)
	if err != nil {
		return err
	}
	if hasNonLocal {
		if err := checkNonInteractiveAuthForCloneFunc(); err != nil {
			return err
		}
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

	if file, err := os.Open(st.reposFile); err == nil {
		base := filepath.Base(cwd)
		if instructions, err := parser.ParseList(file, parser.Options{
			InitialFallbackRemote: base,
			InitialBaseDir:        base,
		}); err == nil {
			updateGitignore(cwd, instructions)
		}
		file.Close()
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

func isLocalRepoSpecForAuthCheck(repoSpec string) bool {
	switch {
	case strings.HasPrefix(repoSpec, "file://"),
		strings.HasPrefix(repoSpec, "/"),
		strings.HasPrefix(repoSpec, `\`),
		isWindowsAbsPath(repoSpec),
		strings.HasPrefix(repoSpec, "./"),
		strings.HasPrefix(repoSpec, "../"),
		strings.HasPrefix(repoSpec, `.\\`),
		strings.HasPrefix(repoSpec, `..\\`):
		return true
	default:
		return false
	}
}

func hasNonLocalRemotesInFile(reposFile string) (bool, error) {
	f, err := os.Open(reposFile)
	if err != nil {
		return false, err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := trimLine(sc.Text())
		if line == "" || lineIsGlobalFlagsOnly(line) {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) == 0 {
			continue
		}
		first := parts[0]
		if strings.HasPrefix(first, "@") {
			continue
		}
		if strings.HasPrefix(first, "git@github.com:") || strings.HasPrefix(first, "ssh://git@github.com/") {
			return true, nil
		}
		repoSpec, _ := splitRepoSpec(first)
		if strings.HasPrefix(strings.ToLower(strings.TrimSpace(repoSpec)), "hf:") {
			continue
		}
		if isLocalRepoSpecForAuthCheck(repoSpec) {
			continue
		}
		normalized := normaliseRemoteToHTTPS(repoSpec)
		if strings.HasPrefix(repoSpec, "https://") ||
			strings.HasPrefix(repoSpec, "http://") ||
			strings.HasPrefix(normalized, "https://github.com/") ||
			strings.HasPrefix(normalized, "http://github.com/") ||
			ownerRepoRegex.MatchString(repoSpec) {
			return true, nil
		}
	}
	if err := sc.Err(); err != nil {
		return false, err
	}
	return false, nil
}

// checkNonInteractiveAuthForClone verifies that at least one non-interactive
// git authentication method is available before attempting remote clones.
func checkNonInteractiveAuthForClone() error {
	if sock := strings.TrimSpace(os.Getenv("SSH_AUTH_SOCK")); sock != "" {
		if st, err := os.Stat(sock); err == nil && st.Mode()&os.ModeSocket != 0 {
			if _, err := exec.LookPath("ssh-add"); err == nil {
				if err := exec.Command("ssh-add", "-l").Run(); err == nil {
					return nil
				}
			}
		}
	}

	_, err := sysutil.DiscoverGitHubToken()
	return err
}

// updateGitignore safely appends new directories to .gitignore without creating duplicates
func updateGitignore(cwd string, instructions []parser.Instruction) {
	ignorePath := filepath.Join(cwd, ".gitignore")
	existing := make(map[string]bool)

	// Read existing entries to avoid duplicates
	if data, err := os.ReadFile(ignorePath); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			existing[strings.TrimSpace(line)] = true
		}
	}

	f, err := os.OpenFile(ignorePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()

	for _, ins := range instructions {
		if !existing[ins.TargetDir] {
			f.WriteString(ins.TargetDir + "\n")
			existing[ins.TargetDir] = true // mark as added
		}
	}
}