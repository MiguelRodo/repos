## 2025-05-15 - [Insecure Chmod on Symlinks in Go]
**Vulnerability:** `os.Chmod` in Go follows symbolic links, which can lead to unauthorized permission changes on sensitive files outside the intended scope if an attacker places a symlink in a repository.
**Learning:** Standard library functions like `os.Chmod` and `os.Stat` follow symlinks by default. In a multi-repo management tool that handles potentially untrusted repository content, this creates a "CWE-59: Improper Link Resolution Before File Operation" vulnerability.
**Prevention:** Always use `os.Lstat` to inspect a file before calling `os.Chmod`. Verify that the file is a regular file (`info.Mode().IsRegular()`) and NOT a symlink before attempting to change its permissions.
