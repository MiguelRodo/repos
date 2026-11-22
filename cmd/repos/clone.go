package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/MiguelRodo/repos/v2/internal/parser"
	"github.com/MiguelRodo/repos/v2/internal/sysutil"
)

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
