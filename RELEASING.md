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

The appcast signing key is independent of the Apple cert. CI never imports it into a
keychain: the `SPARKLE_ED_PRIVATE_KEY` secret is written to an ephemeral file at build time
and passed straight to `generate_appcast` via `--ed-key-file`. To rotate:

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

### Assertions to confirm on the first release

After the first pipeline run, fetch the published feed and confirm:

```bash
curl -fsSL https://davidsoncollege.github.io/Oncillascope/appcast.xml | \
  grep -E 'sparkle:(version|shortVersionString|edSignature|minimumSystemVersion)|<enclosure|releaseNotesLink'
```

- `sparkle:edSignature` is present and non-empty on the enclosure (EdDSA signing worked).
- `sparkle:minimumSystemVersion` is `14.0` (generate_appcast derives this from the app's `LSMinimumSystemVersion`; if it is missing, the deployment target or bundle plist is wrong).
- `sparkle:releaseNotesLink` resolves to the published `release-notes/<version>.html` on Pages (open the URL). If the link is absent or wrong, the release-notes HTML is orphaned — wire `generate_appcast --release-notes-url-prefix https://davidsoncollege.github.io/Oncillascope/release-notes/` in `scripts/make-appcast.sh`.
