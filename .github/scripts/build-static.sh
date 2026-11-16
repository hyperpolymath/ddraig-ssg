#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Build a fully static x86_64-linux-musl `ddraig` binary:
#
#   Ddraig.idr --(Idris 2 RefC backend)--> C --(zig cc, musl, -static)--> dist/ddraig
#
# linked against GMP and the Idris 2 C runtimes, both rebuilt here for musl
# because the copies in the image are built for glibc. Why RefC and Zig, and
# what this does not yet guarantee: RELEASING.adoc.
#
# DRAFT: written without running it. Run from the repository root inside the
# digest-pinned idris2-pack image that ci.yml and release.yml use. Needs idris2,
# git, make and gcc (in the image) plus curl, xz and m4 (installed by
# release.yml). readelf comes with gcc's binutils.

set -eu

# --- Pins ---------------------------------------------------------------------
# Zig: version and SHA-256 of the x86_64-linux tarball, from
# https://ziglang.org/download/index.json, recorded 2026-10-13.
ZIG_VERSION=0.16.0
ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
# GMP: SHA-256 of gmp-6.3.0.tar.xz, computed 2026-10-13 from both gmplib.org and
# ftp.gnu.org (identical). The GNU mirror is used because gmplib.org has
# rate-limited CI runners in the past.
GMP_VERSION=6.3.0
GMP_SHA256=a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
# The Idris 2 commit inside the pinned image (its pack state holds
# install/<commit>/idris2). The C runtimes are rebuilt from this commit, so it
# must be the compiler's own commit; check_idris enforces that.
IDRIS2_COMMIT=6ca00e72e32849cb35e5c262904e9c3cffc1a9a4

TARGET=x86_64-linux-musl
ROOT=$(pwd)
WORK="$ROOT/build/static"
DIST="$ROOT/dist"

# log MESSAGE...: print a build progress message to stdout.
log() { printf '==> %s\n' "$*"; }
# die MESSAGE...: print a build error to stderr and exit with status 1.
die() { printf 'build-static: %s\n' "$*" >&2; exit 1; }

# fetch URL SHA256 DEST: download over HTTPS to DEST and verify its SHA-256.
# Overwrites DEST; leaves it in place on checksum failure. Download or checksum
# failures terminate the script with the failing command's exit status.
fetch() {
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
       --output "$3" "$1"
  printf '%s  %s\n' "$2" "$3" | sha256sum --check --strict -
}

