## 2024-05-23 - [Symlink Following in os.Chmod]
**Vulnerability:** os.Chmod and os.Stat follow symbolic links by default in Go. An attacker could place a symlink at a location the application expects to modify, causing the application to change permissions on an unintended target file (e.g., a sensitive system file).
**Learning:** Go's os.Chmod follows symlinks on many platforms. If the path is controllable or replaceable by an attacker, this leads to privilege escalation or unauthorized file access.
**Prevention:** Always use os.Lstat to verify that a path is a regular file or directory before calling os.Chmod. Ensure that any prior checks on the file also used Lstat to avoid inconsistencies.
