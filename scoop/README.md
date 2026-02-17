# Scoop Manifest

This directory contains the Scoop manifest for the `repos` tool.

## Usage

The `repos.json` file is a template for a Scoop manifest. To use it:

1. **Create a Scoop bucket repository** (e.g., `scoop-bucket`)
2. **Copy `repos.json`** to your bucket repository
3. **Update the version and hash** when releasing new versions
4. Users can then install with:
   ```powershell
   scoop bucket add <username> https://github.com/<username>/scoop-bucket
   scoop install repos
   ```

## Updating for Releases

When releasing a new version:

1. Update the `version` field
2. Calculate the SHA256 hash of the release archive:
   ```powershell
   (Get-FileHash -Algorithm SHA256 v1.0.0.zip).Hash
   ```
3. Update the `hash` field with the calculated hash
4. Commit and push to your bucket repository

## Scoop Autoupdate

The manifest includes an `autoupdate` configuration that allows Scoop to automatically update the manifest when new releases are published.

## More Information

- [Scoop Documentation](https://scoop.sh/)
- [Creating Buckets](https://github.com/ScoopInstaller/Scoop/wiki/Buckets)
- [App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