# The runtime sources must belong to the compiler that generates the C:
#   1. the idris2 on PATH reports the pinned commit in its version string;
#   2. pack has that commit installed;
#   3. every RefC and C-support header it installed equals the source's.
# Uses SRC as the source tree and PACK_STATE_DIR as pack's state directory.
# Missing pack state or a version, layout or header mismatch exits the script
# with status 1; idris2 --version failures propagate their exit status.
check_idris() {
  short=$(printf '%s' "$IDRIS2_COMMIT" | cut -c1-9)
  version=$(idris2 --version)
  case "$version" in
    *"$short"*) ;;
    *) die "idris2 reports '$version', not commit $short; update IDRIS2_COMMIT when the image digest changes" ;;
  esac
  [ -n "${PACK_STATE_DIR:-}" ] \
    || die "PACK_STATE_DIR is unset; run inside the pinned idris2-pack image"
  set -- "$PACK_STATE_DIR/install/$IDRIS2_COMMIT/idris2"/idris2-*
  [ $# -eq 1 ] && [ -d "$1" ] \
    || die "expected one idris2-<version> directory for commit $IDRIS2_COMMIT, found: $*"
  inst=$1
  for h in "$SRC"/support/refc/*.h "$SRC"/support/c/*.h; do
    sub=$(basename "$(dirname "$h")")
    [ -f "$inst/support/$sub/$(basename "$h")" ] \
      || die "the image has no support/$sub/$(basename "$h")"
    cmp -s "$h" "$inst/support/$sub/$(basename "$h")" \
      || die "support/$sub/$(basename "$h") differs between the image and Idris 2 $IDRIS2_COMMIT"
  done
}

mkdir -p "$WORK" "$DIST"

# --- Zig ----------------------------------------------------------------------
log "Zig $ZIG_VERSION"
zig_dir="$WORK/zig-x86_64-linux-$ZIG_VERSION"
if [ ! -x "$zig_dir/zig" ]; then
  fetch "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" \
        "$ZIG_SHA256" "$WORK/zig.tar.xz"
  tar -xJf "$WORK/zig.tar.xz" -C "$WORK"
fi
ZIG="$zig_dir/zig"
"$ZIG" version
# ccm ARG...: invoke Zig's C compiler for TARGET at -O2, forwarding ARG.
ccm() { "$ZIG" cc -target "$TARGET" -O2 "$@"; }

# --- Idris 2 runtime sources, at the compiler's commit ------------------------
log "Idris 2 sources at $IDRIS2_COMMIT"
SRC="$WORK/idris2-src"
if [ ! -d "$SRC/.git" ]; then
  git init --quiet "$SRC"
  git -C "$SRC" fetch --quiet --depth 1 https://github.com/idris-lang/Idris2 "$IDRIS2_COMMIT"
  git -C "$SRC" checkout --quiet FETCH_HEAD
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$IDRIS2_COMMIT" ] \
  || die "checked out the wrong Idris 2 commit"
check_idris

# --- GMP, static, for musl ----------------------------------------------------
log "GMP $GMP_VERSION for $TARGET"
GMP="$WORK/gmp-$TARGET"
if [ ! -f "$GMP/lib/libgmp.a" ]; then
  fetch "https://ftp.gnu.org/gnu/gmp/gmp-$GMP_VERSION.tar.xz" "$GMP_SHA256" "$WORK/gmp.tar.xz"
  rm -rf "$WORK/gmp-$GMP_VERSION"
  tar -xJf "$WORK/gmp.tar.xz" -C "$WORK"
  (
    cd "$WORK/gmp-$GMP_VERSION"
    # Portable C only (--disable-assembly): Ddraig's Integer use is trivial,
    # and generic C avoids assembler differences between gcc and zig cc.
    ./configure --prefix="$GMP" --disable-shared --enable-static --disable-assembly \
      CC="$ZIG cc -target $TARGET" AR="$ZIG ar" RANLIB="$ZIG ranlib" CFLAGS=-O2
    make -j"$(nproc)"
    make check
    make install
  )
fi

# --- Idris 2 C runtimes, static, for musl -------------------------------------
# Same sources and flags as support/c/Makefile and support/refc/Makefile
# (every *.c in the directory, -O2), compiled with zig cc instead of gcc.
log "Idris 2 C runtimes for $TARGET"
RT="$WORK/runtime-$TARGET"
rm -rf "$RT"
mkdir -p "$RT"
for f in "$SRC"/support/c/*.c; do
  ccm -I"$SRC/support/c" -I"$GMP/include" -c "$f" -o "$RT/c_$(basename "$f" .c).o"
done
"$ZIG" ar rcs "$RT/libidris2_support.a" "$RT"/c_*.o
for f in "$SRC"/support/refc/*.c; do
  ccm -I"$SRC/support/refc" -I"$SRC/support/c" -I"$GMP/include" \
      -c "$f" -o "$RT/refc_$(basename "$f" .c).o"
done
"$ZIG" ar rcs "$RT/libidris2_refc.a" "$RT"/refc_*.o

# --- Ddraig -> C -> static binary ---------------------------------------------
# RefC writes build/exec/ddraig-refc.c and then links a glibc binary with the
# image's gcc. We keep only the C file and link it ourselves.
log "RefC: Ddraig.idr -> C"
idris2 --cg refc Ddraig.idr -o ddraig-refc
CSRC="$ROOT/build/exec/ddraig-refc.c"
[ -f "$CSRC" ] || die "RefC did not leave $CSRC"

log "Link static $TARGET binary"
ccm -static -s \
    -I"$SRC/support/refc" -I"$SRC/support/c" -I"$GMP/include" \
    "$CSRC" "$RT/libidris2_refc.a" "$RT/libidris2_support.a" "$GMP/lib/libgmp.a" -lm \
    -o "$DIST/ddraig"

log "Check the binary is fully static"
# Capture readelf's output first: piping it straight into grep would let a
# readelf failure pass silently, because sh has no pipefail.
command -v readelf > /dev/null || die "readelf not found (binutils)"
headers=$(readelf --wide --program-headers "$DIST/ddraig")
dynamic=$(readelf --wide --dynamic "$DIST/ddraig")
case "$headers" in
  *INTERP*) die "dist/ddraig asks for a dynamic loader (PT_INTERP)" ;;
esac
case "$dynamic" in
  *NEEDED*) die "dist/ddraig needs shared libraries (DT_NEEDED)" ;;
esac
"$DIST/ddraig" --version
sha256sum "$DIST/ddraig"
