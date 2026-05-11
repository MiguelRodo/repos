package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/MiguelRodo/repos/internal/gitcmd"
)

const (
	addBranchFileMode os.FileMode = 0644
	addBranchDirMode  os.FileMode = 0755
)

// runBranchCreate implements `repos branch-create <branch-name> [target-dir] [--branch]`.
// Flags may appear before or after positional arguments, matching the behaviour
// of the original branch-create.sh script.
func runBranchCreate(args []string) error {
	var branchName, targetDir string
	useBranch := false
	endOfFlags := false

	for i := 0; i < len(args); i++ {
		arg := args[i]
		if endOfFlags {
			if branchName == "" {
				branchName = arg
			} else if targetDir == "" {
				targetDir = arg
			} else {
				return fmt.Errorf("too many arguments: %s", arg)
			}
			continue
		}
		switch arg {
		case "--":
			endOfFlags = true
		case "-b", "--branch":
			useBranch = true
		case "-h", "--help":
			branchCreateUsage()
			return nil
		default:
			if strings.HasPrefix(arg, "-") {
				return fmt.Errorf("unknown option: %s", arg)
			}
			if branchName == "" {
				branchName = arg
			} else if targetDir == "" {
				targetDir = arg
			} else {
				return fmt.Errorf("too many arguments: %s", arg)
			}
		}
	}

	if useBranch {
		return errors.New("--branch mode not yet implemented. Use worktrees instead")
	}
	if branchName == "" {
		branchCreateUsage()
		return errors.New("branch-name is required")
	}

	// Validate branch name: must not start with '-'
	if strings.HasPrefix(branchName, "-") {
		return fmt.Errorf("'%s' is not a valid Git branch name", branchName)
	}
	if _, err := gitcmd.RunGit("", "check-ref-format", "--allow-onelevel", branchName); err != nil {
		return fmt.Errorf("'%s' is not a valid Git branch name", branchName)
	}

	// Validate we are inside a git working tree and find its root.
	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getting working directory: %w", err)
	}
	projectRoot, err := gitcmd.RunGit(cwd, "rev-parse", "--show-toplevel")
	if err != nil {
		return errors.New("not inside a Git working tree")
	}

	parentDir := filepath.Dir(projectRoot)
	repoName := filepath.Base(projectRoot)

	// Validate target directory.
	if targetDir != "" {
		if filepath.IsAbs(targetDir) || strings.Contains(targetDir, "..") || strings.HasPrefix(targetDir, "-") {
			return fmt.Errorf("target directory cannot be absolute, contain '..', or start with a hyphen: %s", targetDir)
		}
	}

	// Determine destination path.
	var dest string
	if targetDir != "" {
		dest = filepath.Join(parentDir, targetDir)
	} else {
		safeBranch := strings.ReplaceAll(branchName, "/", "-")
		dest = filepath.Join(parentDir, repoName+"-"+safeBranch)
	}

	fmt.Printf("Creating worktree: %s\n", dest)
	fmt.Printf("  Branch: %s\n", branchName)
	fmt.Printf("  Base repo: %s\n", projectRoot)

	// Check the destination does not already exist.
	if _, statErr := os.Stat(dest); statErr == nil {
		return fmt.Errorf("destination already exists: %s", dest)
	}

	// Fetch from origin (ignore errors — the remote might not exist yet).
	_, _ = gitcmd.RunGit(projectRoot, "fetch", "--", "origin")

	// Decide whether the branch already exists on origin.
	_, lsErr := gitcmd.RunGit(projectRoot, "ls-remote", "--exit-code", "--heads", "origin", "--", branchName)
	if lsErr == nil {
		fmt.Println("Branch exists on origin, creating tracking worktree...")
		// Refresh the remote tracking ref.
		_, _ = gitcmd.RunGit(projectRoot, "fetch", "--", "origin",
			"refs/heads/"+branchName+":refs/remotes/origin/"+branchName)
		// Attempt to create a new local branch tracking origin/<branch>.
		if _, err := gitcmd.RunGit(projectRoot, "worktree", "add",
			"-b", branchName, "--", dest, "origin/"+branchName); err != nil {
			// Branch ref may already exist locally — fall back to plain checkout.
			if _, err2 := gitcmd.RunGit(projectRoot, "worktree", "add",
				"--", dest, branchName); err2 != nil {
				return fmt.Errorf("creating worktree: %w", err2)
			}
		}
	} else {
		fmt.Println("Creating new branch from current HEAD...")
		if _, err := gitcmd.RunGit(projectRoot, "worktree", "add",
			"-b", branchName, "--", dest); err != nil {
			return fmt.Errorf("creating worktree: %w", err)
		}
		fmt.Println("Pushing branch to origin...")
		if _, err := gitcmd.RunGit(dest, "push", "-u", "origin", "--", branchName); err != nil {
			return fmt.Errorf("pushing branch to origin: %w", err)
		}
	}

	// Clean the worktree to minimal infrastructure.
	fmt.Println("Cleaning worktree to minimal infrastructure...")
	if err := cleanWorktree(dest); err != nil {
		return fmt.Errorf("cleaning worktree: %w", err)
	}

	// Set up the devcontainer configuration.
	fmt.Println("Setting up devcontainer...")
	if err := setupDevcontainer(dest); err != nil {
		return fmt.Errorf("setting up devcontainer: %w", err)
	}

	// Commit and push the infrastructure setup.
	fmt.Println("Committing infrastructure changes...")
	_, _ = gitcmd.RunGit(dest, "add", "-A", "--")
	_, _ = gitcmd.RunGit(dest, "commit", "-m",
		"Initialize "+branchName+" branch with minimal infrastructure", "--")
	_, _ = gitcmd.RunGit(dest, "push", "origin", "--", branchName)

	// Add the branch to repos.list in the base repo.
	fmt.Println("Adding branch to repos.list...")
	reposListPath := filepath.Join(projectRoot, "repos.list")
	if err := addBranchToReposList(reposListPath, branchName, targetDir); err != nil {
		return fmt.Errorf("updating repos.list: %w", err)
	}

	// Add the new worktree path to the VS Code workspace file.
	fmt.Println("Updating VS Code workspace...")
	wsPath := findWorkspaceFile(projectRoot)
	// filepath.Rel on two absolute paths from the same root always succeeds on
	// any supported OS, so the error value is intentionally ignored.
	wsRelPath, _ := filepath.Rel(projectRoot, dest)
	if err := addPathToWorkspace(wsPath, wsRelPath); err != nil {
		fmt.Printf("  Warning: workspace update failed: %v\n", err)
	} else {
		fmt.Println("  ✓ Workspace updated")
	}

	fmt.Println()
	fmt.Println("✅ Worktree created successfully!")
	fmt.Printf("   Location: %s\n", dest)
	fmt.Printf("   Branch: %s\n", branchName)
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Printf("  - Open in VS Code: code %q\n", dest)
	fmt.Printf("  - Or open workspace: code %q\n", wsPath)
	fmt.Printf("  - To remove: git worktree remove %q\n", dest)
	return nil
}

