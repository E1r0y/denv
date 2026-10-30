# Formula for Homebrew Tap (e.g. E1r0y/homebrew-tap)
# To publish:
# 1. Create a GitHub repo named 'homebrew-tap' under your account (github.com/E1r0y/homebrew-tap).
# 2. Place this file into 'Formula/denv.rb'.
# 3. Calculate sha256 of the release tarball:
#    curl -sL https://github.com/E1r0y/denv/archive/refs/tags/v1.3.0.tar.gz | sha256sum
# 4. Users can then install via:
#    brew tap E1r0y/tap
#    brew install denv

class Denv < Formula
  desc "Atomic, lightning-fast CLI workspace bootstrapper for Python environments and direnv"
  homepage "https://github.com/E1r0y/denv"
  url "https://github.com/E1r0y/denv/archive/refs/tags/v1.3.0.tar.gz"
  sha256 "PUT_RELEASE_TARBALL_SHA256_HERE"
  license "MIT"

  depends_on "direnv"

  def install
    bin.install "bin/denv"
    bash_completion.install "completions/bash/denv"
    zsh_completion.install "completions/zsh/_denv"
    fish_completion.install "completions/fish/denv.fish"
  end

  test do
    assert_match "denv version", shell_output("#{bin}/denv --version")
    assert_match "denv status", shell_output("#{bin}/denv status 2>&1", 1)
  end
end
