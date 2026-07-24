#!/usr/bin/env bash
#
# Packages SKP E-Plumb into an installable SketchUp .rbz (a plain zip whose
# root holds the registration file `skp_e_plumb.rb` next to the `skp_e_plumb`
# code folder). Output goes to dist/.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(ruby -e 'v=File.read("skp_e_plumb/version.rb")[/VERSION\s*=\s*.(\d+\.\d+\.\d+)/,1]; print(v||"1.0.0")')"

DIST="$ROOT/dist"
mkdir -p "$DIST"

# A single artifact. The version lives in the Release tag, so the file name
# stays stable ("download SKP-E-Plumb.rbz from the latest release").
RBZ="$DIST/SKP-E-Plumb.rbz"
rm -f "$DIST"/*.rbz

# Ship the changelog inside the plugin so it can show "What's new" after an
# update (gitignored copy; the source of truth is the root CHANGELOG.md).
cp -f "$ROOT/CHANGELOG.md" "$ROOT/skp_e_plumb/CHANGELOG.md"

# Only ship the plugin payload — never tools/, .git, dist, docs, tests.
zip -r -X "$RBZ" \
    skp_e_plumb.rb \
    skp_e_plumb \
    -x '*.DS_Store' -x '__MACOSX*' -x '*/.git*' >/dev/null

echo "Built $RBZ (v${VERSION})"
echo
echo "Contents:"
unzip -l "$RBZ"
