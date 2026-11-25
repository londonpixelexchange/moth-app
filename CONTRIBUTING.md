# Contributing

By submitting a contribution you agree to section 8 of [LICENSE](LICENSE).

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for commit messages and pull request titles.

Use a feature branch and open a pull request against `main`. Build and terminal-core
checks must pass, review discussions must be resolved, and commits must be signed.
Administrators follow the same rules. Keep pull request titles in Conventional
Commit format; squash merges use the title as the commit subject.

Run `./build.sh` and `./test.sh` locally for GUI and terminal validation. CI runs
an unsigned macOS build, terminal-core tests and CodeQL analysis. Signing and
notarisation credentials are never available to pull requests.

GitHub Actions dependencies are pinned to commit SHAs and updated by Dependabot.
See [SECURITY.md](SECURITY.md) for private vulnerability reporting.
