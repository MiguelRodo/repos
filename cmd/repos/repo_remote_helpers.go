package main

import (
	"errors"
	"net/url"
	"strings"
)

func ownerRepoFromRemote(remote string) (string, error) {
	trimmed := strings.TrimSpace(strings.TrimSuffix(remote, ".git"))
	if ownerRepoRegex.MatchString(trimmed) {
		return trimmed, nil
	}
	u, err := url.Parse(trimmed)
	if err != nil || u.Path == "" || u.Host == "" {
		return "", errors.New("not a valid repository URL")
	}
	parts := strings.Split(strings.Trim(u.Path, "/"), "/")
	if len(parts) < 2 {
		return "", errors.New("missing owner/repo path")
	}
	candidate := parts[0] + "/" + parts[1]
	if !ownerRepoRegex.MatchString(candidate) {
		return "", errors.New("invalid owner/repo")
	}
	return candidate, nil
}
