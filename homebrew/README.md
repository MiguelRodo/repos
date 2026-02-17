# Homebrew Formula

This directory contains the Homebrew formula for the `repos` tool.

## Usage

The `repos.rb` file is a template for a Homebrew formula. To use it:

1. **Create a Homebrew tap repository** (e.g., `homebrew-repos`)
2. **Copy `repos.rb`** to the tap repository's `Formula/` directory
3. **Update the URL and SHA256** when releasing new versions
4. Users can then install with:
   ```bash
   brew tap <username>/repos
   brew install repos
   ```

## Updating for Releases

When releasing a new version:

1. Update the `url` field with the new release tag
2. Calculate the SHA256 hash:
   ```bash
   curl -sL https://github.com/MiguelRodo/repos/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
   ```
3. Update the `sha256` field
4. Commit and push to your tap repository

## Homebrew Tap Repository Structure

Your tap repository should have this structure:
```
homebrew-repos/
└── Formula/
    └── repos.rb
```

## More Information

- [Homebrew Documentation](https://docs.brew.sh/)
- [How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
