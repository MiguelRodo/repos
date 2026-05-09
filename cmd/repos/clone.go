package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
	"github.com/MiguelRodo/repos/internal/parser"
	"github.com/MiguelRodo/repos/internal/sysutil"
)

// ---------------------------------------------------------------------------
// cloneCommand — implements Command
// ---------------------------------------------------------------------------

type cloneCommand struct{}

func (c *cloneCommand) Name() string { return "clone" }
func (c *cloneCommand) Help() string {
	return "Clone repositories listed in repos.list into the parent directory"
}
func (c *cloneCommand) Run(args []string) error { return runClone(args) }

// ---------------------------------------------------------------------------
// Execution state (clone-specific; no parsing fields)
// ---------------------------------------------------------------------------

type counters struct {
	total        int
	clonedFull   int
	clonedBranch int
	worktrees    int
	skipped      int
	errors       int
}

// execState carries the mutable state needed while executing a list of
// resolved Instructions.  It tracks where repos were actually placed on disk
// so that subsequent worktree operations can find the correct base directory
// even when the actual clone location differs from the planned one.
type execState struct {
	parentDir       string
	startDir        string
	currentHTTPS    string
	seenRemoteLocal map[string]string // remote HTTPS → actual local path
	counts          counters
}

// ---------------------------------------------------------------------------
// runClone
// ---------------------------------------------------------------------------

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
	globalWorktree := fs.Bool("worktree", false, "create @branch lines as worktrees by default")
	fetchDeferred := fs.Bool("fetch-all-deferred", false, "deferred fetch mode (default)")
	fetchSingle := fs.Bool("fetch-single", false, "keep strict single-branch refspec")
	fetchAll := fs.Bool("fetch-all", false, "full clone of all branches")
	force := fs.Bool("force", false, "ignore per-line flag overrides")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		cloneHelp()
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

	if _, err := os.Stat(*reposFile); err != nil {
		return fmt.Errorf("file '%s' not found", *reposFile)
	}

	if err := sysutil.CheckPrerequisites(); err != nil {
		return err
	}

	opts := parser.GlobalOptions{
		Debug:           *debug,
		GlobalWorktree:  *globalWorktree,
		GlobalFetchMode: globalFetchMode,
		CLIWorktreeSet:  *globalWorktree,
		CLIFetchModeSet: *fetchDeferred || *fetchSingle || *fetchAll,
		CLIForce:        *force,
		StartDir:        cwd,
		ParentDir:       filepath.Dir(cwd),
	}

	instructions, err := parser.ParseList(*reposFile, opts)
	if err != nil {
		return err
	}

	currentHTTPS, err := parser.GetCurrentRepoRemoteHTTPS(cwd)
	if err != nil {
		return err
	}

	st := &execState{
		parentDir:    filepath.Dir(cwd),
		startDir:     cwd,
		currentHTTPS: currentHTTPS,
		// Pre-seed with the current repo so worktrees against it work without
		// a separate clone step.
		seenRemoteLocal: map[string]string{currentHTTPS: cwd},
	}

	for _, ins := range instructions {
		fmt.Fprintf(os.Stderr, "Processing: %s\n", gitcmd.SanitizeURL(ins.RemoteURL))

		var (
			lineRC  int
			lineErr error
		)
		if ins.IsWorktree {
			lineRC, lineErr = st.execWorktree(ins)
		} else {
			lineRC, lineErr = st.execClone(ins)
		}

		st.counts.total++
		switch lineRC {
		case 0:
			// success – nothing extra to print
		case 2:
			fmt.Fprintf(os.Stderr, "SKIP: %s\n", gitcmd.SanitizeURL(ins.RemoteURL))
		default:
			st.counts.errors++
			if lineErr != nil {
				fmt.Fprintf(os.Stderr, "ERROR: line failed: %s\n", gitcmd.SanitizeURL(lineErr.Error()))
			} else {
				fmt.Fprintf(os.Stderr, "ERROR: line failed (rc=%d): %s\n", lineRC, gitcmd.SanitizeURL(ins.RemoteURL))
			}
		}
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

// ---------------------------------------------------------------------------
// execClone — execute a non-worktree instruction
// ---------------------------------------------------------------------------

func (st *execState) execClone(ins parser.Instruction) (int, error) {
	remoteHTTPS := ins.RemoteURL
	branch := ins.Branch
	dest := ins.TargetDir

	// Resolve the actual clone URL from the remote URL (handles file://, etc.).
	repoURL, _, err := parser.ParseRepoURL(remoteHTTPS)
	if err != nil {
		return 1, err
	}

	if isGitRepo(dest) {
		existingHTTPS := parser.NormaliseRemoteToHTTPS(gitcmd.SafeGetOriginURL(dest))
		if existingHTTPS != "" && existingHTTPS == remoteHTTPS {
			fmt.Printf("Already exists: %s (matches %s)\n", dest, remoteHTTPS)
			st.seenRemoteLocal[remoteHTTPS] = dest
			st.counts.skipped++
			return 2, nil
		}
		fmt.Printf("Skip: %s is a Git repo for '%s' (wanted '%s'); leaving as-is.\n",
			dest, existingHTTPS, remoteHTTPS)
		st.counts.skipped++
		return 2, nil
	}

	if dirExists(dest) && isNonEmptyDir(dest) {
		fmt.Printf("Skip: %s exists and is not empty (non-Git); leaving as-is.\n", dest)
		st.counts.skipped++
		return 2, nil
	}

	cloneArgs := []string{"clone"}
	if !ins.AllBranches {
		cloneArgs = append(cloneArgs, "--single-branch")
	}

	if branch != "" {
		if _, err := gitcmd.RunGit("", "ls-remote", "--exit-code", "--heads", "--", repoURL, branch); err == nil {
			args := append(append([]string{}, cloneArgs...), "--branch", branch, "--", repoURL, dest)
			fmt.Printf("Cloning %s → %s (branch %s)\n", remoteHTTPS, dest, branch)
			if _, err := gitcmd.RunGit("", args...); err != nil {
				return 1, err
			}
		} else {
			fmt.Printf("Remote branch '%s' not found on %s; creating it.\n", branch, remoteHTTPS)
			fmt.Printf("Cloning default branch of %s → %s\n", remoteHTTPS, dest)
			args := append(cloneArgs, "--", repoURL, dest)
			if _, err := gitcmd.RunGit("", args...); err != nil {
				return 1, err
			}
			if _, err := gitcmd.RunGit(dest, "switch", "-c", branch, "--"); err != nil {
				return 1, err
			}
			if _, err := gitcmd.RunGit(dest, "push", "-u", "origin", "--", "HEAD:"+branch); err != nil {
				return 1, err
			}
		}
		st.counts.clonedBranch++
	} else {
		args := append(cloneArgs, "--", repoURL, dest)
		fmt.Printf("Cloning %s → %s\n", remoteHTTPS, dest)
		if _, err := gitcmd.RunGit("", args...); err != nil {
			return 1, err
		}
		if ins.AllBranches {
			st.counts.clonedFull++
		} else {
			st.counts.clonedBranch++
		}
	}

	if !ins.AllBranches && ins.FetchMode == "deferred" {
		st.ensureWildcardFetchRefspec(dest)
	}
	st.seenRemoteLocal[remoteHTTPS] = dest
	return 0, nil
}

// ---------------------------------------------------------------------------
// execWorktree — execute a worktree instruction
// ---------------------------------------------------------------------------

func (st *execState) execWorktree(ins parser.Instruction) (int, error) {
	branch := ins.Branch
	dest := ins.TargetDir

	// Determine the actual base directory, preferring the runtime-tracked path
	// over the statically-planned one so that "already exists" redirections in
	// execClone are respected.
	base := ins.BaseDir
	if actual, ok := st.seenRemoteLocal[ins.RemoteURL]; ok && actual != "" {
		base = actual
	}

	if !isGitRepo(base) {
		rc, err := st.ensureBaseExists(ins.RemoteURL, base, ins.FetchMode)
		if err != nil {
			return 1, err
		}
		if rc != 0 {
			return rc, nil
		}
	}

	return st.createWorktreeForBranch(base, branch, dest, ins.FetchMode)
}

// ---------------------------------------------------------------------------
// createWorktreeForBranch
// ---------------------------------------------------------------------------

func (st *execState) createWorktreeForBranch(base, branch, dest, fetchMode string) (int, error) {
	if branch == "" {
		return 1, errors.New("error: @branch requires a branch name")
	}
	if base == "" {
		return 1, errors.New("error: no fallback base path available for worktree")
	}

	// Best-effort cleanup of stale worktree references.
	if _, err := gitcmd.RunGit(base, "worktree", "prune"); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: ignoring worktree prune failure for %s: %v\n", base, err)
	}
	if existing := gitcmd.FindWorktreeForBranch(base, branch); existing != "" {
		fmt.Printf("Skip: branch '%s' already checked out at %s\n", branch, existing)
		st.counts.skipped++
		return 2, nil
	}

	if isGitRepo(dest) {
		curb, err := gitcmd.RunGit(dest, "rev-parse", "--abbrev-ref", "HEAD")
		if err == nil && strings.TrimSpace(curb) == branch {
			fmt.Printf("Already exists: %s (branch %s)\n", dest, branch)
		} else if err == nil {
			fmt.Printf("Skip: %s already exists (branch '%s'); leaving as-is.\n", dest, strings.TrimSpace(curb))
		} else {
			fmt.Printf("Skip: %s already exists and is a Git repo; leaving as-is.\n", dest)
		}
		st.counts.skipped++
		return 2, nil
	}
	if dirExists(dest) && isNonEmptyDir(dest) {
		fmt.Fprintf(os.Stderr, "Skip: destination '%s' exists and is not empty; not touching it.\n", dest)
		st.counts.skipped++
		return 2, nil
	}

	if _, err := gitcmd.RunGit(base, "fetch", "--prune", "origin"); err != nil {
		return 1, err
	}

	if gitcmd.LocalBranchExists(base, branch) {
		fmt.Printf("Adding worktree %s (existing local branch '%s')\n", dest, branch)
		if _, err := gitcmd.RunGit(base, "worktree", "add", "--", dest, branch); err != nil {
			return 1, err
		}
		st.counts.worktrees++
		if gitcmd.RemoteBranchExists(base, branch) {
			if fetchMode == "deferred" {
				st.ensureWildcardFetchRefspec(base)
			}
			if fetchMode == "single" {
				st.ensureBranchFetchRefspec(base, branch)
			}
			if _, err := gitcmd.RunGit(dest, "branch", "--set-upstream-to", "origin/"+branch, "--"); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to set upstream for %s: %v\n", branch, err)
			}
		} else {
			if _, err := gitcmd.RunGit(dest, "push", "-u", "origin", "--", "HEAD:"+branch); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to push branch %s: %v\n", branch, err)
			}
		}
		return 0, nil
	}

	if _, err := gitcmd.RunGit(base, "ls-remote", "--exit-code", "--heads", "origin", branch); err == nil {
		fmt.Printf("Branch exists: %s (on remote)\n", branch)
		fmt.Printf("Adding worktree %s (tracking origin/%s)\n", dest, branch)
		// Best-effort fetch of the remote-tracking ref in single-branch clones.
		if _, err := gitcmd.RunGit(base, "fetch", "origin", "refs/heads/"+branch+":refs/remotes/origin/"+branch); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: ignoring remote-tracking fetch failure for %s in %s: %v\n", branch, base, err)
		}
		if gitcmd.RemoteBranchExists(base, branch) {
			if fetchMode == "deferred" {
				st.ensureWildcardFetchRefspec(base)
			}
			if fetchMode == "single" {
				st.ensureBranchFetchRefspec(base, branch)
			}
			if _, err := gitcmd.RunGit(base, "worktree", "add", "-b", branch, "--", dest, "origin/"+branch); err != nil {
				return 1, err
			}
			st.counts.worktrees++
			if _, err := gitcmd.RunGit(dest, "branch", "--set-upstream-to", "origin/"+branch, "--"); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to set upstream for %s: %v\n", branch, err)
			}
			return 0, nil
		}
		defb := gitcmd.DefaultRemoteBranch(base)
		baseRef := "origin/" + defb
		if !gitcmd.RemoteBranchExists(base, defb) {
			baseRef = "HEAD"
		}
		fmt.Printf("Could not resolve origin/%s locally; creating from %s instead\n", branch, baseRef)
		if _, err := gitcmd.RunGit(base, "worktree", "add", "-b", branch, "--", dest, baseRef); err != nil {
			return 1, err
		}
		st.counts.worktrees++
		if _, err := gitcmd.RunGit(dest, "push", "-u", "origin", "--", "HEAD:"+branch); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to push branch %s: %v\n", branch, err)
		}
		return 0, nil
	}

	fmt.Printf("Branch not found: %s (on remote, creating new)\n", branch)
	defb := gitcmd.DefaultRemoteBranch(base)
	baseRef := "origin/" + defb
	if !gitcmd.RemoteBranchExists(base, defb) {
		baseRef = "HEAD"
	}
	fmt.Printf("Adding worktree %s (new branch '%s' from %s)\n", dest, branch, baseRef)
	if _, err := gitcmd.RunGit(base, "worktree", "add", "-b", branch, "--", dest, baseRef); err != nil {
		return 1, err
	}
	if _, err := gitcmd.RunGit(dest, "push", "-u", "origin", "--", "HEAD:"+branch); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to push branch %s: %v\n", branch, err)
	}
	st.counts.worktrees++
	return 0, nil
}

