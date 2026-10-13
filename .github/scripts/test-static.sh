#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Check the static release binary (RefC backend) against the reference binary
# (Chez backend, the one CI tests). They must behave identically:
#
#   1. every CI test subcommand passes and prints exactly what the reference prints;
#   2. validate-state accepts this repo's STATE descriptile;
#   3. building examples/ and a fixture site gives byte-identical output trees;
#   4. a large page builds without crashing (C stack depth; see RELEASING.adoc)
#      and also matches the reference.
#
# usage: test-static.sh STATIC_BINARY REFERENCE_BINARY
#
# DRAFT: not yet run. See RELEASING.adoc.
#
# Run from the repository root. The fixture site written below adds what
# examples/ lacks: a nested page, a draft, and more Markdown constructs.
#
# Known false alarm: the attestation file records the build day, so if the two
# builds straddle 00:00 UTC their output trees differ. Re-run.

set -eu

[ $# -eq 2 ] || { echo "usage: $0 STATIC_BINARY REFERENCE_BINARY" >&2; exit 2; }
static=$1
ref=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'test-static: FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'test-static: ok: %s\n' "$*"; }

# same_output NAME CMD...: run CMD with each binary; both must succeed and
# print the same bytes.
same_output() {
  name=$1
  shift
  "$static" "$@" > "$work/$name.static" 2>&1 || fail "$name: static binary exited non-zero"
  "$ref" "$@" > "$work/$name.ref" 2>&1 || fail "$name: reference binary exited non-zero"
  if ! cmp -s "$work/$name.ref" "$work/$name.static"; then
    diff -u "$work/$name.ref" "$work/$name.static" | head -n 60
    fail "$name: output differs from the reference"
  fi
  pass "$name"
}

# same_site NAME SRC: build SRC with each binary and compare the output trees.
same_site() {
  name=$1
  src=$2
  "$static" build "$src" "$work/$name.out.static" https://example.org > "$work/$name.log.static" 2>&1 \
    || { cat "$work/$name.log.static"; fail "$name: static build failed"; }
  "$ref" build "$src" "$work/$name.out.ref" https://example.org > "$work/$name.log.ref" 2>&1 \
    || { cat "$work/$name.log.ref"; fail "$name: reference build failed"; }
  if ! diff -r "$work/$name.out.ref" "$work/$name.out.static" > "$work/$name.diff"; then
    head -n 60 "$work/$name.diff"
    fail "$name: output tree differs from the reference"
  fi
  pass "$name ($(find "$work/$name.out.static" -type f | wc -l) files identical)"
}

# --- 1 and 2: CLI and test subcommands ---------------------------------------
same_output version --version
for t in test-markdown test-frontmatter test-full test-state test-attest; do
  same_output "$t" "$t"
done
same_output validate-state validate-state .machine_readable/descriptiles/STATE.a2ml

# --- 3: examples/ and a fixture site -------------------------------------------
same_site examples examples
# Every page has exactly one h1 and no skipped heading levels, or the build's
# accessibility certification (O3) fails it.
site="$work/site"
mkdir -p "$site/blog" "$site/public"
cat > "$site/index.md" <<'EOF'
---
title: Home
date: 2026-01-15
description: Fixture home page
site: Fixture
tags: [idris, ssg]
---

# Home

Some **bold**, *italic*, ~~struck~~ and `code` text with a [link](https://example.org/x).

![A red dragon](dragon.png)

## Lists

- one
- two
  - nested
1. first
2. second

> a quote

| a | b |
|---|---|
| 1 | 2 |

```idris
main : IO ()
```

---
EOF
cat > "$site/blog/post.md" <<'EOF'
---
title: A post
date: 2026-02-01T09:30:00Z
description: Second page
---

# A post

## Part one

### Detail

Text & entities < > "quotes".
EOF
cat > "$site/draft.md" <<'EOF'
---
title: Not yet
draft: true
---

# Not yet
EOF
printf 'User-agent: *\nAllow: /\n' > "$site/public/robots.txt"
same_site fixture "$site"
[ ! -e "$work/fixture.out.static/draft.html" ] || fail "fixture: draft page was built"

# --- 4: large page -------------------------------------------------------------
# The C stack does not grow the way Chez's does, so deep non-tail recursion is
# the most likely way for the static binary to fail where the reference
# succeeds. The block parser recurses once per block, so this page has many
# short blocks. BIG_BLOCKS (default 5000, a very long article) sets the size;
# the fork dry-run records where each binary actually fails (RELEASING.adoc).
# One long paragraph would be the wrong stress test: the inline parser re-packs
# the rest of the paragraph at every delimiter, which is quadratic in its length.
n=${BIG_BLOCKS:-5000}
big="$work/big"
mkdir -p "$big"
{
  printf '%s\n' '---' 'title: Large' 'date: 2026-03-01' '---' '' '# Large' ''
  awk -v n="$n" 'BEGIN {
    for (i = 0; i < n; i++) {
      if (i % 50 == 0) printf "## Section %d\n\n", i / 50
      printf "Paragraph %d has **bold**, `code` and a [link](https://example.org/%d).\n\n", i, i
    }
  }'
} > "$big/index.md"
pass "large page: $n blocks, $(wc -c < "$big/index.md") bytes"
same_site large "$big"

echo "test-static: all checks passed"
