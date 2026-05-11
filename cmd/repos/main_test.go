package main

import "testing"

func TestParseRepoURLSupportsWindowsBackslashPathForms(t *testing.T) {
	tests := []struct {
		spec    string
		wantDir string
	}{
		{spec: `\path\to\repo.git`, wantDir: "repo"},
		{spec: `.\\local-repo`, wantDir: "local-repo"},
		{spec: `..\\local-repo.git`, wantDir: "local-repo"},
	}

	for _, tt := range tests {
		t.Run(tt.spec, func(t *testing.T) {
			gotURL, gotDir, err := parseRepoURL(tt.spec)
			if err != nil {
				t.Fatalf("parseRepoURL(%q) error: %v", tt.spec, err)
			}
			if gotURL != tt.spec {
				t.Fatalf("expected URL %q, got %q", tt.spec, gotURL)
			}
			if gotDir != tt.wantDir {
				t.Fatalf("expected dir %q, got %q", tt.wantDir, gotDir)
			}
		})
	}
}
