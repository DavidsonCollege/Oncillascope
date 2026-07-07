# Auto-update via GitHub Releases — Design

**Date:** 2026-07-07
**Status:** Approved (design)
**Repo:** `DavidsonCollege/Oncillascope`

## Goal

Keep the shipped Oncillascope macOS app up to date against new GitHub Releases,
using a **notify-and-prompt** experience: the app checks in the background and,
when a newer release exists, shows a dialog with release notes and an
**Install & Relaunch** action. No silent installs.

This is delivered with the industry-standard macOS updater **Sparkle 2.x**, plus
a **GitHub Actions release pipeline** that builds, signs, notarizes, EdDSA-signs,
and publishes each release together with an **appcast feed hosted on GitHub Pages**.

## Decisions (locked during brainstorming)

| Decision | Choice |
|---|---|
| Update UX | Notify & prompt (Sparkle standard). No silent auto-install. |
| Mechanism | Sparkle 2.x (added to the app target only, not the core package). |
| Scope | In-app updater **plus** full CI release pipeline. |
| Appcast hosting | GitHub Pages: `https://davidsoncollege.github.io/Oncillascope/appcast.xml`. |
| Versioning | Semver git tags `vMAJOR.MINOR.PATCH`; CI stamps the bundle. |

## Non-goals

- Silent/forced updates.
- Delta updates (Sparkle supports them; deferred — full-zip updates only for v1).
- Updating the optional privileged helper out-of-band (the helper ships inside the
  app bundle and is replaced when the app bundle is replaced; no separate helper feed).
- In-app rollback UI (users can re-download an older release manually).

---

## Section 1 — App integration (Sparkle client)

Sparkle is added to the **Xcode app target** (`App/Oncillascope.xcodeproj`) as a
SwiftPM package dependency (`https://github.com/sparkle-project/Sparkle`, 2.x).
It is deliberately **not** added to the `WiFiAnalyzerKit` SwiftPM core package, so
the framework-independent, unit-tested core keeps its "no third-party runtime
dependencies" property. Only the app shell gains the dependency.

**New file:** `App/Oncillascope/UpdaterController.swift`

- Wraps `SPUStandardUpdaterController` (which owns an `SPUUpdater` + standard user
  driver) as an `ObservableObject`/`@StateObject` created in `OncillascopeApp`.
- Exposes `canCheckForUpdates` (published) and a `checkForUpdates()` method.

**Menu integration** in `OncillascopeApp.swift`:

- A dedicated `CommandGroup(after: .appInfo)` (or `replacing: .appVisibility` adjacent
  slot) adds a **"Check for Updates…"** button, disabled while `canCheckForUpdates`
  is false — mirroring the existing pattern where `EmailExportCommandButton` gates on
  a focused value. The button calls `updater.checkForUpdates()`.

**First-run behavior:** On first launch Sparkle presents its standard permission
prompt asking whether to enable **automatic background update checks**. This is the
opt-in moment that keeps the privacy posture honest. Once enabled, Sparkle checks on
its scheduled interval and shows the update dialog when the appcast advertises a newer
`CFBundleVersion`.

**`Info.plist` additions** (`App/Info.plist`):

| Key | Value |
|---|---|
| `SUFeedURL` | `https://davidsoncollege.github.io/Oncillascope/appcast.xml` |
| `SUPublicEDKey` | Base64 Ed25519 **public** key (committed; safe to publish) |
| `SUEnableAutomaticChecks` | *(omitted so Sparkle asks on first run)* |

The app is **non-sandboxed** (`App/Oncillascope.entitlements` has only
`network.client`), so Sparkle's in-process installer path works without the sandboxed
XPC installer services. Hardened runtime is already `YES`. No new entitlements are
required for Sparkle itself beyond outbound network (already present).

---

## Section 2 — Appcast, EdDSA signing keys, and trust model

Two independent signatures protect every update:

1. **Developer ID + notarization** — checked by macOS Gatekeeper (already in place per
   `SIGNING.md`). Protects the binary at first launch / quarantine.
2. **EdDSA (Ed25519) appcast signature** — checked by **Sparkle** before it installs.
   This is what makes a compromised Pages host or a MITM on the feed insufficient to
   ship a malicious update: without the private key, no attacker can produce a matching
   `sparkle:edSignature`.

