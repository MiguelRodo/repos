package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/MiguelRodo/repos/internal/gitcmd"
)

// updateResult holds the per-repository update outcome and buffered log lines.
type updateResult struct {
	dir    string
	log    []string
	status string // "updated" | "up-to-date" | "skipped" | "no-remote" | "error"
	err    error
}

// findGitRepos scans the immediate children of baseDir and returns any
// subdirectory that contains a .git entry (regular directory or worktree file).
func findGitRepos(baseDir string) ([]string, error) {
	entries, err := os.ReadDir(baseDir)
	if err != nil {
		return nil, fmt.Errorf("reading directory %s: %w", baseDir, err)
	}
	var repos []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(baseDir, e.Name())
		if _, statErr := os.Stat(filepath.Join(dir, ".git")); statErr == nil {
			repos = append(repos, dir)
		}
	}
	return repos, nil
}

// updateRepo performs the full fetch + fast-forward cycle for a single
// repository and returns an updateResult. It is designed to be called from a
// goroutine; all output is buffered so callers can print it atomically.
func updateRepo(dir string) updateResult {
	res := updateResult{dir: dir}
	name := filepath.Base(dir)

	logf := func(format string, a ...any) {
		res.log = append(res.log, fmt.Sprintf(format, a...))
	}

	// 1. Check working tree is clean.
	statusOut, err := gitcmd.RunGit(dir, "status", "--porcelain")
	if err != nil {
		res.status = "error"
		res.err = fmt.Errorf("git status: %w", err)
		logf("[%s] ✗ git status failed: %v", name, err)
		return res
	}
	if strings.TrimSpace(statusOut) != "" {
		res.status = "skipped"
		logf("[%s] ⏭  uncommitted changes, skipping", name)
		return res
	}

	// 2. Fetch from remote.
	if _, err := gitcmd.RunGit(dir, "fetch"); err != nil {
		res.status = "error"
		res.err = fmt.Errorf("git fetch: %w", err)
		logf("[%s] ✗ fetch failed: %v", name, err)
		return res
	}

	// 3. Check whether the current branch tracks a remote branch.
	if _, err := gitcmd.RunGit(dir, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"); err != nil {
		res.status = "no-remote"
		logf("[%s] ⏭  no upstream tracking branch, skipping merge", name)
		return res
	}

	// 4. Fast-forward merge.
	mergeOut, err := gitcmd.RunGit(dir, "merge", "--ff-only", "@{u}")
	if err != nil {
		res.status = "error"
		res.err = fmt.Errorf("git merge --ff-only: %w", err)
		logf("[%s] ✗ merge failed: %v", name, err)
		return res
	}

	// Different git versions emit slightly different phrasing ("Already up to date."
	// vs "Already up-to-date."); use a case-insensitive check to handle all variants.
	if strings.Contains(strings.ToLower(mergeOut), "already up") {
		res.status = "up-to-date"
		logf("[%s] ✓ Already up to date", name)
	} else {
		res.status = "updated"
		// mergeOut may contain multiple lines (e.g. "Updating abc..def\nFast-forward\n …").
		// Prefix every non-empty line with the repo name for readable output.
		for _, line := range strings.Split(mergeOut, "\n") {
			if strings.TrimSpace(line) != "" {
				logf("[%s] ✓ %s", name, line)
			}
		}
	}
	return res
}

// runUpdateBranches implements `repos update-branches`.
func runUpdateBranches(args []string) error {
	defaultJobs := runtime.NumCPU()
	if defaultJobs < 1 {
		defaultJobs = 1
	}

	fs := flag.NewFlagSet("update-branches", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	dirFlag := fs.String("dir", "", "base directory to scan for repos (default: parent of current directory)")
	fs.StringVar(dirFlag, "d", "", "base directory to scan for repos")
	jobsFlag := fs.Int("jobs", defaultJobs, "maximum number of concurrent git operations")
	fs.IntVar(jobsFlag, "j", defaultJobs, "maximum number of concurrent git operations")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		updateBranchesUsage()
		return nil
	}

	maxJobs := *jobsFlag
	if maxJobs < 1 {
		maxJobs = 1
	}

	baseDir := *dirFlag
	if baseDir == "" {
		cwd, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("getting working directory: %w", err)
		}
		baseDir = filepath.Dir(cwd)
	}

	repos, err := findGitRepos(baseDir)
	if err != nil {
		return err
	}
	if len(repos) == 0 {
		fmt.Printf("No git repositories found in %s\n", baseDir)
		return nil
	}

	repoWord := pluralRepo(len(repos))
	fmt.Printf("Found %d git %s in %s\n", len(repos), repoWord, baseDir)

	// Semaphore channel limits concurrent git network operations to maxJobs.
	sem := make(chan struct{}, maxJobs)

	// Each goroutine writes to its own index — no mutex needed for the slice.
	results := make([]updateResult, len(repos))
	var wg sync.WaitGroup
	for i, dir := range repos {
		wg.Add(1)
		go func(idx int, d string) {
			defer wg.Done()
			sem <- struct{}{}        // acquire slot
			defer func() { <-sem }() // release slot
			results[idx] = updateRepo(d)
		}(i, dir)
	}
	wg.Wait()

	// Print buffered output in deterministic (discovery) order.
	var updated, upToDate, skipped, noRemote, errCount int
	for _, r := range results {
		for _, line := range r.log {
			fmt.Println(line)
		}
		switch r.status {
		case "updated":
			updated++
		case "up-to-date":
			upToDate++
		case "skipped":
			skipped++
		case "no-remote":
			noRemote++
		case "error":
			errCount++
		default:
			// Unknown status — treat as error so it is visible in the summary.
			errCount++
		}
	}

	fmt.Println()
	fmt.Println("Summary:")
	fmt.Printf("  Total repos scanned : %d\n", len(repos))
	fmt.Printf("  Updated             : %d\n", updated)
	fmt.Printf("  Already up to date  : %d\n", upToDate)
	fmt.Printf("  Skipped (dirty)     : %d\n", skipped)
	fmt.Printf("  Skipped (no remote) : %d\n", noRemote)
	fmt.Printf("  Errors              : %d\n", errCount)

	if errCount > 0 {
		return fmt.Errorf("%d %s failed to update", errCount, pluralRepo(errCount))
	}
	return nil
}

// pluralRepo returns "repository" for n==1 and "repositories" otherwise.
func pluralRepo(n int) string {
	if n == 1 {
		return "repository"
	}
	return "repositories"
}

func updateBranchesUsage() {
	fmt.Print(`Usage: repos update-branches [--dir <directory>] [--jobs <n>]

For each git repository found in the base directory, this command:
  1. Checks the working tree is clean (skips if dirty)
  2. Runs git fetch
  3. Checks if the current branch tracks a remote branch
  4. Performs git merge --ff-only @{u} if a tracking branch exists

Repository discovery scans immediate subdirectories of the base directory
for a .git entry (both regular git clones and git worktrees are detected).

Options:
  -d, --dir <dir>    Directory to scan for git repos
                     (default: parent of current working directory)
  -j, --jobs <n>     Maximum concurrent git operations (default: number of CPUs)
  -h, --help         Show this help message.
`)
}
