package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
)

// runBranchUpdate implements `repos branch-update [--dry-run]`.
func runBranchUpdate(args []string) error {
	dryRun := false
	for _, arg := range args {
		if arg == "-n" || arg == "--dry-run" {
			dryRun = true
		} else if arg == "-h" || arg == "--help" {
			branchUpdateUsage()
			return nil
		} else {
			return fmt.Errorf("Unknown option: %s", arg)
		}
	}
	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getting working directory: %w", err)
	}

	projectRoot, err := gitcmd.RunGit(cwd, "rev-parse", "--show-toplevel")
	if err != nil {
		return fmt.Errorf("not inside a Git working tree")
	}

	prebuildFile := filepath.Join(projectRoot, ".devcontainer", "prebuild", "devcontainer.json")
	data, err := os.ReadFile(prebuildFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: prebuild devcontainer not found: %s\n", prebuildFile)
		fmt.Fprintln(os.Stderr, "This file is required to update worktrees.")
		return fmt.Errorf("prebuild devcontainer not found")
	}

	var cfg map[string]interface{}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return fmt.Errorf("failed to parse %s: %w", prebuildFile, err)
	}

	if customizations, ok := cfg["customizations"].(map[string]interface{}); ok {
		if codespaces, ok := customizations["codespaces"].(map[string]interface{}); ok {
			delete(codespaces, "repositories")
		}
	}

	strippedData, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to encode devcontainer: %w", err)
	}
	strippedData = append(strippedData, '\n')

	fmt.Println("Finding worktrees...")

	out, err := gitcmd.RunGit(projectRoot, "worktree", "list", "--porcelain")
	if err != nil {
		return fmt.Errorf("failed to list worktrees: %w", err)
	}

	worktreeCount := 0
	updatedCount := 0
	skippedCount := 0

	lines := strings.Split(out, "\n")
	for _, line := range lines {
		if !strings.HasPrefix(line, "worktree ") {
			continue
		}
		wtPath := strings.TrimPrefix(line, "worktree ")

		if wtPath == projectRoot {
			continue
		}

		worktreeCount++
		fmt.Println()
		fmt.Printf(" [%d] %s\n", worktreeCount, filepath.Base(wtPath))
		fmt.Printf("    Path: %s\n", wtPath)

		dcDir := filepath.Join(wtPath, ".devcontainer")
		if stat, err := os.Stat(dcDir); err != nil || !stat.IsDir() {
			fmt.Println("    ⏭  No .devcontainer directory, skipping")
			skippedCount++
			continue
		}

		destFile := filepath.Join(dcDir, "devcontainer.json")
		if dryRun {
			fmt.Printf("    DRY-RUN: Would update %s\n", destFile)
			updatedCount++
			continue
		}

		if err := os.WriteFile(destFile, strippedData, 0644); err != nil {
			return fmt.Errorf("failed to write %s: %w", destFile, err)
		}

		fmt.Println("    ✓ Updated devcontainer.json")

		if _, err := gitcmd.RunGit(wtPath, "diff", "--quiet", destFile); err == nil {
			fmt.Println("    ℹ️  No changes to commit")
			skippedCount++
		} else {
			if _, err := gitcmd.RunGit(wtPath, "add", "--", ".devcontainer/devcontainer.json"); err != nil {
				return fmt.Errorf("failed to git add: %w", err)
			}
			if _, err := gitcmd.RunGit(wtPath, "commit", "-m", "Update devcontainer from latest prebuild"); err != nil {
				return fmt.Errorf("failed to git commit: %w", err)
			}

			branch, err := gitcmd.RunGit(wtPath, "rev-parse", "--abbrev-ref", "HEAD")
			if err != nil {
				return fmt.Errorf("failed to get current branch: %w", err)
			}
			branch = strings.TrimSpace(branch)

			if _, err := gitcmd.RunGit(wtPath, "push", "origin", "--", branch); err != nil {
				fmt.Println("    ⚠️  Push failed (you may need to push manually)")
			}

			fmt.Println("    ✓ Committed and pushed")
			updatedCount++
		}
	}

	fmt.Println()
	fmt.Println("Summary:")
	fmt.Printf("  Worktrees found: %d\n", worktreeCount)
	fmt.Printf("  Updated: %d\n", updatedCount)
	fmt.Printf("  Skipped: %d\n", skippedCount)

	if dryRun {
		fmt.Println()
		fmt.Println("This was a dry run. Use without --dry-run to apply changes.")
	}

	return nil
}

func branchUpdateUsage() {
	fmt.Print(`Usage: repos branch-update [options]

Update all worktrees with the latest devcontainer prebuild configuration.

This command:
  1. Reads .devcontainer/prebuild/devcontainer.json from the base repo
  2. Strips the codespaces repositories section
  3. Writes to .devcontainer/devcontainer.json in each worktree
  4. Commits and pushes changes to each worktree

Options:
  -n, --dry-run    Show what would be done without making changes
  -h, --help       Show this message
`)
}
