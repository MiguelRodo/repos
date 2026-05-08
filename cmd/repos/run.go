package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
)

type runTarget struct {
	name string
	path string
}

type runResult struct {
	target   runTarget
	exitCode int
	err      error
}

const (
	initialScannerBufferSize = 64 * 1024
	maxScannerBufferSize     = 1024 * 1024
)

func runRun(args []string) error {
	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("getting working directory: %w", err)
	}

	defaultFile := "repos.list"
	if _, err := os.Stat(defaultFile); err != nil {
		if _, err2 := os.Stat("repos-to-clone.list"); err2 == nil {
			defaultFile = "repos-to-clone.list"
		}
	}

	fs := flag.NewFlagSet("run", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	reposFile := fs.String("file", defaultFile, "repos list file")
	fs.StringVar(reposFile, "f", defaultFile, "repos list file")
	concurrent := fs.Bool("concurrent", false, "run command across repos concurrently")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		runUsage()
		return nil
	}

	command := fs.Args()
	if len(command) == 0 {
		runUsage()
		return errors.New("a command is required")
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
	if err := st.initFallback(); err != nil {
		st.currentRepoHTTPS = ""
		st.fallbackRepoHTTPS = ""
	}
	if err := st.planForward(); err != nil {
		return err
	}

	targets, err := st.collectRunTargets()
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		return errors.New("no repositories found in repos list")
	}

	var outMu sync.Mutex
	results := make([]runResult, len(targets))

	if *concurrent {
		var wg sync.WaitGroup
		for i, target := range targets {
			wg.Add(1)
			go func(idx int, t runTarget) {
				defer wg.Done()
				results[idx] = runCommandInTarget(t, command, &outMu)
			}(i, target)
		}
		wg.Wait()
	} else {
		for i, target := range targets {
			results[i] = runCommandInTarget(target, command, &outMu)
		}
	}

	var failures int
	for _, r := range results {
		if r.exitCode != 0 || r.err != nil {
			failures++
		}
	}
	if failures > 0 {
		return fmt.Errorf("%d %s failed", failures, pluralRepo(failures))
	}
	return nil
}

func (s *state) collectRunTargets() ([]runTarget, error) {
	f, err := os.Open(s.reposFile)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var targets []runTarget
	fallbackHTTPS := s.currentRepoHTTPS
	fallbackLocalName := filepath.Base(s.startDir)
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
			repoNoRef, branch := splitRepoSpec(ins.repoSpec)
			destName, baseName, err := s.resolveAtBranchDestName(ins, fallbackHTTPS, fallbackLocalName, repoNoRef, branch)
			if err != nil {
				return nil, err
			}
			destPath := filepath.Join(s.parentDir, destName)
			targets = append(targets, runTarget{name: filepath.Base(destPath), path: destPath})

			if ins.isWorktree {
				if baseName != "" {
					fallbackLocalName = baseName
				}
			} else {
				fallbackLocalName = filepath.Base(destPath)
				if fallbackHTTPS != "" {
					s.seenRemoteLocal[fallbackHTTPS] = destPath
				}
			}
			continue
		}

		repoNoRef, ref := splitRepoSpec(ins.repoSpec)
		_, repoDir, err := parseRepoURL(repoNoRef)
		if err != nil {
			return nil, err
		}
		remoteHTTPS := specToHTTPS(repoNoRef)

		destName := repoDir
		switch {
		case ins.targetDir != "":
			destName = ins.targetDir
		case ref != "" && s.remoteRefCount(remoteHTTPS) > 1:
			destName = repoDir + "-" + sanitizeBranchName(ref)
		}

		destPath := filepath.Join(s.parentDir, destName)
		targets = append(targets, runTarget{name: filepath.Base(destPath), path: destPath})
		fallbackHTTPS = remoteHTTPS
		fallbackLocalName = filepath.Base(destPath)
		s.seenRemoteLocal[remoteHTTPS] = destPath
	}

	if err := sc.Err(); err != nil {
		return nil, err
	}
	return targets, nil
}

