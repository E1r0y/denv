# Generated release formula; --HEAD tracks main.
# scripts/build_release.py generates an updated formula for each new release.

class Denv < Formula
  desc "Configure Python project environments for direnv"
  homepage "https://github.com/E1r0y/denv"
  url "https://github.com/E1r0y/denv/releases/download/v1.4.0/denv-1.4.0.tar.gz"
  sha256 "559e00fd4ac56b561007effb8f30483bbc11789b102fd03dc0461567af089f95"
  license "MIT"
  head "https://github.com/E1r0y/denv.git", branch: "main"

  depends_on "direnv"

  def install
    bin.install "bin/denv"
    bash_completion.install "completions/bash/denv"
    zsh_completion.install "completions/zsh/_denv"
    fish_completion.install "completions/fish/denv.fish"
  end

  test do
    assert_match "denv version", shell_output("#{bin}/denv --version")
    assert_match "denv workspace status", shell_output("#{bin}/denv status 2>&1", 1)
    system bin/"denv", "init", "--backend", "venv", "--no-create"
    assert_match "dotenv_if_exists .env", (testpath/".envrc").read
    system "bash", "-n", testpath/".envrc"
  end
end
