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
#   tests/golden/sites/<name>/         sites built from tests/fixtures/, e.g. the
#                                      configuration precedence fixture
#   tests/golden/errors/<case>.*       what a user sees when something is wrong:
#                                      .stdout, .stderr and .status (exit code)
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
for t in test-markdown test-frontmatter test-full test-state test-attest test-diagnostics; do
  "$ddraig" "$t" > "$work/cli/$t.out" \
    || { cat "$work/cli/$t.out"; echo "golden: FAIL: $t exited non-zero" >&2; exit 1; }
done
"$ddraig" build examples "$work/examples" "$base_url" > "$work/build.log" 2>&1 \
  || { cat "$work/build.log"; echo "golden: FAIL: building examples/ failed" >&2; exit 1; }

# --- Errors: what a user sees when something is wrong --------------------------------
# Each case runs from a scratch directory, so the paths in the messages are
# relative and the same on every machine. stdout, stderr and the exit status
# are recorded separately: problems go to stderr, progress to stdout.
ddraig_abs=$(cd "$(dirname "$ddraig")" && pwd)/$(basename "$ddraig")
mkdir -p "$work/errors" "$work/run" "$work/sites"
cp -R examples "$work/run/examples"
cp -R tests/fixtures "$work/run/fixtures"
printf '# Not a directory\n' > "$work/run/page.md"

# --- Sites built from fixtures -------------------------------------------------
# build_site NAME SRC [BASE-URL]: build a fixture; it must succeed.
build_site() {
  name=$1
  shift
  (cd "$work/run" && "$ddraig_abs" build "$1" "$work/sites/$name" ${2:+"$2"}) \
    > "$work/sites-$name.log" 2>&1 \
    || { cat "$work/sites-$name.log"; echo "golden: FAIL: building $1 failed" >&2; exit 1; }
}
# base URL from ddraig.toml, then the command line's overriding it
build_site config          fixtures/config
build_site config-cli-base fixtures/config https://cli.example
build_site braces          fixtures/braces

# run_case NAME COMMAND...: run COMMAND in the scratch directory and record it.
run_case() {
  name=$1
  shift
  set +e
  (cd "$work/run" && "$@") > "$work/errors/$name.stdout" 2> "$work/errors/$name.stderr"
  echo "$?" > "$work/errors/$name.status"
  set -e
}
D=$ddraig_abs
run_case unknown-command  "$D" biuld examples out
run_case wrong-arguments  "$D" build examples
run_case missing-source   "$D" build no-such-dir out
run_case source-is-file   "$D" build page.md out
run_case bad-epoch        env SOURCE_DATE_EPOCH=12abc "$D" build examples out
run_case two-problems     env SOURCE_DATE_EPOCH=-1 "$D" build no-such-dir out
run_case explain-list     "$D" explain
run_case explain-one      "$D" explain ddr0002
run_case explain-unknown  "$D" explain DDR002
run_case config-broken          "$D" build fixtures/config-broken out
run_case validate-config-broken "$D" validate-config fixtures/config-broken/ddraig.toml
run_case validate-config-ok     "$D" validate-config fixtures/config/ddraig.toml
run_case validate-config-missing "$D" validate-config no-such.toml
run_case validate-config-nickel  "$D" validate-config fixtures/config-nickel/ddraig.toml
run_case toml-lists              "$D" validate-config fixtures/toml-lists/ddraig.toml
run_case template-vars          "$D" build fixtures/template-vars out
run_case data-broken            "$D" build fixtures/data-broken out
run_case images-missing-alt     "$D" build fixtures/images out

# --- Update, or compare ------------------------------------------------------------
if $update; then
  rm -rf "$golden/cli" "$golden/examples" "$golden/sites" "$golden/errors"
  cp -R "$work/cli" "$work/examples" "$work/sites" "$work/errors" "$golden/"
  echo "golden: rewrote $golden/cli, examples, sites and errors"
  echo "golden: review with: git status -- $golden && git diff -- $golden"
  exit 0
fi

status=0
for d in cli examples sites errors; do
  if ! diff -r -u "$golden/$d" "$work/$d"; then
    status=1
  fi
done
if [ "$status" -ne 0 ]; then
  echo "golden: FAIL: output differs from $golden (diff above)." >&2
  echo "golden: if the change is intended, run: sh tests/golden.sh --update" >&2
  exit 1
fi
echo "golden: ok ($(find "$golden/cli" "$golden/examples" "$golden/sites" "$golden/errors" -type f | wc -l) files match)"
