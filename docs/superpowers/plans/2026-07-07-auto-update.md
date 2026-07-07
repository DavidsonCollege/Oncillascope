# Auto-Update (Sparkle + GitHub Releases CI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a notify-and-prompt auto-updater for the Oncillascope macOS app, fed by an EdDSA-signed appcast on GitHub Pages that a tag-triggered GitHub Actions pipeline builds, signs, notarizes, and publishes.

**Architecture:** Sparkle 2.x is added to the Xcode **app target only** (the `WiFiAnalyzerKit` SwiftPM core stays dependency-free). A new pure-Swift `AppUpdateSupport` SwiftPM target holds the unit-testable version-comparison helper. A `.github/workflows/release.yml` runs on semver tags, producing a notarized zip + EdDSA-signed `appcast.xml` deployed to `gh-pages` and a GitHub Release.

**Tech Stack:** Swift 6 / SwiftUI, Sparkle 2.x (SwiftPM), Xcode 16+, GitHub Actions (`macos-14`), `notarytool`, Sparkle CLI tools (`generate_keys`, `generate_appcast`), GitHub Pages.

## Global Constraints

- **Platform floor:** macOS 14 (`LSMinimumSystemVersion` / deployment target `14.0`); appcast `sparkle:minimumSystemVersion` = `14.0`.
- **Core package stays dependency-free:** Sparkle is added to the Xcode app target only, never to `Package.swift` product targets. The one new `Package.swift` target (`AppUpdateSupport`) is pure Swift/Foundation with no third-party deps.
- **Team / signing:** Developer ID Application, `DEVELOPMENT_TEAM=4Z539UE4TT`, hardened runtime `YES`, build flags `OTHER_CODE_SIGN_FLAGS="--timestamp"` and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` (from `SIGNING.md`).
- **Feed URL (verbatim):** `https://davidsoncollege.github.io/Oncillascope/appcast.xml`
- **Version scheme:** git tag `vMAJOR.MINOR.PATCH`; `CFBundleShortVersionString` = tag minus `v`; `CFBundleVersion` = `MAJOR*10000 + MINOR*100 + PATCH` (MINOR/PATCH < 100).
- **Update UX:** notify-and-prompt only. No silent installs. First-run shows Sparkle's automatic-check permission prompt.
- **EdDSA private key** is never committed — Keychain locally, `SPARKLE_ED_PRIVATE_KEY` secret in CI. Public key (`SUPublicEDKey`) is committed in `Info.plist`.
- **Secrets (verbatim names):** `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `AC_APPLE_ID`, `AC_TEAM_ID`, `AC_APP_PASSWORD`, `SPARKLE_ED_PRIVATE_KEY`.
- **Commit trailer:** end every commit message with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

**New**
- `Sources/AppUpdateSupport/AppcastVersion.swift` — pure version model + build-number derivation + ordering.
- `Tests/AppUpdateSupportTests/AppcastVersionTests.swift` — unit tests for the above.
- `App/Oncillascope/UpdaterController.swift` — Sparkle updater wrapper + "Check for Updates" menu command view.
- `.github/workflows/release.yml` — tag-triggered release pipeline.
- `scripts/make-appcast.sh` — CI helper: fetch existing appcast, run `generate_appcast`, render release notes.
- `RELEASING.md` — release runbook: secrets, tagging, key rotation, safe testing.

**Modified**
- `Package.swift` — add `AppUpdateSupport` target + product + test target.
- `App/Info.plist` — add `SUFeedURL`, `SUPublicEDKey`.
- `App/Oncillascope/OncillascopeApp.swift` — add updater `@StateObject` + menu command.
- `App/Oncillascope.xcodeproj/project.pbxproj` — Sparkle SwiftPM dependency on the app target (via Xcode UI).
- `README.md` — network-activity honesty fix, dependency note, "Updating" section.

---

## Task 1: `AppcastVersion` version model + build-number derivation (pure, unit-tested)

Establishes the one piece of logic worth unit-testing: parsing a semver tag, deriving the `CFBundleVersion` integer exactly as CI will, and ordering versions the way Sparkle does. Lives in a new pure SwiftPM target so `swift test` covers it with no app dependency.

**Files:**
- Create: `Sources/AppUpdateSupport/AppcastVersion.swift`
- Modify: `Package.swift` (add product, target, test target)
- Test: `Tests/AppUpdateSupportTests/AppcastVersionTests.swift`

**Interfaces:**
- Consumes: nothing (Foundation only).
- Produces:
  - `struct AppcastVersion: Equatable, Comparable` with `let major: Int`, `let minor: Int`, `let patch: Int`.
  - `init?(tag: String)` — parses `"v1.2.3"` or `"1.2.3"`; returns `nil` on malformed input.
  - `var shortVersionString: String` → `"1.2.3"`.
  - `var bundleVersion: Int` → `major*10000 + minor*100 + patch`.
  - `static func < (lhs:rhs:)` — orders by `bundleVersion`.

- [ ] **Step 1: Add the SwiftPM target, product, and test target to `Package.swift`**

In `Package.swift`, add to the `products` array (after the `WiFiCore` product line):

```swift
        .library(name: "AppUpdateSupport", targets: ["AppUpdateSupport"]),