### Key management

- Generate the keypair **once** with Sparkle's `generate_keys` tool.
- **Public key** → `Info.plist` `SUPublicEDKey`, committed to the repo (public by design).
- **Private key** → stored in the developer's login **Keychain** locally, **and** stored
  as a base64 GitHub Actions secret `SPARKLE_ED_PRIVATE_KEY` for CI. **Never committed.**
- Rotation procedure is documented in `RELEASING.md` (generate new key, ship an app
  update carrying the new `SUPublicEDKey`, then sign subsequent releases with the new key;
  old clients continue trusting old key until they update).

### Appcast structure

`appcast.xml` is an RSS feed; each release is one `<item>`:

- `<sparkle:version>` = `CFBundleVersion` (monotonic integer — Sparkle orders by this).
- `<sparkle:shortVersionString>` = e.g. `1.1.0` (display).
- `<sparkle:minimumSystemVersion>` = `14.0` (matches `LSMinimumSystemVersion`/deployment target).
- `<enclosure url=… length=… sparkle:edSignature=… type="application/octet-stream"/>` where
  `url` is the GitHub Release `.zip` download URL and `length` is its byte size.
- `<sparkle:releaseNotesLink>` → an HTML file published next to the appcast on Pages,
  rendered from the GitHub Release body (Markdown → HTML).

### History preservation

CI fetches the current `appcast.xml` from Pages before regenerating, so previously
released `<item>`s are retained (all historical release zips remain downloadable from
their GitHub Releases). Sparkle's `generate_appcast` merges the new archive into the
existing feed.

---

## Section 3 — CI release pipeline (GitHub Actions, on tag)

**New file:** `.github/workflows/release.yml`
**Trigger:** push of a tag matching `v*.*.*` (e.g. `v1.1.0`).
**Runner:** `macos-14` (Apple Silicon; builds a universal arm64+x86_64 binary).

### Steps

1. **Checkout** the tagged commit.
2. **Import signing assets** into a temporary keychain:
   - Developer ID Application cert from secrets `DEVELOPER_ID_P12` (base64 `.p12`) +
     `DEVELOPER_ID_P12_PASSWORD`.
   - Apple WWDR G3 intermediate (fetched or bundled) — see the gotcha noted in `SIGNING.md`.
   - Create + unlock a throwaway keychain; delete on cleanup.
3. **Version stamping:**
   - `CFBundleShortVersionString` = tag without leading `v` (`1.1.0`).
   - `CFBundleVersion` = explicit integer derived deterministically from the semver:
     `MAJOR*10000 + MINOR*100 + PATCH` (e.g. `1.1.0` → `10100`, `1.2.3` → `10203`).
     Monotonic as long as versions increase, independent of git history, and
     computed straight from the tag (no manual tracking). Constraint: `MINOR` and
     `PATCH` stay `< 100`, which is fine for this project's cadence.
   - Applied via `agvtool`/`PlistBuddy`/xcodebuild build settings.
4. **Build** the Release app with the proven flags from `SIGNING.md`:
   ```
   xcodebuild -scheme Oncillascope -configuration Release -derivedDataPath build \
     CODE_SIGN_STYLE=Manual \
     CODE_SIGN_IDENTITY="Developer ID Application" \
     DEVELOPMENT_TEAM=4Z539UE4TT \
     PROVISIONING_PROFILE_SPECIFIER="" \
     OTHER_CODE_SIGN_FLAGS="--timestamp" \
     CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
     build
   ```
5. **Notarize + staple:**
   - `ditto -c -k --keepParent "$APP" notarize.zip`
   - `xcrun notarytool submit notarize.zip --apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_APP_PASSWORD" --wait`
   - `xcrun stapler staple "$APP"` then `stapler validate`.
6. **Package for distribution:** `ditto -c -k --keepParent "$APP" "Oncillascope-<version>.zip"`
   (the stapled app; this is the file end users download and Sparkle installs).
7. **Sign for Sparkle & update appcast:**
   - Fetch existing `appcast.xml` from the `gh-pages` branch into a working archives dir.
   - Run Sparkle's `generate_appcast` (with `SPARKLE_ED_PRIVATE_KEY`) against the new zip,
     using `--download-url-prefix` pointing at the GitHub Release download URL, to compute
     the EdDSA signature and produce the updated `appcast.xml`.
   - Render the release notes HTML from the tag/release body.
