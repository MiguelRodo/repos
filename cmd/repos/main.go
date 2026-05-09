package main

import (
	"fmt"
	"os"
	"strings"
)

// ---------------------------------------------------------------------------
// Command interface and registry
// ---------------------------------------------------------------------------

// Command is the interface that every repos subcommand must implement.
type Command interface {
	// Name returns the subcommand token used on the CLI (e.g. "clone").
	Name() string
	// Run executes the subcommand with the given arguments.
	Run(args []string) error
	// Help returns the help text for the subcommand.  The first line is used
	// as the short one-line description in the top-level usage listing;
	// subsequent lines (if any) are used when the subcommand's own --help
	// flag is passed.
	Help() string
}

// commands is the ordered registry of all subcommands.  Add new subcommands
// here to have them appear automatically in --help output.
var commands []Command

func init() {
	commands = []Command{
		&cloneCommand{},
	}
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	sub := os.Args[1]
	switch sub {
	case "-h", "--help", "help":
		usage()
		return
	}

	for _, cmd := range commands {
		if cmd.Name() == sub {
			if err := cmd.Run(os.Args[2:]); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			return
		}
	}

	fmt.Fprintf(os.Stderr, "Error: unknown command '%s'\n\n", sub)
	usage()
	os.Exit(1)
}

// ---------------------------------------------------------------------------
// Dynamic usage
// ---------------------------------------------------------------------------

func usage() {
	fmt.Println("Usage: repos <command> [options]")
	fmt.Println()
	fmt.Println("Commands:")
	for _, cmd := range commands {
		// Print only the first line of Help() as a short description.
		short := strings.SplitN(cmd.Help(), "\n", 2)[0]
		fmt.Printf("  %-20s %s\n", cmd.Name(), short)
	}
	fmt.Println()
	fmt.Println("Run 'repos <command> --help' for more information on a command.")
}
