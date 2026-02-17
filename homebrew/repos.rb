class Repos < Formula
  desc "Multi-repository management tool"
  homepage "https://github.com/MiguelRodo/repos"
  url "https://github.com/MiguelRodo/repos/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on "jq"

  def install
    # Install all scripts to libexec to preserve directory structure
    libexec.install "scripts"
    
    # Create a wrapper script in bin that calls the main script
    (bin/"repos").write <<~EOS
      #!/bin/bash
      exec "#{libexec}/scripts/setup-repos.sh" "$@"
    EOS
  end

  test do
    # Test that the command exists and shows help
    assert_match "Usage:", shell_output("#{bin}/repos --help")
  end
end
