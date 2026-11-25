# Security

Security fixes target the latest published Moth release. Install the current
signed and notarised version from [getmoth.dev](https://getmoth.dev/download/).

Report vulnerabilities privately using
[GitHub private vulnerability reporting](https://github.com/londonpixelexchange/moth-app/security/advisories/new).
Include the affected version, macOS version, reproduction steps and impact.
Do not include passwords, private keys, shell history or other sensitive data.
Please avoid public issues for vulnerabilities until a fix can be coordinated.

Repository changes go through pull requests and passing CI, including changes
by administrators. Do not put signing identities, notarisation credentials or
production deployment secrets in CI or pull requests. Release signing and
notarisation stay in the maintainer's local Keychain.
