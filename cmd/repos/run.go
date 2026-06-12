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
	"regexp"
	"runtime"
	"strings"
	"sync"
)

type runTarget struct {
	name     string
	path     string
	repoSpec string
	repoType string
	dontRun  bool
}

type runResult struct {
	target   runTarget
	exitCode int
	err      error
}

type runOptions struct {
	reposFile  string
	concurrent bool
	// script defaults to run.sh for pipeline mode.
	script          string
	include         map[string]struct{}
	exclude         map[string]struct{}
	ensureSetup     bool
	skipDeps        bool
	dryRun          bool
	verbose         bool
	continueOnError bool
	explicitCommand []string
}

type pipelineTarget struct {
	target runTarget
	script string
}

type runPipelineStats struct {
	total   int
	success int
	failed  int
	skipped int
}

const (
	initialScannerBufferSize = 64 * 1024
	maxScannerBufferSize     = 1024 * 1024
)

var scriptPathCharPattern = regexp.MustCompile(`^[a-zA-Z0-9._/-]+$`)
var conciseRepoNamePattern = regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)

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

	opts, err := parseRunOptions(args, defaultFile)
	if err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}

	st := &state{
		startDir:        cwd,
		baseDir:         cwd,
		reposFile:       opts.reposFile,
		globalFetchMode: "deferred",
		seenRemoteLocal: map[string]string{},
		plan:            map[string]planInfo{},
	}

	if _, err := os.Stat(st.reposFile); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("file '%s' not found", st.reposFile)
		}
		return fmt.Errorf("checking repos file '%s': %w", st.reposFile, err)
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

	if len(opts.explicitCommand) > 0 {
		return runExplicitCommandMode(st, opts)
	}

	if opts.ensureSetup {
		if opts.dryRun {
			fmt.Printf("DRY-RUN: would execute 'repos clone --file %s'\n", opts.reposFile)
		} else if err := runClone([]string{"--file", opts.reposFile}); err != nil {
			return err
		}
	}
	if !opts.skipDeps {
		if opts.dryRun {
			fmt.Printf("DRY-RUN: would execute 'repos install-r-deps --file %s'\n", opts.reposFile)
		} else if err := runInstallRDeps([]string{"--file", opts.reposFile}); err != nil {
			if opts.verbose {
				fmt.Fprintf(os.Stderr, "Warning: install-r-deps failed: %v\n", err)
			}
		}
	}

	targets, err := st.collectPipelineTargets(opts)
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		return errors.New("no repositories found in repos list")
	}

	stats, err := runPipelineTargets(targets, opts)
	printRunPipelineSummary(stats)
	if err != nil {
		return err
	}
	return nil
}

