#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Fail unless the idris2 on PATH is at least the minimum version this project
# supports (README.adoc: "Requires idris2 >= 0.8.0").
#
# usage: check-idris-version.sh [MINIMUM]     (default 0.8.0)
#
# DRAFT: not yet run. See RELEASING.adoc.

set -eu

min=${1:-0.8.0}
out=$(idris2 --version)
printf '%s\n' "$out"

# "Idris 2, version 0.8.0-6ca00e72e" -> "0.8.0"
ver=$(printf '%s\n' "$out" |
      sed -n 's/.*version \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
if [ -z "$ver" ]; then
  printf 'check-idris-version: cannot read a version from: %s\n' "$out" >&2
  exit 1
fi

lowest=$(printf '%s\n%s\n' "$min" "$ver" | sort -V | head -n 1)
if [ "$lowest" != "$min" ]; then
  printf 'check-idris-version: Idris 2 %s is older than the minimum %s\n' "$ver" "$min" >&2
  exit 1
fi
printf 'OK: Idris 2 %s >= %s\n' "$ver" "$min"
