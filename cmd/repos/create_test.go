package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExtractOwnerRepo(t *testing.T) {
	tests := []struct {
		name    string
		spec    string
		want    string
		wantErr bool
	}{
		{name: "owner-repo", spec: "acme/api", want: "acme/api"},
		{name: "owner-repo-with-branch", spec: "acme/api@dev", want: "acme/api"},
		{name: "https-url", spec: "https://github.com/acme/api.git@dev", want: "acme/api"},
		{name: "https-url-with-credentials", spec: "https://token123@github.com/acme/api.git@dev", want: "acme/api"},
		{name: "ssh-url", spec: "git@github.com:acme/api@dev", want: "acme/api"},
		{name: "invalid-local-path", spec: "/tmp/repo", wantErr: true},
		{name: "invalid-format", spec: "acme", wantErr: true},
		{name: "invalid-owner-dots", spec: "..../repo", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := extractOwnerRepo(tt.spec)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("expected error for %q", tt.spec)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("expected %q, got %q", tt.want, got)
			}
		})
	}
}

func TestExtractOwnerRepoDoesNotLeakCredentialsInError(t *testing.T) {
	_, err := extractOwnerRepo("https://supersecret@github.com/not-valid")
	if err == nil {
		t.Fatalf("expected parse error")
	}
	if strings.Contains(err.Error(), "supersecret") {
		t.Fatalf("error should not include credentials: %v", err)
	}
}

func TestParseCreateGlobalVisibility(t *testing.T) {
	tmp := t.TempDir()
	list := filepath.Join(tmp, "repos.list")
	content := strings.Join([]string{
		"--public",
		"acme/a",
		"--private",
		"acme/b",
	}, "\n")
	if err := os.WriteFile(list, []byte(content), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}

	private, err := parseCreateGlobalVisibility(list, true)
	if err != nil {
		t.Fatalf("parseCreateGlobalVisibility error: %v", err)
	}
	if !private {
		t.Fatalf("expected last global visibility to be private")
	}
}

func TestProcessCreateLinePerLineVisibility(t *testing.T) {
	origExists := ghRepoExistsFunc
	origCreate := ghCreateRepoFunc
	defer func() {
		ghRepoExistsFunc = origExists
		ghCreateRepoFunc = origCreate
	}()

	ghRepoExistsFunc = func(ownerRepo string) (bool, error) {
		return false, nil
	}

	var gotRepo string
	var gotPrivate bool
	ghCreateRepoFunc = func(ownerRepo string, private bool) error {
		gotRepo = ownerRepo
		gotPrivate = private
		return nil
	}

	if err := processCreateLine("acme/new-repo --public", true); err != nil {
		t.Fatalf("processCreateLine error: %v", err)
	}
	if gotRepo != "acme/new-repo" {
		t.Fatalf("expected owner/repo acme/new-repo, got %q", gotRepo)
	}
	if gotPrivate {
		t.Fatalf("expected --public to override default private visibility")
	}
}

func TestIsRepoNotFoundError(t *testing.T) {
	if !isRepoNotFoundError("GraphQL: Could not resolve to a Repository with the name") {
		t.Fatalf("expected GraphQL not-found output to be recognized")
	}
	if isRepoNotFoundError("authentication failed") {
		t.Fatalf("did not expect auth failure to be recognized as not-found")
	}
}
