# Contributing

Contributions to Moth’s own code and documentation are licensed under
`GPL-3.0-or-later`; see [LICENSE](LICENSE). Vendored components retain their
own licences, and changes to them must follow those licences.

Every contribution commit needs a Developer Certificate of Origin (DCO)
sign-off. Read [DCO 1.1](https://developercertificate.org/), then use
`git commit -s` to add `Signed-off-by: Your Name <your-email@example.com>`.
Only sign off work you have the right to contribute. No CLA is required.
The DCO sign-off is separate from the cryptographic commit signature
required below. Preserve contributor sign-offs when squashing commits.

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