// ---------------------------------------------------------------------------
// ensureBaseExists
// ---------------------------------------------------------------------------

func (st *execState) ensureBaseExists(remote, base, fetchMode string) (int, error) {
	if _, err := gitcmd.RunGit(base, "rev-parse", "--is-inside-work-tree"); err == nil {
		return 0, nil
	}
	if dirExists(base) && isNonEmptyDir(base) {
		fmt.Fprintf(os.Stderr,
			"Error: intended base '%s' exists and is not a Git repo (non-empty). Skipping.\n", base)
		return 2, nil
	}
	if err := os.MkdirAll(base, 0o700); err != nil {
		return 1, err
	}
	cloneArgs := []string{"clone"}
	if fetchMode != "all" {
		cloneArgs = append(cloneArgs, "--single-branch")
	}
	cloneArgs = append(cloneArgs, "--", remote, base)
	if _, err := gitcmd.RunGit("", cloneArgs...); err != nil {
		return 1, fmt.Errorf("error: failed to clone '%s' into '%s': %w", remote, base, err)
	}
	if fetchMode == "all" {
		st.counts.clonedFull++
	} else {
		st.counts.clonedBranch++
		if fetchMode == "deferred" {
			st.ensureWildcardFetchRefspec(base)
		}
	}
	st.seenRemoteLocal[remote] = base
	return 0, nil
}