```

Add to the `targets` array, immediately before the first `.testTarget(...)`:

```swift
        // Pure version model shared with the CI appcast pipeline; app-target only usage.
        .target(name: "AppUpdateSupport"),
```

Add to the `targets` array, alongside the other test targets:

```swift
        .testTarget(name: "AppUpdateSupportTests", dependencies: ["AppUpdateSupport"]),
```

- [ ] **Step 2: Write the failing test**

Create `Tests/AppUpdateSupportTests/AppcastVersionTests.swift`:

```swift
import XCTest
@testable import AppUpdateSupport

final class AppcastVersionTests: XCTestCase {
    func testParsesTagWithLeadingV() {
        let v = AppcastVersion(tag: "v1.2.3")
        XCTAssertEqual(v, AppcastVersion(major: 1, minor: 2, patch: 3))
    }

    func testParsesTagWithoutLeadingV() {
        XCTAssertEqual(AppcastVersion(tag: "1.0.0"),
                       AppcastVersion(major: 1, minor: 0, patch: 0))
    }

    func testRejectsMalformedTag() {
        XCTAssertNil(AppcastVersion(tag: "v1.2"))
        XCTAssertNil(AppcastVersion(tag: "1.2.3.4"))
        XCTAssertNil(AppcastVersion(tag: "vX.Y.Z"))
        XCTAssertNil(AppcastVersion(tag: ""))
    }

    func testShortVersionString() {
        XCTAssertEqual(AppcastVersion(major: 1, minor: 2, patch: 3).shortVersionString, "1.2.3")
    }

    func testBundleVersionDerivation() {
        XCTAssertEqual(AppcastVersion(major: 1, minor: 1, patch: 0).bundleVersion, 10100)
        XCTAssertEqual(AppcastVersion(major: 1, minor: 2, patch: 3).bundleVersion, 10203)
        XCTAssertEqual(AppcastVersion(major: 0, minor: 0, patch: 1).bundleVersion, 1)
    }

