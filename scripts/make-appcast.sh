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
