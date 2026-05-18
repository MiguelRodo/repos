## 2025-05-15 - Credential Leakage via Incomplete URL Sanitization
**Vulnerability:** Incomplete sanitization of Git credentials in URLs. The previous regex `(https?://)[^/@\s]+@` stopped at the first `@` character encountered in the credential portion of the URL. If a password or token contained an `@`, the portion after the first `@` would remain in the output, potentially leaking sensitive credentials in logs or error messages.
**Learning:** Sanitization regexes for URLs must be greedy up to the *last* `@` before the host/path begins to handle cases where credentials themselves contain the separator character.
**Prevention:** Use a more inclusive negated character class like `[^/\s]+@` to capture everything from the protocol scheme until the final `@` before the URL path starts.