// ---------------------------------------------------------------------------
// Fetch refspec helpers
// ---------------------------------------------------------------------------

func (st *execState) ensureWildcardFetchRefspec(base string) {
	wild := "+refs/heads/*:refs/remotes/origin/*"
	out, err := gitcmd.RunGit(base, "config", "--get-all", "--", "remote.origin.fetch")
	if err == nil {
		for _, l := range strings.Split(out, "\n") {
			if strings.TrimSpace(l) == wild {
				return
			}
		}
	}
	if _, err := gitcmd.RunGit(base, "config", "--add", "--", "remote.origin.fetch", wild); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not add wildcard fetch refspec in %s: %v\n", base, err)
	}
}

func (st *execState) ensureBranchFetchRefspec(base, branch string) {
	wild := "+refs/heads/*:refs/remotes/origin/*"
	branchRef := "+refs/heads/" + branch + ":refs/remotes/origin/" + branch
	out, err := gitcmd.RunGit(base, "config", "--get-all", "--", "remote.origin.fetch")
	if err == nil {
		for _, l := range strings.Split(out, "\n") {
			entry := strings.TrimSpace(l)
			if entry == wild || entry == branchRef {
				return
			}
		}
	}
	if _, err := gitcmd.RunGit(base, "config", "--add", "--", "remote.origin.fetch", branchRef); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not add branch fetch refspec for %s in %s: %v\n", branch, base, err)
	}
}

// ---------------------------------------------------------------------------
// Filesystem helpers
// ---------------------------------------------------------------------------

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

func isGitRepo(path string) bool {
	if !dirExists(path) {
		return false
	}
	_, err := gitcmd.RunGit(path, "rev-parse", "--is-inside-work-tree")
	return err == nil
}

// ---------------------------------------------------------------------------
// Help text
// ---------------------------------------------------------------------------

func cloneHelp() {
	fmt.Print(`Usage: repos clone [--file <repo-list>] [--debug] [--worktree]
                  [--fetch-all-deferred|--fetch-single|--fetch-all]
                  [--force]

Clone repositories listed in repos.list into the parent directory.

Fetch modes:
  --fetch-all-deferred   (default) clone with --single-branch then restore wildcard refspec
  --fetch-single         keep strict single-branch refspec
  --fetch-all            full clone of all branches

Precedence:
  Per-line flags override global defaults by default.
  Use --force to enforce CLI global flags over per-line overrides.
`)
}