func (s *state) resolveAtBranchDestName(ins instruction, fallbackHTTPS, fallbackLocalName, repoNoRef, branch string) (destName string, baseName string, err error) {
	if ins.targetDir != "" {
		return ins.targetDir, "", nil
	}

	if ins.isWorktree {
		baseName = fallbackLocalName
		if baseName == "" && fallbackHTTPS != "" {
			if p := s.seenRemoteLocal[fallbackHTTPS]; p != "" {
				baseName = filepath.Base(p)
			} else {
				baseName = s.planBaseName(fallbackHTTPS)
			}
		}
		if baseName == "" {
			return "", "", errors.New("unable to determine fallback repository for @branch line")
		}
		return baseName + "-" + sanitizeBranchName(branch), baseName, nil
	}

	remoteHTTPS := specToHTTPS(repoNoRef)
	_, repoDir, parseErr := parseRepoURL(repoNoRef)
	if parseErr != nil {
		return "", "", parseErr
	}
	if s.remoteRefCount(remoteHTTPS) > 1 {
		return repoDir + "-" + sanitizeBranchName(branch), "", nil
	}
	return repoDir, "", nil
}

func runCommandInTarget(target runTarget, command []string, outMu *sync.Mutex) runResult {
	res := runResult{target: target}

	info, err := os.Stat(target.path)
	if err != nil || !info.IsDir() {
		res.exitCode = 1
		res.err = fmt.Errorf("directory not found: %s", target.path)
		printPrefixedLine(target.name, "ERROR: "+res.err.Error(), outMu)
		return res
	}

	cmd := exec.Command(command[0], command[1:]...)
	cmd.Dir = target.path

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		res.exitCode = 1
		res.err = fmt.Errorf("capturing stdout: %w", err)
		printPrefixedLine(target.name, "ERROR: "+res.err.Error(), outMu)
		return res
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		res.exitCode = 1
		res.err = fmt.Errorf("capturing stderr: %w", err)
		printPrefixedLine(target.name, "ERROR: "+res.err.Error(), outMu)
		return res
	}

	if err := cmd.Start(); err != nil {
		res.exitCode = 1
		res.err = fmt.Errorf("starting command: %w", err)
		printPrefixedLine(target.name, "ERROR: "+res.err.Error(), outMu)
		return res
	}

	var wg sync.WaitGroup
	readErrs := make(chan error, 2)
	reader := func(r io.Reader) {
		defer wg.Done()
		scanner := bufio.NewScanner(r)
		buffer := make([]byte, initialScannerBufferSize)
		scanner.Buffer(buffer, maxScannerBufferSize)
		for scanner.Scan() {
			printPrefixedLine(target.name, scanner.Text(), outMu)
		}
		if scanErr := scanner.Err(); scanErr != nil {
			readErrs <- scanErr
		}
	}

	wg.Add(2)
	go reader(stdout)
	go reader(stderr)

	wg.Wait()
	waitErr := cmd.Wait()
	close(readErrs)

	for scanErr := range readErrs {
		if isBenignPipeReadError(scanErr) {
			continue
		}
		if res.err == nil {
			res.err = fmt.Errorf("reading process output: %w", scanErr)
		}
		if res.exitCode == 0 {
			res.exitCode = 1
		}
	}

	if waitErr != nil {
		var exitErr *exec.ExitError
		if errors.As(waitErr, &exitErr) {
			res.exitCode = exitErr.ExitCode()
		} else if res.exitCode == 0 {
			res.exitCode = 1
		}
		if res.err == nil {
			res.err = waitErr
		}
		printPrefixedLine(target.name, fmt.Sprintf("ERROR: command exited with code %d", res.exitCode), outMu)
	}

	return res
}

func isBenignPipeReadError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, os.ErrClosed) {
		return true
	}
	return strings.Contains(err.Error(), "file already closed")
}

func printPrefixedLine(repoName, line string, outMu *sync.Mutex) {
	line = strings.TrimRight(line, "\r")
	outMu.Lock()
	defer outMu.Unlock()
	fmt.Fprintf(os.Stdout, "[%s] %s\n", repoName, line)
}

func runUsage() {
	fmt.Print(`Usage: repos run [--file <repo-list>] [--concurrent] <command> [args...]

Execute a command in each local repository path derived from repos.list.
Execution continues across repositories even if some commands fail.
The command exits non-zero if any repository command fails.

Options:
  -f, --file <file>   Repo list file (default: repos.list or repos-to-clone.list)
      --concurrent    Run command across repositories in parallel
  -h, --help          Show this help message.

Examples:
  repos run make test
  repos run --concurrent npm install
`)
}
