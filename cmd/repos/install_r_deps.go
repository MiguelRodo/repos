package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/MiguelRodo/repos/internal/sysutil"
)

type managedRepo struct {
	name string
	path string
}

const (
	// renvInstallExpr bootstraps renv (if needed) then restores from renv.lock.
	renvInstallExpr = `if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}
renv::restore(prompt = FALSE)`
	// remotesInstallExpr bootstraps remotes (if needed) then installs dependencies
	// declared by DESCRIPTION in the current repository.
	remotesInstallExpr = `if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", repos = "https://cloud.r-project.org")
}
remotes::install_deps(dependencies = TRUE)`
)

func runInstallRDeps(args []string) error {
	defaultFile := "repos.list"
	if _, err := os.Stat(defaultFile); err != nil {
		if _, err2 := os.Stat("repos-to-clone.list"); err2 == nil {
			defaultFile = "repos-to-clone.list"
		}
	}

	fs := flag.NewFlagSet("install-r-deps", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	reposFile := fs.String("file", defaultFile, "repos list file")
	fs.StringVar(reposFile, "f", defaultFile, "repos list file")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		installRDepsUsage()
		return nil
	}

	if _, err := exec.LookPath("Rscript"); err != nil {
		return fmt.Errorf("Rscript not found in PATH. Please install R from https://www.r-project.org/ (%w)", err)
	}

	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getting working directory: %w", err)
	}

	st := &state{
		startDir:        cwd,
		parentDir:       filepath.Dir(cwd),
		reposFile:       *reposFile,
		globalFetchMode: "deferred",
		seenRemoteLocal: map[string]string{},
		plan:            map[string]planInfo{},
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

	repos, err := st.collectManagedRepoPaths()
	if err != nil {
		return err
	}
	if len(repos) == 0 {
		fmt.Println("No managed repositories found in repos list.")
		return nil
	}

	var processed, skipped, failed int
	for _, repo := range repos {
		if !dirExists(repo.path) {
			fmt.Printf("[%s] SKIPPED: directory not found (%s)\n", repo.name, repo.path)
			skipped++
			continue
		}

		mode, ok, err := detectRProject(repo.path)
		if err != nil {
			fmt.Printf("[%s] ERROR: failed to inspect project: %v\n", repo.name, err)
			failed++
			continue
		}
		if !ok {
			fmt.Printf("[%s] INFO: no DESCRIPTION or renv.lock, skipping\n", repo.name)
			skipped++
			continue
		}

		fmt.Printf("[%s] Installing R dependencies (%s)\n", repo.name, mode)
		if err := runRInstall(repo, mode); err != nil {
			fmt.Printf("[%s] ERROR: dependency installation failed: %v\n", repo.name, err)
			failed++
			continue
		}
		fmt.Printf("[%s] SUCCESS: dependency installation complete\n", repo.name)
		processed++
	}

	fmt.Println()
	fmt.Println("Summary:")
	fmt.Printf("  Total managed repos   : %d\n", len(repos))
	fmt.Printf("  Installed             : %d\n", processed)
	fmt.Printf("  Skipped               : %d\n", skipped)
	fmt.Printf("  Failed                : %d\n", failed)

	if failed > 0 {
		return fmt.Errorf("%d repositories failed dependency installation", failed)
	}
	return nil
}

