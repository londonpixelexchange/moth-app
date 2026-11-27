# Third-party licence audit

Prepared on 27 November 2026 against the base commits in [README](README.md).
This is an inventory of repository evidence, not a new licence grant for any
third-party component.

| Component | Repository evidence | Terms and candidate treatment |
| --- | --- | --- |
| SwiftTerm, documented v1.10.1 snapshot with local changes | `Vendor/SwiftTerm/Package.swift`, `Vendor/SwiftTerm/LICENSE` | MIT; all vendored files and notices unchanged. |
| TOMLKit, documented 0.6.0 snapshot | `Vendor/TOMLKit/Package.swift`, `Vendor/TOMLKit/LICENSE` | MIT; all vendored files and notices unchanged. |
| toml++ 3.4.0 | `Vendor/TOMLKit/Sources/CTOML/Sources/toml.hpp`, `THIRD-PARTY-NOTICES` | MIT; original notices unchanged. |
| Marked 18.2.1, website build dependency | Website `package-lock.json`, installed `node_modules/marked/LICENSE` | MIT; full installed notice appended to website third-party notices. |
| JetBrains Mono Nerd Font Mono | `Moth/Resources/Fonts/JetBrainsMonoNerdFontMono-*.ttf`, `OFL.txt`, `THIRD-PARTY-NOTICES` | SIL OFL 1.1; website credits now state this explicitly. Font files unchanged. |
| IBM Plex Mono 2.5.0 | App font resources, `IBM-Plex-Mono-LICENSE.txt`, third-party notices | SIL OFL 1.1; unchanged. |
| IBM Plex Sans | `Packaging/IBMPlexSans-Variable.ttf`, `Packaging/IBM-Plex-Sans-OFL.txt`; website `public/assets/IBM-Plex-Sans-OFL.txt` | SIL OFL 1.1; unchanged. |
| Moth Nerd Symbols Mono and Nerd Fonts icon sources | `Moth/Resources/Fonts/Nerd-Fonts-Licences/`, `FontSources/build-manifest.json`, `scripts/build-wumpus-nerd.py` | Overall OFL 1.1 plus component notices including MIT, Apache-2.0 and CC-BY-4.0; kept separate from Moth's GPL grant. |
| GitHub colourblind themes and Primer Primitives | `Moth/Configuration.swift`, third-party notices | MIT; attribution retained and added to website credits. |
| Wumpus Mono Pro | Fourteen separate app TTFs, `FONT-PERMISSION`, adjacent `Wumpus-Licence.txt` | Proprietary, outside GPL. Candidate uses the supplied new permission and preserves the historical permission. |
| Wumpus icon donor | `FontSources/WumpusMonoNerdFontMono-Regular.ttf`, `FontSources/README.txt` | Creator-supplied donor, not embedded in the app; unchanged. Its Wumpus outlines are not relicensed under GPL. |
| Moth name, icon, logo and artwork | `TRADEMARKS`, app icon resources, website artwork | Separate branding policy; modified forks use different name, icon and logo. No GPL grant for the artwork is asserted. |
| Apple frameworks and system libraries | Xcode project, source imports and local library manifests | System SDK dependencies; no third-party binary framework is added by this change. |

The active SwiftTerm package has only a local library and test target; TOMLKit
has only local CTOML and TOMLKit targets. Neither declares an external package
dependency. The Xcode project uses these local packages. There is a historical
`Package.resolved` under the vendored iOS sample app, containing Apple Swift
packages. That sample is not an active Moth target or part of its build graph.
The website's only locked npm dependency is Marked.

The Nerd Fonts donor identifies itself as `3.4.0-96`; the manifest records its
SHA-256 and generated face hashes. Component notices include Font Awesome
(fonts OFL 1.1, icon artwork CC-BY-4.0), Pictogrammers/Material Design
(Apache-2.0), Codicons (CC-BY-4.0), Octicons (MIT), Powerline (MIT), Powerline
Extra (MIT), Pomicons (OFL 1.1), Weather Icons (OFL 1.1), and Devicons source
attributions. Keep the entire bundled notice directory, including source
records and READMEs, rather than replacing it with a generic MIT label.

No GPLv2-only component was found in the active build manifests or supplied
licence notices. MIT and Apache-2.0 code can be incorporated under GPLv3 while
retaining their notices. OFL and other font/icon assets retain their own terms;
they are not relicensed as GPL software. See the
[GNU licence list](https://www.gnu.org/licenses/license-list.html) for licence
compatibility information and [GPLv3 section 5](https://www.gnu.org/licenses/gpl-3.0.html#section5)
for the distinction between a covered work and an aggregate. Packaging fonts
as separate resources is verified here; it does not turn proprietary fonts
into free software.

Historical code and font permissions are saved verbatim. Existing DMGs,
font binaries, screenshots and the owner's untracked website `output/`
directory have not been edited.
