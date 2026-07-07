#!/usr/bin/env bash
# Regenerate the Sparkle appcast for a new release, preserving prior entries.
#
# Required env:
#   VERSION              e.g. 1.1.0  (CFBundleShortVersionString)
#   ZIP_PATH             path to the notarized+stapled Oncillascope-<version>.zip
#   RELEASE_NOTES_MD     path to a Markdown file with this release's notes
#   SPARKLE_BIN          directory containing generate_appcast
#   DOWNLOAD_URL_PREFIX  e.g. https://github.com/DavidsonCollege/Oncillascope/releases/download/v1.1.0/
#   PAGES_DIR            checked-out gh-pages working tree (output dir)
#
# Optional env:
#   ED_KEY_FILE          path to the private EdDSA key file. If set, it is passed
#                        to generate_appcast via --ed-key-file (robust for CI);
#                        if unset, generate_appcast falls back to the Keychain
#                        (convenient for local runs where the key is installed).
set -euo pipefail

: "${VERSION:?}"; : "${ZIP_PATH:?}"; : "${RELEASE_NOTES_MD:?}"
: "${SPARKLE_BIN:?}"; : "${DOWNLOAD_URL_PREFIX:?}"; : "${PAGES_DIR:?}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
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

# generate_appcast signs each enclosure with the EdDSA private key and writes the
# merged appcast. The key comes from --ed-key-file when ED_KEY_FILE is set (CI),
# otherwise from the Keychain (local). --download-url-prefix makes enclosure URLs
# point at the GitHub Release asset; --link sets the feed's channel link.
# (Per-item release-notes linking is verified during the release E2E, not here.)
gen_args=(--download-url-prefix "$DOWNLOAD_URL_PREFIX"
          --link "https://github.com/DavidsonCollege/Oncillascope/releases")
if [ -n "${ED_KEY_FILE:-}" ]; then
  gen_args=(--ed-key-file "$ED_KEY_FILE" "${gen_args[@]}")
fi
"$SPARKLE_BIN/generate_appcast" "${gen_args[@]}" "$work"

# Safety: never publish a feed that lost history. generate_appcast should
# merge, not shrink — if item count dropped, something went wrong; abort.
new_items="$(grep -c '<item>' "$work/appcast.xml" 2>/dev/null || true)"
if [ -f "$PAGES_DIR/appcast.xml" ]; then
  old_items="$(grep -c '<item>' "$PAGES_DIR/appcast.xml" 2>/dev/null || true)"
else
  old_items=0
fi
if [ ! -s "$work/appcast.xml" ] || [ "${new_items:-0}" -lt "${old_items:-0}" ]; then
  echo "Refusing to publish: generated appcast has ${new_items:-0} item(s), fewer than the existing ${old_items:-0}." >&2
  exit 1
fi

cp "$work/appcast.xml" "$PAGES_DIR/appcast.xml"
echo "Wrote $PAGES_DIR/appcast.xml and $notes_html"