// cleanWorktree removes all entries inside dest except .git, .gitignore, and
// .devcontainer so that the worktree starts with only the minimal scaffolding.
func cleanWorktree(dest string) error {
	entries, err := os.ReadDir(dest)
	if err != nil {
		return fmt.Errorf("reading directory %s: %w", dest, err)
	}
	for _, e := range entries {
		name := e.Name()
		switch name {
		case ".git", ".gitignore", ".devcontainer":
			// keep
		default:
			fmt.Printf("  Removing: %s\n", name)
			if err := os.RemoveAll(filepath.Join(dest, name)); err != nil {
				return err
			}
		}
	}
	return nil
}

// setupDevcontainer moves .devcontainer/prebuild/devcontainer.json to
// .devcontainer/devcontainer.json and strips the codespaces repositories key,
// mirroring the behaviour of branch-create.sh.
func setupDevcontainer(dest string) error {
	prebuildFile := filepath.Join(dest, ".devcontainer", "prebuild", "devcontainer.json")
	targetFile := filepath.Join(dest, ".devcontainer", "devcontainer.json")

	if _, err := os.Stat(prebuildFile); err == nil {
		fmt.Println("  Moving prebuild devcontainer to main location...")
		data, err := os.ReadFile(prebuildFile)
		if err != nil {
			return err
		}

		// Parse and strip customizations.codespaces.repositories.
		var cfg map[string]interface{}
		if jsonErr := json.Unmarshal(data, &cfg); jsonErr == nil {
			if customizations, ok := cfg["customizations"].(map[string]interface{}); ok {
				if codespaces, ok := customizations["codespaces"].(map[string]interface{}); ok {
					delete(codespaces, "repositories")
				}
			}
			out, marshalErr := json.MarshalIndent(cfg, "", "  ")
			if marshalErr == nil {
				out = append(out, '\n')
				if writeErr := os.WriteFile(targetFile, out, addBranchFileMode); writeErr != nil {
					return writeErr
				}
			} else {
				// Marshalling failed — fall back to a plain copy.
				if copyErr := copyFile(prebuildFile, targetFile); copyErr != nil {
					return copyErr
				}
			}
		} else {
			// JSON parse failed — fall back to a plain copy.
			fmt.Println("  Warning: could not parse devcontainer.json; copying as-is")
			if copyErr := copyFile(prebuildFile, targetFile); copyErr != nil {
				return copyErr
			}
		}

		// Remove the now-redundant prebuild directory.
		if err := os.RemoveAll(filepath.Join(dest, ".devcontainer", "prebuild")); err != nil {
			return err
		}
		fmt.Println("  ✓ Devcontainer configured")
		return nil
	}

	if _, err := os.Stat(targetFile); err == nil {
		fmt.Println("  Devcontainer already exists, keeping as-is")
		return nil
	}

	fmt.Println("  Warning: No devcontainer configuration found")
	return nil
}

