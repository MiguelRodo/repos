package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/MiguelRodo/repos/internal/sysutil"
)

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
	force := fs.Bool("force", false, "ignore per-line flag overrides")
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
		startDir:              cwd,
		parentDir:             filepath.Dir(cwd),
		reposFile:             *reposFile,
		debug:                 *debug,
		globalWorktree:        *globalWorktree,
		globalWorktreeForced:  false,
		globalFetchMode:       globalFetchMode,
		globalFetchModeForced: false,
		cliWorktreeSet:        *globalWorktree,
		cliFetchModeSet:       *fetchDeferred || *fetchSingle || *fetchAll,
		cliForce:              *force,
		seenRemoteLocal:       map[string]string{},
		plan:                  map[string]planInfo{},
	}

	if _, err := os.Stat(st.reposFile); err != nil {
		return fmt.Errorf("file '%s' not found", st.reposFile)
	}

	if err := st.applyGlobalFlagsFromFile(); err != nil {
		return err
	}
	if err := sysutil.CheckPrerequisites(); err != nil {
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