func runExplicitCommandMode(st *state, opts runOptions) error {
	targets, err := st.collectRunTargets()
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		return errors.New("no repositories found in repos list")
	}

	var outMu sync.Mutex
	results := make([]runResult, len(targets))

	if opts.concurrent {
		var wg sync.WaitGroup
		for i, target := range targets {
			wg.Add(1)
			go func(idx int, t runTarget) {
				defer wg.Done()
				results[idx] = runCommandInTarget(t, opts.explicitCommand, &outMu)
			}(i, target)
		}
		wg.Wait()
	} else {
		for i, target := range targets {
			results[i] = runCommandInTarget(target, opts.explicitCommand, &outMu)
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

func parseRunOptions(args []string, defaultFile string) (runOptions, error) {
	fs := flag.NewFlagSet("run", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)

	opts := runOptions{
		reposFile: defaultFile,
		script:    "run.sh",
	}

	var includeRaw string
	var excludeRaw string
	help := false

	fs.StringVar(&opts.reposFile, "file", defaultFile, "repos list file")
	fs.StringVar(&opts.reposFile, "f", defaultFile, "repos list file")
	fs.BoolVar(&opts.concurrent, "concurrent", false, "run command across repos concurrently")
	fs.StringVar(&opts.script, "script", "run.sh", "script to run in each repository")
	fs.StringVar(&includeRaw, "include", "", "comma-separated list of repositories to include")
	fs.StringVar(&includeRaw, "i", "", "comma-separated list of repositories to include")
	fs.StringVar(&excludeRaw, "exclude", "", "comma-separated list of repositories to exclude")
	fs.StringVar(&excludeRaw, "e", "", "comma-separated list of repositories to exclude")
	fs.BoolVar(&opts.ensureSetup, "ensure-setup", false, "clone repositories before running scripts")
	fs.BoolVar(&opts.skipDeps, "skip-deps", false, "skip install-r-deps step")
	fs.BoolVar(&opts.dryRun, "dry-run", false, "show what would run without executing")
	fs.BoolVar(&opts.verbose, "verbose", false, "enable verbose logging")
	fs.BoolVar(&opts.continueOnError, "continue-on-error", false, "continue processing repositories after failure")
	fs.BoolVar(&help, "help", false, "show help")
	fs.BoolVar(&help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return runOptions{}, err
	}
	if help {
		runUsage()
		return runOptions{}, flag.ErrHelp
	}
	if err := validateRunScriptPath(opts.script); err != nil {
		return runOptions{}, err
	}

	opts.include = parseCSVSet(includeRaw)
	opts.exclude = parseCSVSet(excludeRaw)
	opts.explicitCommand = fs.Args()
	return opts, nil
}

func parseCSVSet(raw string) map[string]struct{} {
	set := map[string]struct{}{}
	for _, part := range strings.Split(raw, ",") {
		name := strings.TrimSpace(part)
		if name == "" {
			continue
		}
		set[name] = struct{}{}
	}
	return set
}

func validateRunScriptPath(script string) error {
	if script == "" {
		return errors.New("script path cannot be empty")
	}
	if isAbsoluteScriptPath(script) || strings.Contains(script, "..") || strings.HasPrefix(script, "-") {
		return fmt.Errorf("invalid script path: %s", script)
	}
	if !scriptPathCharPattern.MatchString(script) {
		return fmt.Errorf("script path must only contain alphanumeric characters, dots, underscores, slashes, or hyphens: %s", script)
	}
	return nil
}

func isAbsoluteScriptPath(script string) bool {
	if filepath.IsAbs(script) {
		return true
	}
	return strings.HasPrefix(filepath.ToSlash(script), "/")
}

func (s *state) collectPipelineTargets(opts runOptions) ([]pipelineTarget, error) {
	concise, err := isConciseRunList(s.reposFile)
	if err != nil {
		return nil, err
	}
	if concise {
		return s.collectConciseRunTargets(opts)
	}

	targets, err := s.collectRunTargets()
	if err != nil {
		return nil, err
	}
	pipelineTargets := make([]pipelineTarget, 0, len(targets))
	for _, t := range targets {
		if !shouldRunRepo(t.name, opts.include, opts.exclude) {
			continue
		}
		if t.dontRun || shouldAutoSkipPipelineRepo(t.repoSpec, t.repoType) {
			continue
		}
		pipelineTargets = append(pipelineTargets, pipelineTarget{
			target: t,
			script: opts.script,
		})
	}
	return pipelineTargets, nil
}

func isConciseRunList(path string) (bool, error) {
	f, err := os.Open(path)
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
		switch {
		case strings.HasPrefix(line, "@"), strings.Contains(line, "/"):
			return false, nil
		}
	}
	if err := sc.Err(); err != nil {
		return false, err
	}
	return true, nil
}

func (s *state) collectConciseRunTargets(opts runOptions) ([]pipelineTarget, error) {
	f, err := os.Open(s.reposFile)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var targets []pipelineTarget
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := trimLine(sc.Text())
		if line == "" || lineIsGlobalFlagsOnly(line) {
			continue
		}
		parts := strings.Fields(line)
		repoName := parts[0]
		if !shouldRunRepo(repoName, opts.include, opts.exclude) {
			continue
		}
		if err := validateConciseRunRepoName(repoName); err != nil {
			return nil, err
		}
		script := opts.script
		hasPerLineScript := false
		dontRun := false
		for _, tok := range parts[1:] {
			if tok == "--dont-run" {
				dontRun = true
				continue
			}
			if hasPerLineScript {
				return nil, fmt.Errorf("invalid concise repos.list line (multiple script values): %s", line)
			}
			script = tok
			hasPerLineScript = true
			if err := validateRunScriptPath(script); err != nil {
				return nil, err
			}
		}
		if dontRun {
			continue
		}
		targets = append(targets, pipelineTarget{
			target: runTarget{
				name: filepath.Base(repoName),
				path: filepath.Join(s.baseDir, repoName),
			},
			script: script,
		})
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return targets, nil
}

func validateConciseRunRepoName(name string) error {
	if filepath.IsAbs(name) || strings.Contains(name, "..") || strings.HasPrefix(name, "-") {
		return fmt.Errorf("invalid repository directory in repos list: %s", name)
	}
	if !conciseRepoNamePattern.MatchString(name) {
		return fmt.Errorf("repository directory must only contain alphanumeric characters, dots, underscores, or hyphens: %s", name)
	}
	return nil
}

func shouldRunRepo(name string, include, exclude map[string]struct{}) bool {
	if len(include) > 0 {
		if _, ok := include[name]; !ok {
			return false
		}
	}
	if len(exclude) > 0 {
		if _, ok := exclude[name]; ok {
			return false
		}
	}
	return true
}

func shouldAutoSkipPipelineRepo(repoSpec, repoType string) bool {
	if repoType != repoTypeHuggingFace {
		return false
	}
	repoURLNoRef, _ := splitRepoSpec(repoSpec)
	trimmed := strings.TrimSpace(repoURLNoRef)
	if len(trimmed) < 3 || !strings.EqualFold(trimmed[:3], "hf:") {
		return false
	}
	hfPath := strings.TrimLeft(trimmed[3:], "/")
	if hfPath == "" {
		return false
	}
	lowerPath := strings.ToLower(hfPath)
	if strings.HasPrefix(lowerPath, "datasets/") || strings.HasPrefix(lowerPath, "models/") {
		return true
	}
	if strings.HasPrefix(lowerPath, "spaces/") {
		return false
	}
	// Default model repos use "owner/model" (without a "models/" prefix).
	return strings.Count(hfPath, "/") == 1
}

func runPipelineTargets(targets []pipelineTarget, opts runOptions) (runPipelineStats, error) {
	stats := runPipelineStats{}
	for _, t := range targets {
		stats.total++
		result := runScriptInTarget(t, opts)
		if result.skipped {
			stats.skipped++
			continue
		}
		if result.err != nil {
			stats.failed++
			if !opts.continueOnError {
				return stats, fmt.Errorf("%d %s failed", stats.failed, pluralRepo(stats.failed))
			}
			continue
		}
		stats.success++
	}
	if stats.failed > 0 {
		return stats, fmt.Errorf("%d %s failed", stats.failed, pluralRepo(stats.failed))
	}
	return stats, nil
}

type runScriptResult struct {
	err     error
	skipped bool
}

func runScriptInTarget(t pipelineTarget, opts runOptions) runScriptResult {
	if opts.dryRun {
		printPrefixedLine(t.target.name, "DRY-RUN: would execute ./"+t.script, nil)
		return runScriptResult{}
	}
	info, err := os.Stat(t.target.path)
	if err != nil || !info.IsDir() {
		printPrefixedLine(t.target.name, "SKIP: directory not found", nil)
		return runScriptResult{skipped: true}
	}

	scriptPath := filepath.Join(t.target.path, t.script)
	if _, err := os.Stat(scriptPath); err != nil {
		printPrefixedLine(t.target.name, "SKIP: no "+t.script+" found", nil)
		return runScriptResult{skipped: true}
	}
	// Security: Use Lstat to ensure we don't follow symlinks when calling Chmod.
	// os.Chmod follows symlinks on many platforms, which could lead to privilege escalation.
	if info, err := os.Lstat(scriptPath); err == nil && info.Mode().IsRegular() {
		if err := os.Chmod(scriptPath, 0o755); err != nil {
			printPrefixedLine(t.target.name, "Warning: could not chmod "+t.script+": "+err.Error(), nil)
		}
	}

	cmd := commandForScript(t.script)
	cmd.Dir = t.target.path
	outMu := &sync.Mutex{}
	res := runCommandWithPrefixedOutput(t.target.name, cmd, outMu)
	if res != nil {
		return runScriptResult{err: res}
	}
	return runScriptResult{}
}

func commandForScript(script string) *exec.Cmd {
	if runtime.GOOS == "windows" {
		if _, err := exec.LookPath("sh"); err == nil {
			return exec.Command("sh", filepath.ToSlash(script))
		}
	}
	return exec.Command("./" + script)
}

func runCommandWithPrefixedOutput(repoName string, cmd *exec.Cmd, outMu *sync.Mutex) error {
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
	readErrs := make(chan error, 2)
	reader := func(r io.Reader) {
		defer wg.Done()
		sc := bufio.NewScanner(r)
		buffer := make([]byte, initialScannerBufferSize)
		sc.Buffer(buffer, maxScannerBufferSize)
		for sc.Scan() {
			printPrefixedLine(repoName, sc.Text(), outMu)
		}
		if scanErr := sc.Err(); scanErr != nil {
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
		if !isBenignPipeReadError(scanErr) {
			return scanErr
		}
	}
	if waitErr != nil {
		var exitErr *exec.ExitError
		if errors.As(waitErr, &exitErr) {
			printPrefixedLine(repoName, fmt.Sprintf("ERROR: command exited with code %d", exitErr.ExitCode()), outMu)
		}
		return waitErr
	}
	return nil
}

func printRunPipelineSummary(stats runPipelineStats) {
	fmt.Println()
	fmt.Println("Summary:")
	fmt.Printf("  Total repositories : %d\n", stats.total)
	fmt.Printf("  Succeeded          : %d\n", stats.success)
	fmt.Printf("  Failed             : %d\n", stats.failed)
	fmt.Printf("  Skipped            : %d\n", stats.skipped)
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
			destPath := filepath.Join(s.baseDir, destName)
			targets = append(targets, runTarget{
				name:     filepath.Base(destPath),
				path:     destPath,
				repoSpec: ins.repoSpec,
				repoType: ins.repoType,
				dontRun:  ins.dontRun,
			})

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

		destPath := filepath.Join(s.baseDir, destName)
		targets = append(targets, runTarget{
			name:     filepath.Base(destPath),
			path:     destPath,
			repoSpec: ins.repoSpec,
			repoType: ins.repoType,
			dontRun:  ins.dontRun,
		})
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
	if err != nil {
		res.exitCode = 1
		if errors.Is(err, os.ErrNotExist) {
			res.err = fmt.Errorf("directory not found: %s", target.path)
		} else {
			res.err = fmt.Errorf("checking directory %s: %w", target.path, err)
		}
		printPrefixedLine(target.name, "ERROR: "+res.err.Error(), outMu)
		return res
	}
	if !info.IsDir() {
		res.exitCode = 1
		res.err = fmt.Errorf("path is not a directory: %s", target.path)
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
	if outMu != nil {
		outMu.Lock()
		defer outMu.Unlock()
	}
	fmt.Fprintf(os.Stdout, "[%s] %s\n", repoName, line)
}

func runUsage() {
	fmt.Print(`Usage: repos run [options] [command [args...]]

Run mode:
  Without an explicit command, runs scripts across repositories (run-pipeline parity).
  With an explicit command, executes that command in each repository path.

Options:
  -f, --file <file>        Repo list file (default: repos.list or repos-to-clone.list)
      --script <path>      Script to run in script mode (default: run.sh)
                            Per-line --dont-run entries in repos.list are skipped.
                            Hugging Face dataset/model entries are also skipped.
  -i, --include <names>    Comma-separated repository names to include
  -e, --exclude <names>    Comma-separated repository names to exclude
      --ensure-setup       Run clone step before script execution
      --skip-deps          Skip install-r-deps step (deps run by default)
      --dry-run            Show actions without executing
      --verbose            Enable verbose logging
      --continue-on-error  Continue after script failures
      --concurrent         Run explicit command mode in parallel
  -h, --help               Show this help message.

Examples:
  repos run
  repos run --script pipeline.sh --continue-on-error
  repos run make test
  repos run --concurrent npm install
`)
}

// pluralRepo returns "repository" for n==1 and "repositories" otherwise.
func pluralRepo(n int) string {
	if n == 1 {
		return "repository"
	}
	return "repositories"
}
