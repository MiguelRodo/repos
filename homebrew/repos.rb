class Repos < Formula
  desc "Multi-repository management tool"
  homepage "https://github.com/MiguelRodo/repos"
  url "https://github.com/MiguelRodo/repos/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(output: bin/"repos"), "./cmd/repos"
  end

  test do
    # Test that the command exists and shows help
    assert_match "Usage:", shell_output("#{bin}/repos --help")
  end
end