// copyFile copies src to dst, creating dst if it does not exist.
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	if err := os.MkdirAll(filepath.Dir(dst), addBranchDirMode); err != nil {
		return err
	}
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

// addBranchToReposList appends an @<branch> (and optional target-dir) line to
// the repos.list file if that branch is not already listed.
func addBranchToReposList(path, branch, targetDir string) error {
	exists, err := branchInReposList(path, branch)
	if err != nil {
		return err
	}
	if exists {
		fmt.Println("  Branch already in repos.list")
		return nil
	}

	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, addBranchFileMode)
	if err != nil {
		return err
	}
	defer f.Close()

	var line string
	if targetDir != "" {
		line = fmt.Sprintf("@%s %s\n", branch, targetDir)
	} else {
		line = fmt.Sprintf("@%s\n", branch)
	}
	if _, err := f.WriteString(line); err != nil {
		return err
	}
	fmt.Printf("  ✓ Added @%s to repos.list\n", branch)
	return nil
}

// branchInReposList reports whether a @<branch> line already appears in the
// repos.list file at path. Returns false (no error) if the file does not exist.
func branchInReposList(path, branch string) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	defer f.Close()

	target := "@" + branch
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) > 0 && fields[0] == target {
			return true, nil
		}
	}
	return false, scanner.Err()
}

// addPathToWorkspace adds wsRelPath to the workspace file at wsPath (creating
// the file if necessary), unless the path is already present.
func addPathToWorkspace(wsPath, wsRelPath string) error {
	ws, err := readWorkspace(wsPath)
	if err != nil {
		return err
	}
	for _, f := range ws.Folders {
		if f.Path == wsRelPath {
			fmt.Printf("  Path '%s' is already present in %s\n", wsRelPath, wsPath)
			return nil
		}
	}
	ws.Folders = append(ws.Folders, workspaceFolder{Path: wsRelPath})
	return writeWorkspace(wsPath, ws)
}

func branchCreateUsage() {
	fmt.Print(`Usage: repos branch-create <branch-name> [target-directory] [options]

Create a new worktree off the current repository with minimal infrastructure.

Arguments:
  branch-name        Name of the new branch to create
  target-directory   Optional custom directory name
                     (default: <repo>-<branch> in the parent directory)

Options:
  -b, --branch   Create as a separate branch instead of worktree (not yet implemented)
  -h, --help     Show this help message

What this command does:
  1. Creates a new worktree at ../<repo>-<branch> (or ../target-directory)
  2. Pushes the branch to origin with tracking (for new branches)
  3. Cleans the worktree (keeps only .git, .gitignore, and .devcontainer)
  4. Moves .devcontainer/prebuild/devcontainer.json → .devcontainer/devcontainer.json
  5. Strips codespaces repositories config from devcontainer.json
  6. Commits and pushes the minimal infrastructure
  7. Adds @<branch> line to repos.list
  8. Adds the new path to the VS Code workspace file

Examples:
  repos branch-create data-tidy
  repos branch-create analysis my-analysis
`)
}