    func testOrderingMatchesBundleVersion() {
        XCTAssertLessThan(AppcastVersion(major: 1, minor: 0, patch: 9),
                          AppcastVersion(major: 1, minor: 1, patch: 0))
        XCTAssertLessThan(AppcastVersion(major: 1, minor: 2, patch: 3),
                          AppcastVersion(major: 2, minor: 0, patch: 0))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter AppUpdateSupportTests`
Expected: FAIL — `cannot find 'AppcastVersion' in scope` (no implementation yet).

- [ ] **Step 4: Write the minimal implementation**

Create `Sources/AppUpdateSupport/AppcastVersion.swift`:

```swift
import Foundation

/// Semantic version used by the release pipeline and the Sparkle appcast.
///
/// A git tag `vMAJOR.MINOR.PATCH` maps to a display string (`CFBundleShortVersionString`)
/// and a monotonic integer (`CFBundleVersion`) via `major*10000 + minor*100 + patch`.
/// Sparkle orders updates by `CFBundleVersion`, so `Comparable` mirrors that exactly.
public struct AppcastVersion: Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"v1.2.3"` or `"1.2.3"`. Returns `nil` on anything else.
    public init?(tag: String) {
        var s = tag
        if s.hasPrefix("v") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]),
              a >= 0, b >= 0, c >= 0 else { return nil }
        self.init(major: a, minor: b, patch: c)
    }

    public var shortVersionString: String { "\(major).\(minor).\(patch)" }

    public var bundleVersion: Int { major * 10000 + minor * 100 + patch }

    public static func < (lhs: AppcastVersion, rhs: AppcastVersion) -> Bool {
        lhs.bundleVersion < rhs.bundleVersion
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AppUpdateSupportTests`
Expected: PASS — all 6 tests green. Also confirm the full suite still builds: `swift build`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/AppUpdateSupport Tests/AppUpdateSupportTests
git commit -m "feat(update): AppcastVersion model + build-number derivation (unit-tested)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Generate EdDSA keypair and add Sparkle Info.plist keys

Produces the trust anchor for the appcast. The public key is committed in `Info.plist`; the private key is captured for the developer's Keychain and (later) the CI secret. This task has a manual key-generation step and a plist edit — no automated test, verified by inspection.

**Files:**
- Modify: `App/Info.plist`
- (Local artifact, not committed: the private key string for Keychain + `SPARKLE_ED_PRIVATE_KEY`.)

**Interfaces:**
- Consumes: nothing.
- Produces: `SUPublicEDKey` string value now present in `App/Info.plist`; `SUFeedURL` present. Both consumed by the running app (Task 4) and referenced by CI (Task 6).

- [ ] **Step 1: Obtain the Sparkle CLI tools and generate the keypair**

Sparkle's tools ship in its distribution. Fetch a release tarball (no repo integration needed yet):

```bash
cd "$(mktemp -d)"
curl -fsSL -o sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
tar -xf sparkle.tar.xz
./bin/generate_keys
```

Expected output includes:
- A line: `A key has been generated and saved in your keychain.` (this is the private key — it now lives in your login Keychain).
- A printed **public key**, e.g. `SUPublicEDKey: <base64…>` (Sparkle prints the exact `<key>/<string>` snippet to paste).

If a key already exists in the Keychain, `generate_keys` prints the existing public key instead of creating a new one — that is fine; use it.

- [ ] **Step 2: Export the private key for the CI secret (do NOT commit)**

```bash
./bin/generate_keys -x sparkle_private_key.txt
# Store the CONTENTS of sparkle_private_key.txt as GitHub secret SPARKLE_ED_PRIVATE_KEY (Task 6).
# Then remove it from disk:
rm -f sparkle_private_key.txt
```

Record the printed public key string; it goes into `Info.plist` next.

- [ ] **Step 3: Add Sparkle keys to `App/Info.plist`**

In `App/Info.plist`, inside the top-level `<dict>` (e.g. after the `NSLocationAlwaysAndWhenInUseUsageDescription` block, before `</dict>`), add:

```xml
    <key>SUFeedURL</key>
    <string>https://davidsoncollege.github.io/Oncillascope/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PASTE_THE_BASE64_PUBLIC_KEY_FROM_STEP_1</string>
```

Replace `PASTE_THE_BASE64_PUBLIC_KEY_FROM_STEP_1` with the actual base64 public key printed by `generate_keys`. Do **not** add `SUEnableAutomaticChecks` — omitting it makes Sparkle prompt the user on first launch.

- [ ] **Step 4: Verify the plist is well-formed**

Run: `plutil -lint App/Info.plist`
Expected: `App/Info.plist: OK`

Also confirm the key is present and non-placeholder:

Run: `/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" App/Info.plist`
Expected: the base64 key (NOT the literal `PASTE_...` placeholder).

- [ ] **Step 5: Commit**

```bash
git add App/Info.plist
git commit -m "feat(update): add Sparkle SUFeedURL + SUPublicEDKey to Info.plist

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Add Sparkle SwiftPM dependency to the app target

Wires the Sparkle framework into the Xcode app target (only). This is a `project.pbxproj` change best made through Xcode's package UI to get a correct diff. No unit test; verified by a build.

**Files:**
- Modify: `App/Oncillascope.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces: `import Sparkle` becomes available in the `Oncillascope` app target (used by Task 4).

- [ ] **Step 1: Add the package dependency in Xcode**

Open the project: `open App/Oncillascope.xcodeproj`

In Xcode: **File ▸ Add Package Dependencies…** → enter `https://github.com/sparkle-project/Sparkle` → Dependency Rule **Up to Next Major Version** from `2.6.4` → Add Package → add the **Sparkle** library product to the **Oncillascope** app target (not to any helper target).

- [ ] **Step 2: Verify the dependency resolves and the app still builds**

Run:
```bash
xcodebuild -scheme Oncillascope -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`. (An ad-hoc Debug build is fine here; signing is not exercised until CI.)

- [ ] **Step 3: Confirm Sparkle is referenced in the project file**

Run: `grep -c "sparkle-project/Sparkle" App/Oncillascope.xcodeproj/project.pbxproj`
Expected: a non-zero count (the package repository URL is recorded).

- [ ] **Step 4: Commit**

```bash
git add App/Oncillascope.xcodeproj/project.pbxproj App/Oncillascope.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null || git add App/Oncillascope.xcodeproj
git commit -m "build(update): add Sparkle 2.x SwiftPM dependency to app target

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Updater controller + "Check for Updates…" menu command

Adds the in-app Sparkle integration: an updater owned by the app, and a menu item gated on `canCheckForUpdates`, mirroring the existing `EmailExportCommandButton` focused-command pattern. Verified by build + a manual launch check.

**Files:**
- Create: `App/Oncillascope/UpdaterController.swift`
- Modify: `App/Oncillascope/OncillascopeApp.swift`

**Interfaces:**
- Consumes: `import Sparkle` (Task 3); Sparkle keys in `Info.plist` (Task 2).
- Produces:
  - `final class UpdaterController: ObservableObject` with `let updaterController: SPUStandardUpdaterController`, `@Published var canCheckForUpdates: Bool`, and `func checkForUpdates()`.
  - `struct CheckForUpdatesCommand: View` rendering the menu button.

- [ ] **Step 1: Create `UpdaterController.swift`**

Create `App/Oncillascope/UpdaterController.swift`:

```swift
import SwiftUI
import Sparkle

/// Owns the Sparkle updater for the app. Notify-and-prompt only: `startingUpdater: true`
/// lets Sparkle schedule background checks, but with no `SUEnableAutomaticChecks` in
/// Info.plist Sparkle asks the user for permission on first launch before any network call.
final class UpdaterController: ObservableObject {
    let updaterController: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

/// Menu command that mirrors the existing focused-command pattern (EmailExportCommandButton):
/// a titled button disabled while the updater is mid-check.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterController
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
```

- [ ] **Step 2: Wire it into `OncillascopeApp.swift`**

In `App/Oncillascope/OncillascopeApp.swift`, add a `@StateObject` alongside the existing ones (after the `annotations` line at `App/Oncillascope/OncillascopeApp.swift:45`):

```swift
    @StateObject private var updater = UpdaterController()
```

Then add a new command group inside `.commands { … }` (after the existing `CommandGroup(after: .newItem) { … }` block closes, before `.commands`'s closing brace):

```swift
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild -scheme Oncillascope -configuration Debug -derivedDataPath build build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual launch check**

Run the built app:
```bash
open build/Build/Products/Debug/Oncillascope.app
```
Expected: the app launches; the application menu (or the menu bar item after `.appInfo`) shows **"Check for Updates…"** and it is clickable. Choosing it shows Sparkle's "You're up to date" / permission dialog (the feed 404s until CI publishes one — that is expected pre-release; Sparkle reports it cannot check, which is acceptable here).

- [ ] **Step 5: Commit**

```bash
git add App/Oncillascope/UpdaterController.swift App/Oncillascope/OncillascopeApp.swift
git commit -m "feat(update): Sparkle updater controller + Check for Updates menu command

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Appcast generation helper script

A standalone script the CI calls: it fetches the current appcast from `gh-pages` (so history is preserved), runs Sparkle's `generate_appcast` against the new zip with the GitHub-Release download-URL prefix, and renders the release-notes HTML. Kept as a committed script so it is reviewable and locally runnable. Verified by a `bash -n` syntax check and a documented dry-run.

**Files:**
- Create: `scripts/make-appcast.sh`

**Interfaces:**
- Consumes: env `VERSION` (e.g. `1.1.0`), `TAG` (e.g. `v1.1.0`), `ZIP_PATH`, `RELEASE_NOTES_MD`, `SPARKLE_BIN` (dir with `generate_appcast`), `DOWNLOAD_URL_PREFIX`, `PAGES_DIR` (checked-out `gh-pages` working dir).
- Produces: writes/updates `$PAGES_DIR/appcast.xml` and `$PAGES_DIR/release-notes/<version>.html`.

- [ ] **Step 1: Create `scripts/make-appcast.sh`**

Create `scripts/make-appcast.sh`:

```bash
#!/usr/bin/env bash
# Regenerate the Sparkle appcast for a new release, preserving prior entries.
#
# Required env:
#   VERSION              e.g. 1.1.0  (CFBundleShortVersionString)
#   TAG                  e.g. v1.1.0 (git tag)
#   ZIP_PATH             path to the notarized+stapled Oncillascope-<version>.zip
#   RELEASE_NOTES_MD     path to a Markdown file with this release's notes
#   SPARKLE_BIN          directory containing generate_appcast
#   DOWNLOAD_URL_PREFIX  e.g. https://github.com/DavidsonCollege/Oncillascope/releases/download/v1.1.0/
#   PAGES_DIR            checked-out gh-pages working tree (output dir)
set -euo pipefail

: "${VERSION:?}"; : "${TAG:?}"; : "${ZIP_PATH:?}"; : "${RELEASE_NOTES_MD:?}"
: "${SPARKLE_BIN:?}"; : "${DOWNLOAD_URL_PREFIX:?}"; : "${PAGES_DIR:?}"

work="$(mktemp -d)"
# generate_appcast scans a directory of archives and MERGES into an existing
# appcast.xml if one is already present in that directory — so seed it with the
# current published feed to retain historical <item>s.
cp "$ZIP_PATH" "$work/"
if [ -f "$PAGES_DIR/appcast.xml" ]; then
  cp "$PAGES_DIR/appcast.xml" "$work/appcast.xml"
fi

# Render release notes Markdown -> HTML (GitHub CLI ships no renderer; use a
# minimal wrapper: <pre> is acceptable and safe. Prefer `cmark` if available).
mkdir -p "$PAGES_DIR/release-notes"
notes_html="$PAGES_DIR/release-notes/${VERSION}.html"
if command -v cmark >/dev/null 2>&1; then
  { echo '<!doctype html><meta charset="utf-8"><body>'; cmark "$RELEASE_NOTES_MD"; echo '</body>'; } > "$notes_html"
else
  { echo '<!doctype html><meta charset="utf-8"><body><pre>'; \
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$RELEASE_NOTES_MD"; \
    echo '</pre></body>'; } > "$notes_html"
fi

# Sparkle reads the EdDSA private key from the Keychain (CI imports it first) and
# signs each enclosure. --download-url-prefix makes enclosure URLs point at the
# GitHub Release asset. --link sets the release-notes URL base is handled per-item
# by generate_appcast when a matching <version>.html sits alongside; we set the
# feed's own URLs via the prefix and post-process the release notes link.
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "https://github.com/DavidsonCollege/Oncillascope/releases" \
  "$work"

cp "$work/appcast.xml" "$PAGES_DIR/appcast.xml"
echo "Wrote $PAGES_DIR/appcast.xml and $notes_html"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/make-appcast.sh
```

- [ ] **Step 3: Syntax-check the script**

Run: `bash -n scripts/make-appcast.sh && echo OK`
Expected: `OK` (no syntax errors).

- [ ] **Step 4: Verify required-env guard fires**

Run: `bash scripts/make-appcast.sh; echo "exit=$?"`
Expected: fails fast with a message like `VERSION: parameter null or not set` and a non-zero `exit=` (the `: "${VAR:?}"` guards). This confirms the guards work without needing Sparkle installed.

- [ ] **Step 5: Commit**

```bash
git add scripts/make-appcast.sh
git commit -m "feat(update): appcast generation helper script for CI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: GitHub Actions release pipeline

The tag-triggered workflow that builds, signs, notarizes, packages, EdDSA-signs the appcast, and publishes both a GitHub Release and the updated Pages feed. Verified by YAML lint + a documented throwaway-tag dry run (executed in Task 8, not here).

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: repo secrets (Global Constraints); `scripts/make-appcast.sh` (Task 5); `AppcastVersion` scheme (for `CFBundleVersion` derivation, replicated in shell).
- Produces: a GitHub Release with `Oncillascope-<version>.zip`; updated `appcast.xml` + release notes on `gh-pages`.

- [ ] **Step 1: Create `.github/workflows/release.yml`**

Create `.github/workflows/release.yml`:

```yaml
name: Release
on:
  push:
    tags:
      - "v*.*.*"

permissions:
  contents: write   # create releases, push to gh-pages

jobs:
  release:
    runs-on: macos-14
    env:
      TEAM_ID: "4Z539UE4TT"
      FEED_APP_NAME: "Oncillascope"
      SPARKLE_VERSION: "2.6.4"
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 16+
        run: sudo xcode-select -s /Applications/Xcode_16.app || xcodebuild -version

      - name: Derive version numbers from tag
        id: ver
        run: |
          TAG="${GITHUB_REF_NAME}"           # e.g. v1.2.3
          SHORT="${TAG#v}"                    # 1.2.3
          IFS='.' read -r MAJ MIN PAT <<< "$SHORT"
          if [ "$MIN" -ge 100 ] || [ "$PAT" -ge 100 ]; then
            echo "MINOR/PATCH must be < 100 for the CFBundleVersion scheme" >&2; exit 1
          fi
          BUILD=$(( MAJ*10000 + MIN*100 + PAT ))
          echo "tag=$TAG"        >> "$GITHUB_OUTPUT"
          echo "short=$SHORT"    >> "$GITHUB_OUTPUT"
          echo "build=$BUILD"    >> "$GITHUB_OUTPUT"

      - name: Import Developer ID signing cert
        env:
          DEVELOPER_ID_P12: ${{ secrets.DEVELOPER_ID_P12 }}
          DEVELOPER_ID_P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/build.keychain"
          KPW="$(uuidgen)"
          security create-keychain -p "$KPW" "$KEYCHAIN"
          security set-keychain-settings -lut 21600 "$KEYCHAIN"
          security unlock-keychain -p "$KPW" "$KEYCHAIN"
          echo "$DEVELOPER_ID_P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" \
            -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
          # WWDR G3 intermediate (see SIGNING.md gotcha)
          curl -fsSL -o "$RUNNER_TEMP/wwdr.cer" https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
          security import "$RUNNER_TEMP/wwdr.cer" -k "$KEYCHAIN" || true
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KPW" "$KEYCHAIN"
          rm -f "$RUNNER_TEMP/cert.p12"
          echo "BUILD_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
          # Sparkle EdDSA private key -> Keychain (generate_appcast reads it there)
          echo "$SPARKLE_ED_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle_key.txt"

      - name: Fetch Sparkle tools
        run: |
          cd "$RUNNER_TEMP"
          curl -fsSL -o sparkle.tar.xz \
            "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
          tar -xf sparkle.tar.xz
          echo "SPARKLE_BIN=$RUNNER_TEMP/bin" >> "$GITHUB_ENV"
          # Import the EdDSA private key into the login/build keychain for signing.
          "$RUNNER_TEMP/bin/generate_keys" -f "$RUNNER_TEMP/sparkle_key.txt" || true
          rm -f "$RUNNER_TEMP/sparkle_key.txt"

      - name: Build (Release, universal, hardened runtime)
        run: |
          xcodebuild -scheme Oncillascope -configuration Release -derivedDataPath build \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM="$TEAM_ID" \
            PROVISIONING_PROFILE_SPECIFIER="" \
            OTHER_CODE_SIGN_FLAGS="--timestamp" \
            CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
            MARKETING_VERSION="${{ steps.ver.outputs.short }}" \
            CURRENT_PROJECT_VERSION="${{ steps.ver.outputs.build }}" \
            build

      - name: Notarize + staple
        env:
          AC_APPLE_ID: ${{ secrets.AC_APPLE_ID }}
          AC_TEAM_ID: ${{ secrets.AC_TEAM_ID }}
          AC_APP_PASSWORD: ${{ secrets.AC_APP_PASSWORD }}
        run: |
          APP="build/Build/Products/Release/Oncillascope.app"
          ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/notarize.zip"
          xcrun notarytool submit "$RUNNER_TEMP/notarize.zip" \
            --apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_APP_PASSWORD" --wait
          xcrun stapler staple "$APP"
          xcrun stapler validate "$APP"

      - name: Package distribution zip
        id: pkg
        run: |
          APP="build/Build/Products/Release/Oncillascope.app"
          ZIP="Oncillascope-${{ steps.ver.outputs.short }}.zip"
          ditto -c -k --keepParent "$APP" "$ZIP"
          echo "zip=$ZIP" >> "$GITHUB_OUTPUT"

      - name: Extract release notes
        id: notes
        run: |
          NOTES="$RUNNER_TEMP/notes.md"
          # Use the annotated tag message if present, else a default line.
          git tag -l --format='%(contents)' "${GITHUB_REF_NAME}" > "$NOTES"
          [ -s "$NOTES" ] || echo "Oncillascope ${{ steps.ver.outputs.short }}" > "$NOTES"
          echo "path=$NOTES" >> "$GITHUB_OUTPUT"

      - name: Create GitHub Release with asset
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "${GITHUB_REF_NAME}" "${{ steps.pkg.outputs.zip }}" \
            --title "Oncillascope ${{ steps.ver.outputs.short }}" \
            --notes-file "${{ steps.notes.outputs.path }}"

      - name: Check out gh-pages worktree
        run: |
          git fetch origin gh-pages || true
          git worktree add "$RUNNER_TEMP/pages" gh-pages 2>/dev/null \
            || { git worktree add --orphan -b gh-pages "$RUNNER_TEMP/pages"; }

      - name: Regenerate appcast
        run: |
          VERSION="${{ steps.ver.outputs.short }}" \
          TAG="${GITHUB_REF_NAME}" \
          ZIP_PATH="${{ steps.pkg.outputs.zip }}" \
          RELEASE_NOTES_MD="${{ steps.notes.outputs.path }}" \
          SPARKLE_BIN="$SPARKLE_BIN" \
          DOWNLOAD_URL_PREFIX="https://github.com/DavidsonCollege/Oncillascope/releases/download/${GITHUB_REF_NAME}/" \
          PAGES_DIR="$RUNNER_TEMP/pages" \
          bash scripts/make-appcast.sh

      - name: Publish appcast to gh-pages
        run: |
          cd "$RUNNER_TEMP/pages"
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add appcast.xml release-notes
          git commit -m "release: appcast for ${GITHUB_REF_NAME}" || echo "no changes"
          git push origin gh-pages
```

- [ ] **Step 2: Lint the workflow YAML**

Run:
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 3: Sanity-check the build-number math in isolation**

Run:
```bash
for t in v1.1.0 v1.2.3 v0.0.1; do
  s="${t#v}"; IFS='.' read -r a b c <<< "$s"; echo "$t -> $((a*10000+b*100+c))"
done
```
Expected:
```
v1.1.0 -> 10100
v1.2.3 -> 10203
v0.0.1 -> 1
```
(Matches `AppcastVersion.bundleVersion` from Task 1.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(update): tag-triggered build/notarize/appcast release pipeline

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Docs — README honesty fix + RELEASING runbook

Corrects the README's "no network calls" claim (integrity requirement) and adds a release runbook. Verified by inspection and a link/anchor check.

**Files:**
- Modify: `README.md`
- Create: `RELEASING.md`

**Interfaces:**
- Consumes: nothing.
- Produces: user-facing docs; no code contract.

- [ ] **Step 1: Fix the network-activity claim in `README.md`**

In `README.md`, replace the line (currently at `README.md:98-99`):

```
No third-party runtime dependencies. No telemetry, no network calls (OUI lookups are
fully local).
```

with:

```
No third-party runtime dependencies in the core (`WiFiAnalyzerKit`); the app shell bundles
**Sparkle** solely for updates. No telemetry. OUI lookups are fully local. The only network
activity is the **optional** Sparkle update check against GitHub Releases, which you opt into
on first launch and can disable anytime in the update dialog.
```

- [ ] **Step 2: Add an "Updating" section to `README.md`**

In `README.md`, add immediately before the `## License` section:

```markdown
## Updating

Oncillascope updates itself via [Sparkle](https://sparkle-project.org). On first launch it
asks whether to check for updates automatically. When a newer signed release is available it
shows the release notes and an **Install & Relaunch** button — updates are never installed
silently. You can also trigger a check anytime from **Oncillascope ▸ Check for Updates…**.

Every update is protected by two independent signatures: the app's Developer ID + Apple
notarization (checked by macOS), and an EdDSA signature on the appcast (checked by Sparkle),
so a compromised feed host cannot ship a tampered build. Releases and the update feed are
produced automatically by the CI pipeline described in [`RELEASING.md`](RELEASING.md).
```

- [ ] **Step 3: Create `RELEASING.md`**

Create `RELEASING.md`:

```markdown
# Releasing Oncillascope

Releases are fully automated by `.github/workflows/release.yml`. Cutting a release is:

```bash
git tag v1.1.0      # vMAJOR.MINOR.PATCH — MINOR and PATCH must be < 100
git push origin v1.1.0
```

On the tag push, CI builds the universal Release app, signs it with Developer ID,
notarizes + staples it, packages `Oncillascope-<version>.zip`, EdDSA-signs the appcast,
creates the GitHub Release with the zip attached, and publishes the updated
`appcast.xml` (+ release notes) to the `gh-pages` branch, which GitHub Pages serves at
`https://davidsoncollege.github.io/Oncillascope/appcast.xml`.

Release notes come from the **annotated tag message**, so tag with:

```bash
git tag -a v1.1.0 -m "What changed in this release…"
```

## Version scheme

- `CFBundleShortVersionString` = the tag without `v` (e.g. `1.1.0`).
- `CFBundleVersion` = `MAJOR*10000 + MINOR*100 + PATCH` (e.g. `1.1.0` → `10100`).
  Sparkle orders updates by this integer. Keep MINOR/PATCH < 100; if the cadence ever
  exceeds that, widen the multipliers in both `release.yml` and `AppcastVersion.swift`.

## One-time setup

### GitHub Pages
Repo **Settings ▸ Pages** → Source = `gh-pages` branch, root. The first successful
release run seeds `appcast.xml`.

### Required repository secrets

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12` | base64 of the Developer ID Application `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_P12_PASSWORD` | the `.p12` export password |
| `AC_APPLE_ID` | Apple ID for notarization (`jdmills@davidson.edu`) |
| `AC_TEAM_ID` | `4Z539UE4TT` |
| `AC_APP_PASSWORD` | app-specific password from appleid.apple.com |
| `SPARKLE_ED_PRIVATE_KEY` | the EdDSA private key printed by `generate_keys -x` |

## EdDSA key rotation

The appcast signing key is independent of the Apple cert. To rotate:

1. Run Sparkle's `generate_keys` to create a new keypair (old one stays in the Keychain).
2. Ship an app update whose `Info.plist` carries the **new** `SUPublicEDKey`, still signed
   with the **old** private key so current users accept it.
3. After that update is widely adopted, update `SPARKLE_ED_PRIVATE_KEY` to the new key for
   subsequent releases. Clients that updated in step 2 trust the new key; older clients keep
   trusting the old key until they update.

## Testing the pipeline safely

Push a throwaway pre-release tag (e.g. `v0.0.1`) first and confirm the whole chain runs
green and the feed appears on Pages before cutting a real release. See the manual E2E
checklist in the auto-update design spec.
```

- [ ] **Step 4: Verify docs render and links resolve**

Run:
```bash
grep -q "Check for Updates" README.md && grep -q "opt into" README.md && test -f RELEASING.md && grep -q "SPARKLE_ED_PRIVATE_KEY" RELEASING.md && echo "DOCS OK"
```
Expected: `DOCS OK`.

- [ ] **Step 5: Commit**

```bash
git add README.md RELEASING.md
git commit -m "docs(update): correct network-activity claim + add RELEASING runbook

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: End-to-end verification (baseline release + update + tamper rejection)

Exercises the full system for real: seed a baseline release through CI, then confirm a lower-versioned local build detects, verifies, and installs it, and that a tampered feed is rejected. This is a manual, documented task — no code, but it is the acceptance gate.

**Files:** none (verification only).

**Interfaces:**
- Consumes: everything from Tasks 1–7; the six repo secrets configured; Pages enabled.

- [ ] **Step 1: Configure secrets and Pages (one-time)**

Set all six secrets from the `RELEASING.md` table under repo **Settings ▸ Secrets and variables ▸ Actions**. Enable **Settings ▸ Pages** with source `gh-pages` (the branch will be created by the first run).

- [ ] **Step 2: Cut a baseline pre-release**

```bash
git tag -a v0.0.1 -m "Baseline release to seed the appcast."
git push origin v0.0.1
```
Watch the run: `gh run watch` (or the Actions tab).
Expected: the `Release` workflow finishes green; a `v0.0.1` GitHub Release exists with `Oncillascope-0.0.1.zip`; `gh-pages` now has `appcast.xml`.

- [ ] **Step 3: Confirm the feed is live and signed**

Run:
```bash
curl -fsSL https://davidsoncollege.github.io/Oncillascope/appcast.xml | grep -E "sparkle:(version|edSignature)|enclosure"
```
Expected: an `<enclosure>` with `sparkle:version="1"` (0.0.1 → build 1), a non-empty `sparkle:edSignature`, and a `url` pointing at the `v0.0.1` release asset.

- [ ] **Step 4: Verify update detection from an older build**

Publish a second release `v0.0.2` (repeat Step 2 with a small real change and a new tag). Then keep the **0.0.1** app from the first release's artifact and launch it — it is now older than the feed's newest entry:
```bash
# Download the v0.0.1 asset, unzip, and launch that older build:
open Oncillascope.app     # the 0.0.1 build
```
Then choose **Oncillascope ▸ Check for Updates…**.
Expected: Sparkle detects `0.0.2`, shows the release notes from the tag message, downloads, **verifies the EdDSA signature**, installs, and relaunches into `0.0.2` (confirm via **About Oncillascope**).

- [ ] **Step 5: Negative test — tamper rejection**

On a scratch copy of the feed, flip a byte in the hosted zip's recorded length or point the enclosure at a mismatched file, or (simplest) temporarily set `SUPublicEDKey` in a local build to a different valid key and check for updates.
Expected: Sparkle **refuses** to install, reporting a signature/verification failure. Restore the correct key afterward.

- [ ] **Step 6: Record results**

Append a short "Verified <date>" note to `RELEASING.md` under a new `## Verification log` heading documenting that Steps 2–5 passed (mirrors the project's manual-E2E-verified convention). Commit:

```bash
git add RELEASING.md
git commit -m "docs(update): record E2E verification of the release + update flow

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes for the implementer

- **Do Tasks 1–7 in order**; Task 8 requires repo secrets + push access and is the acceptance gate. Tasks 2 and 3 involve manual GUI/CLI steps (key generation, Xcode package add) that cannot be fully scripted.
- **Sparkle version `2.6.4`** is pinned throughout; if you bump it, change it in Task 2, Task 3, and `release.yml` (`SPARKLE_VERSION`) together.
- **`generate_appcast` release-notes linking:** the script writes `release-notes/<version>.html`; if Sparkle's `generate_appcast` version in use does not auto-link them, add a `<sparkle:releaseNotesLink>` post-processing step. This is the one area to verify against the actual tool output during Task 6's dry run in Task 8.
- **Runner Xcode:** `Xcode_16.app` is assumed present on `macos-14`; adjust the `xcode-select` path to the newest available if the build fails on toolchain version.