8. **Publish:**
   - `gh release create "$TAG" "Oncillascope-<version>.zip" --title … --notes …`
   - Deploy updated `appcast.xml` + release-notes HTML to the **`gh-pages`** branch
     (Pages source), e.g. via `peaceiris/actions-gh-pages` or a scripted commit.

### Required GitHub Actions secrets

| Secret | Purpose |
|---|---|
| `DEVELOPER_ID_P12` | base64 of the Developer ID Application `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | password for the `.p12` |
| `AC_APPLE_ID` | Apple ID for notarization (`jdmills@davidson.edu`) |
| `AC_TEAM_ID` | `4Z539UE4TT` |
| `AC_APP_PASSWORD` | app-specific password for notarytool |
| `SPARKLE_ED_PRIVATE_KEY` | base64 Ed25519 private key for appcast signing |

Result: cutting a release is **tag → push → done.**

### GitHub Pages setup (one-time)

- Enable Pages on the repo, source = `gh-pages` branch, root.
- First successful workflow run seeds `appcast.xml`.

---

## Section 4 — Docs, honesty fixes, and testing

### README corrections (integrity)

The current README states "No telemetry, no network calls." This becomes accurate:

> No telemetry. The only network activity is the optional Sparkle update check against
> GitHub Releases, which you opt into on first launch and can disable anytime.

- Add Sparkle to the dependency discussion (note it's app-shell-only; the core package
  stays dependency-free).
- Add an **"Updating"** section describing the notify-and-prompt flow.

### New doc: `RELEASING.md`

- The tag → release flow.
- The secrets table and how to set them.
- EdDSA key generation and rotation procedure.
- How to test the pipeline safely (pre-release tag).

### Testing strategy

- **Unit test:** a small pure-Swift `AppcastVersion` comparison helper (correct ordering of
  build numbers / short versions) so version logic is covered like the rest of the core
  (`swift test`). Lives where it can be tested without the app target.
- **Manual E2E checklist** (documented, in the style of the email feature's manual E2E):
  1. Publish a baseline release (e.g. `v0.0.1`) through the pipeline.
  2. Run a locally-built app stamped with a **lower** `CFBundleVersion`.
  3. Confirm: it detects the update, shows release notes, downloads, **verifies the EdDSA
     signature**, installs, and relaunches into the new version.
  4. **Negative test:** tamper one byte of a hosted zip (or use a wrong-key signature) →
     Sparkle must **refuse** to install.
- **CI dry run:** validate `release.yml` on a throwaway pre-release tag before real use.

### Baseline release

There are currently **no tags or releases**. The first real semver tag through the pipeline
establishes the baseline; the appcast is seeded on that run.

---

## Files touched (summary)

**New**
- `App/Oncillascope/UpdaterController.swift`
- `.github/workflows/release.yml`
- `RELEASING.md`
- appcast/release-notes generation lives in CI (published to `gh-pages`)
- unit test for `AppcastVersion` helper (+ the helper itself)

**Modified**
- `App/Oncillascope/OncillascopeApp.swift` — updater `@StateObject` + "Check for Updates…" menu.
- `App/Info.plist` — `SUFeedURL`, `SUPublicEDKey`.
- `App/Oncillascope.xcodeproj/project.pbxproj` — Sparkle SwiftPM dependency on the app target.
- `README.md` — network-activity honesty fix + Updating section + dependency note.

## Open risks / notes

- **Xcode project edits** (`project.pbxproj`) for the SwiftPM dependency are fiddly; safest to
  add Sparkle via Xcode's package UI and commit the resulting diff.
- **Runner Xcode version** must be new enough (Xcode 16+) to match the local toolchain; pin it
  in the workflow.
- **Notarization latency** makes releases take several minutes — acceptable for tag-driven CI.
- **CFBundleVersion is derived from the semver** as `MAJOR*10000 + MINOR*100 + PATCH`; this
  assumes `MINOR`/`PATCH` stay below 100. If the cadence ever exceeds that, widen the
  multipliers (e.g. `*1000000 + *1000`).
