package main

import (
	"io"
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

func TestProcessCreateFileSkipsLocalRemotes(t *testing.T) {
	tmp := t.TempDir()
	list := filepath.Join(tmp, "repos.list")
	local1 := filepath.Join(tmp, "local.git")
	local2 := filepath.Join(tmp, "local2.git")
	content := strings.Join([]string{
		"file://" + local1,
		local2,
		"acme/remote",
	}, "\n")
	if err := os.WriteFile(list, []byte(content), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}

	origExists := ghRepoExistsFunc
	origCreate := ghCreateRepoFunc
	origFallback := resolveCreateFallbackRepoFunc
	defer func() {
		ghRepoExistsFunc = origExists
		ghCreateRepoFunc = origCreate
		resolveCreateFallbackRepoFunc = origFallback
	}()

	resolveCreateFallbackRepoFunc = func() (string, error) { return "", nil }

	var seen []string
	ghRepoExistsFunc = func(ownerRepo string) (bool, error) {
		seen = append(seen, ownerRepo)
		return false, nil
	}
	ghCreateRepoFunc = func(ownerRepo string, private bool) error { return nil }

	if err := processCreateFile(list, true); err != nil {
		t.Fatalf("processCreateFile error: %v", err)
	}
	if len(seen) != 1 || seen[0] != "acme/remote" {
		t.Fatalf("expected only remote repo to be processed, got %#v", seen)
	}
}

func TestProcessCreateFileAtBranchUsesFallbackRepo(t *testing.T) {
	tmp := t.TempDir()
	list := filepath.Join(tmp, "repos.list")
	content := strings.Join([]string{
		"acme/base",
		"@feature-x",
	}, "\n")
	if err := os.WriteFile(list, []byte(content), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}

	origExists := ghRepoExistsFunc
	origCreate := ghCreateRepoFunc
	origBranchExists := ghBranchExistsFunc
	origCreateBranch := ghCreateBranchFunc
	origFallback := resolveCreateFallbackRepoFunc
	defer func() {
		ghRepoExistsFunc = origExists
		ghCreateRepoFunc = origCreate
		ghBranchExistsFunc = origBranchExists
		ghCreateBranchFunc = origCreateBranch
		resolveCreateFallbackRepoFunc = origFallback
	}()

	resolveCreateFallbackRepoFunc = func() (string, error) { return "", nil }
	ghRepoExistsFunc = func(ownerRepo string) (bool, error) { return true, nil }
	ghCreateRepoFunc = func(ownerRepo string, private bool) error { return nil }

	var gotOwnerRepo, gotBranch string
	var createCalled bool
	ghBranchExistsFunc = func(ownerRepo, branch string) (bool, error) {
		gotOwnerRepo = ownerRepo
		gotBranch = branch
		return false, nil
	}
	ghCreateBranchFunc = func(ownerRepo, branch string) error {
		createCalled = true
		return nil
	}

	if err := processCreateFile(list, true); err != nil {
		t.Fatalf("processCreateFile error: %v", err)
	}
	if gotOwnerRepo != "acme/base" || gotBranch != "feature-x" {
		t.Fatalf("expected fallback branch check on acme/base@feature-x, got %s@%s", gotOwnerRepo, gotBranch)
	}
	if !createCalled {
		t.Fatalf("expected missing branch to be created")
	}
}

func TestProcessCreateFileFallbackResolutionErrorDeferredUntilAtBranch(t *testing.T) {
	tmp := t.TempDir()
	list := filepath.Join(tmp, "repos.list")
	content := "acme/remote\n"
	if err := os.WriteFile(list, []byte(content), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}

	origExists := ghRepoExistsFunc
	origCreate := ghCreateRepoFunc
	origFallback := resolveCreateFallbackRepoFunc
	defer func() {
		ghRepoExistsFunc = origExists
		ghCreateRepoFunc = origCreate
		resolveCreateFallbackRepoFunc = origFallback
	}()

	resolveCreateFallbackRepoFunc = func() (string, error) { return "", os.ErrNotExist }
	ghRepoExistsFunc = func(ownerRepo string) (bool, error) { return true, nil }
	ghCreateRepoFunc = func(ownerRepo string, private bool) error { return nil }

	stderr := captureStderr(t, func() {
		if err := processCreateFile(list, true); err != nil {
			t.Fatalf("processCreateFile error: %v", err)
		}
	})
	if strings.Contains(stderr, "unable to resolve initial fallback repository") {
		t.Fatalf("did not expect fallback warning without @branch line, got: %q", stderr)
	}
}

func TestProcessCreateFileAtBranchWarnsWhenInitialFallbackResolutionFailed(t *testing.T) {
	tmp := t.TempDir()
	list := filepath.Join(tmp, "repos.list")
	content := "@feature-x\n"
	if err := os.WriteFile(list, []byte(content), 0o644); err != nil {
		t.Fatalf("write repos.list: %v", err)
	}

	origFallback := resolveCreateFallbackRepoFunc
	defer func() {
		resolveCreateFallbackRepoFunc = origFallback
	}()
	resolveCreateFallbackRepoFunc = func() (string, error) { return "", os.ErrNotExist }

	stderr := captureStderr(t, func() {
		if err := processCreateFile(list, true); err != nil {
			t.Fatalf("processCreateFile error: %v", err)
		}
	})
	if !strings.Contains(stderr, "initial fallback resolution failed") {
		t.Fatalf("expected fallback warning with resolution error, got: %q", stderr)
	}
}

func TestIsLocalRepoSpecTreatsSingleLeadingBackslashAsLocal(t *testing.T) {
	if !isLocalRepoSpec(`\path\to\repo`) {
		t.Fatalf("expected single-leading-backslash path to be treated as local")
	}
}

func TestEnsureBranchExistsOnRepoNormalizesHeadRefPrefix(t *testing.T) {
	origBranchExists := ghBranchExistsFunc
	origCreateBranch := ghCreateBranchFunc
	defer func() {
		ghBranchExistsFunc = origBranchExists
		ghCreateBranchFunc = origCreateBranch
	}()

	var checkedBranch, createdBranch string
	ghBranchExistsFunc = func(ownerRepo, branch string) (bool, error) {
		checkedBranch = branch
		return false, nil
	}
	ghCreateBranchFunc = func(ownerRepo, branch string) error {
		createdBranch = branch
		return nil
	}

	if err := ensureBranchExistsOnRepo("acme/base", "refs/heads/feature/x"); err != nil {
		t.Fatalf("ensureBranchExistsOnRepo error: %v", err)
	}
	if checkedBranch != "feature/x" {
		t.Fatalf("expected branch check to use normalized name, got %q", checkedBranch)
	}
	if createdBranch != "feature/x" {
		t.Fatalf("expected branch creation to use normalized name, got %q", createdBranch)
	}
}

func captureStderr(t *testing.T, fn func()) string {
	t.Helper()

	oldStderr := os.Stderr
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stderr = w
	defer func() {
		os.Stderr = oldStderr
	}()

	fn()

	if err := w.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}
	out, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read stderr: %v", err)
	}
	if err := r.Close(); err != nil {
		t.Fatalf("close reader: %v", err)
	}
	return string(out)
}
