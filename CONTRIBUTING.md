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

For input and animation changes, `./test-app.sh --keyboard-only` checks held-key
handling through AppKit and a real PTY. `./test-app.sh --animation-only` measures
deterministic truecolor block frames and saves `AnimationMeasurements.json` and
a frame image next to the test result. These timings measure parsing and bitmap
drawing separately, not overall application frame rate. For a locally installed
interactive animation, set `MOTH_TEST_ANIMATION_COMMAND` to an executable wrapper
and run `./test-app.sh --gloam-only`; the probe runs it for ten seconds, sends `q`,
and checks that the shell is restored. Use a silent local audio file for Gloam.
`./test-app.sh --focus-only` checks AppKit's first-click gate, pane hit testing
and keyboard delivery. Verify physical clicks after switching applications
interactively; synthetic window events do not exercise the window server.
