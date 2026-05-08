package sysutil

import (
	"fmt"
	"os/exec"
)

func CheckPrerequisites() error {
	for _, tool := range []string{"git"} {
		if _, err := exec.LookPath(tool); err != nil {
			return fmt.Errorf("error: '%s' is required but not found in PATH", tool)
		}
	}
	return nil
}