func (s *state) collectManagedRepoPaths() ([]managedRepo, error) {
	f, err := os.Open(s.reposFile)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	fallbackHTTPS := s.currentRepoHTTPS
	fallbackLocal := s.startDir
	seenRemoteLocal := map[string]string{}
	for k, v := range s.seenRemoteLocal {
		seenRemoteLocal[k] = v
	}

	repos := make([]managedRepo, 0)
	seenPaths := map[string]bool{}
	addRepo := func(path string) {
		if path == "" || seenPaths[path] {
			return
		}
		repos = append(repos, managedRepo{
			name: filepath.Base(path),
			path: path,
		})
		seenPaths[path] = true
	}

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		trimmed := trimLine(sc.Text())
		if trimmed == "" || lineIsGlobalFlagsOnly(trimmed) {
			continue
		}

		ins, err := s.parseEffectiveLine(trimmed, fallbackHTTPS)
		if err != nil {
			return nil, err
		}
		if ins.repoSpec == "" {
			continue
		}

		if ins.isAtBranch {
			_, branch := splitRepoSpec(ins.repoSpec)
			base := fallbackLocal
			if seen := seenRemoteLocal[fallbackHTTPS]; seen != "" {
				base = seen
			}
			if base == "" {
				base = filepath.Join(s.parentDir, s.planBaseName(fallbackHTTPS))
			}
			dest := ""
			if ins.targetDir != "" {
				dest = filepath.Join(s.parentDir, ins.targetDir)
			} else {
				dest = filepath.Join(s.parentDir, filepath.Base(base)+"-"+sanitizeBranchName(branch))
			}
			addRepo(dest)
			if ins.isWorktree {
				fallbackLocal = base
				seenRemoteLocal[fallbackHTTPS] = base
			} else {
				fallbackLocal = dest
				seenRemoteLocal[fallbackHTTPS] = dest
			}
			continue
		}

		repoNoRef, ref := splitRepoSpec(ins.repoSpec)
		_, repoDir, err := parseRepoURL(repoNoRef)
		if err != nil {
			return nil, err
		}
		remoteHTTPS := specToHTTPS(repoNoRef)
		_, seenBefore := seenRemoteLocal[remoteHTTPS]

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
		addRepo(dest)

		fallbackHTTPS = remoteHTTPS
		if ref == "" {
			fallbackLocal = dest
			seenRemoteLocal[remoteHTTPS] = dest
			continue
		}

		if !seenBefore && s.planHasFull(remoteHTTPS) {
			base := filepath.Join(s.parentDir, s.planBaseName(remoteHTTPS))
			fallbackLocal = base
			seenRemoteLocal[remoteHTTPS] = base
			continue
		}

		fallbackLocal = dest
		seenRemoteLocal[remoteHTTPS] = dest
	}

	if err := sc.Err(); err != nil {
		return nil, err
	}
	return repos, nil
}

func detectRProject(dir string) (mode string, ok bool, err error) {
	if _, err := os.Stat(filepath.Join(dir, "renv.lock")); err == nil {
		return "renv.lock", true, nil
	} else if !os.IsNotExist(err) {
		return "", false, err
	}
	if _, err := os.Stat(filepath.Join(dir, "DESCRIPTION")); err == nil {
		return "DESCRIPTION", true, nil
	} else if !os.IsNotExist(err) {
		return "", false, err
	}
	return "", false, nil
}

func runRInstall(repo managedRepo, mode string) error {
	var expr string
	switch mode {
	case "renv.lock":
		expr = renvInstallExpr
	case "DESCRIPTION":
		expr = remotesInstallExpr
	default:
		return fmt.Errorf("unsupported R dependency mode %q for %s", mode, repo.path)
	}

	cmd := exec.Command("Rscript", "--vanilla", "-e", expr)
	cmd.Dir = repo.path
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}

	if err := cmd.Start(); err != nil {
		return err
	}

	var wg sync.WaitGroup
	errCh := make(chan error, 2)
	wg.Add(2)
	go streamPrefixedOutput(repo.name, stdout, os.Stdout, &wg, errCh)
	go streamPrefixedOutput(repo.name, stderr, os.Stderr, &wg, errCh)
	wg.Wait()
	close(errCh)
	for scanErr := range errCh {
		if scanErr != nil {
			return fmt.Errorf("streaming Rscript output for %s: %w", repo.path, scanErr)
		}
	}

	if err := cmd.Wait(); err != nil {
		return err
	}
	return nil
}

func streamPrefixedOutput(name string, src io.Reader, dst io.Writer, wg *sync.WaitGroup, errCh chan<- error) {
	defer wg.Done()
	reader := bufio.NewReader(src)
	for {
		line, err := reader.ReadString('\n')
		if len(line) > 0 {
			line = strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
			fmt.Fprintf(dst, "[%s] %s\n", name, line)
		}
		if err == io.EOF {
			return
		}
		if err != nil {
			errCh <- err
			return
		}
	}
}

func installRDepsUsage() {
	fmt.Print(`Usage: repos install-r-deps [--file <repo-list>]

Install R dependencies for managed repositories listed in repos.list.

For each managed local repository:
  1. Detects R projects by checking for renv.lock or DESCRIPTION
  2. Runs Rscript inside that repository to install dependencies
  3. Streams output with repository-prefixed log lines

Options:
  -f, --file <file>   Path to repos list file (default: repos.list; falls back to repos-to-clone.list)
  -h, --help          Show this help message.
`)
}
