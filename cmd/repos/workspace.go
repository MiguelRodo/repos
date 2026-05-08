package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

// workspaceFolder represents a single entry in the VS Code workspace folders array.
type workspaceFolder struct {
	Path string `json:"path"`
}

// workspaceFile is the top-level VS Code .code-workspace JSON structure.
// Unknown keys are preserved via the extra map so round-trips don't lose data.
type workspaceFile struct {
	Folders []workspaceFolder      `json:"folders"`
	Extra   map[string]interface{} `json:"-"`
}

// MarshalJSON emits folders first, then any additional keys from Extra.
func (w workspaceFile) MarshalJSON() ([]byte, error) {
	m := make(map[string]interface{}, 1+len(w.Extra))
	for k, v := range w.Extra {
		m[k] = v
	}
	m["folders"] = w.Folders
	return json.Marshal(m)
}

// UnmarshalJSON reads a raw object, extracts "folders", and keeps everything
// else in Extra so we don't silently drop extension settings, etc.
func (w *workspaceFile) UnmarshalJSON(data []byte) error {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	if foldersRaw, ok := raw["folders"]; ok {
		if err := json.Unmarshal(foldersRaw, &w.Folders); err != nil {
			return err
		}
		delete(raw, "folders")
	}
	if len(raw) > 0 {
		w.Extra = make(map[string]interface{}, len(raw))
		for k, v := range raw {
			var val interface{}
			if err := json.Unmarshal(v, &val); err != nil {
				return err
			}
			w.Extra[k] = val
		}
	}
	return nil
}

// findWorkspaceFile returns the path to an existing .code-workspace file in dir.
// It checks for "entire-project.code-workspace" first (the canonical lower-case
// name) and falls back to "EntireProject.code-workspace" (a legacy CamelCase
// variant). If neither exists, the canonical lower-case path is returned so the
// caller can create it.
func findWorkspaceFile(dir string) string {
	canonical := filepath.Join(dir, "entire-project.code-workspace")
	legacy := filepath.Join(dir, "EntireProject.code-workspace")
	if _, err := os.Stat(canonical); err == nil {
		return canonical
	}
	if _, err := os.Stat(legacy); err == nil {
		return legacy
	}
	return canonical
}

// readWorkspace reads and parses a .code-workspace file.
// If the file does not exist it returns an empty workspace (no error).
func readWorkspace(path string) (workspaceFile, error) {
	var ws workspaceFile
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return ws, nil
		}
		return ws, fmt.Errorf("reading workspace file: %w", err)
	}
	if err := json.Unmarshal(data, &ws); err != nil {
		return ws, fmt.Errorf("parsing workspace file %s: %w", path, err)
	}
	return ws, nil
}

// writeWorkspace serialises ws to path with 2-space indentation.
func writeWorkspace(path string, ws workspaceFile) error {
	data, err := json.MarshalIndent(ws, "", "  ")
	if err != nil {
		return fmt.Errorf("marshalling workspace: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("writing workspace file %s: %w", path, err)
	}
	return nil
}

// runWorkspace dispatches workspace sub-commands.
func runWorkspace(args []string) error {
	if len(args) == 0 {
		workspaceUsage()
		return nil
	}
	switch args[0] {
	case "add":
		return runWorkspaceAdd(args[1:])
	case "-h", "--help", "help":
		workspaceUsage()
		return nil
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown workspace command '%s'\n\n", args[0])
		workspaceUsage()
		return errors.New("unknown workspace command")
	}
}

// runWorkspaceAdd implements `repos workspace add <path> [--file <workspace>]`.
func runWorkspaceAdd(args []string) error {
	fs := flag.NewFlagSet("workspace add", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	workspaceFlag := fs.String("file", "", "path to .code-workspace file (default: auto-detect in current directory)")
	fs.StringVar(workspaceFlag, "f", "", "path to .code-workspace file")
	help := fs.Bool("help", false, "show help")
	fs.BoolVar(help, "h", false, "show help")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if *help {
		workspaceAddUsage()
		return nil
	}

	remaining := fs.Args()
	if len(remaining) != 1 {
		workspaceAddUsage()
		return errors.New("exactly one path argument is required")
	}
	addPath := remaining[0]

	// Determine workspace file location.
	wsPath := *workspaceFlag
	if wsPath == "" {
		cwd, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("getting working directory: %w", err)
		}
		wsPath = findWorkspaceFile(cwd)
	}

	ws, err := readWorkspace(wsPath)
	if err != nil {
		return err
	}

	// Check for duplicates.
	for _, f := range ws.Folders {
		if f.Path == addPath {
			fmt.Printf("Path '%s' is already present in %s\n", addPath, wsPath)
			return nil
		}
	}

	ws.Folders = append(ws.Folders, workspaceFolder{Path: addPath})

	if err := writeWorkspace(wsPath, ws); err != nil {
		return err
	}
	fmt.Printf("Added '%s' to %s\n", addPath, wsPath)
	return nil
}

func workspaceUsage() {
	fmt.Print(`Usage: repos workspace <subcommand> [options]

Subcommands:
  add <path>   Add a folder path to the VS Code .code-workspace file

Run 'repos workspace add --help' for more information.
`)
}

func workspaceAddUsage() {
	fmt.Print(`Usage: repos workspace add <path> [--file <workspace-file>]

Arguments:
  <path>   Folder path to add to the workspace (e.g. "../my-repo")

Options:
  -f, --file <file>   Path to the .code-workspace file.
                      Defaults to 'entire-project.code-workspace' (or
                      'EntireProject.code-workspace') in the current directory,
                      creating it if it does not exist.
  -h, --help          Show this help message.
`)
}
