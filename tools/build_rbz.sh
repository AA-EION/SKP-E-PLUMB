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

STABLE="$DIST/SKP-E-Plumb.rbz"
VERSIONED="$DIST/SKP-E-Plumb-v${VERSION}.rbz"

rm -f "$STABLE" "$VERSIONED"

# Only ship the plugin payload — never tools/, .git, dist, docs, tests.
zip -r -X "$STABLE" \
    skp_e_plumb.rb \
    skp_e_plumb \
    -x '*.DS_Store' -x '__MACOSX*' -x '*/.git*' >/dev/null

cp "$STABLE" "$VERSIONED"

echo "Built:"
echo "  $STABLE"
echo "  $VERSIONED"
echo
echo "Contents:"
unzip -l "$STABLE"
