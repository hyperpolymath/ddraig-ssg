#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Golden tests: compare ddraig's output, byte for byte, with the expected
# output committed under tests/golden/.
#
#   sh tests/golden.sh [--update] [DDRAIG]
#
# DDRAIG defaults to ./build/exec/ddraig (build it with: idris2 Ddraig.idr -o ddraig).
# Run from the repository root.
#
# Compared:
#   tests/golden/cli/<subcommand>.out  stdout of each test-* subcommand
#   tests/golden/examples/             the site built from examples/
#
# --update rewrites the expected files from the current output instead of
# comparing. Any change to them is a change to ddraig's output: review it with
# `git diff -- tests/golden` and commit it with the change that caused it.
#
# The build date is pinned with SOURCE_DATE_EPOCH (2026-06-22, the example
# pages' date), so the attestation's "generated" field and the feed's no-date
# fallback do not depend on the day the tests run.

set -eu

update=false
if [ "${1:-}" = --update ]; then
  update=true
  shift
fi
ddraig=${1:-./build/exec/ddraig}
golden=tests/golden
base_url=https://hyperpolymath.github.io/ddraig-ssg
SOURCE_DATE_EPOCH=1782086400
export SOURCE_DATE_EPOCH

[ -f Ddraig.idr ] && [ -d "$golden" ] \
  || { echo "golden: run from the repository root" >&2; exit 2; }
[ -x "$ddraig" ] \
  || { echo "golden: $ddraig not found; build it with: idris2 Ddraig.idr -o ddraig" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- Produce the actual output -------------------------------------------------
mkdir -p "$work/cli"
for t in test-markdown test-frontmatter test-full test-state test-attest; do
  "$ddraig" "$t" > "$work/cli/$t.out" \
    || { cat "$work/cli/$t.out"; echo "golden: FAIL: $t exited non-zero" >&2; exit 1; }
done
"$ddraig" build examples "$work/examples" "$base_url" > "$work/build.log" 2>&1 \
  || { cat "$work/build.log"; echo "golden: FAIL: building examples/ failed" >&2; exit 1; }

# --- Update, or compare ------------------------------------------------------------
if $update; then
  rm -rf "$golden/cli" "$golden/examples"
  cp -R "$work/cli" "$work/examples" "$golden/"
  echo "golden: rewrote $golden/cli and $golden/examples"
  echo "golden: review with: git status -- $golden && git diff -- $golden"
  exit 0
fi

status=0
for d in cli examples; do
  if ! diff -r -u "$golden/$d" "$work/$d"; then
    status=1
  fi
done
if [ "$status" -ne 0 ]; then
  echo "golden: FAIL: output differs from $golden (diff above)." >&2
  echo "golden: if the change is intended, run: sh tests/golden.sh --update" >&2
  exit 1
fi
echo "golden: ok ($(find "$golden/cli" "$golden/examples" -type f | wc -l) files match)"
