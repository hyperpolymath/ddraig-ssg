#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 hyperpolymath
#
# Claude Code session start hook for ddraig-ssg

echo "🐉 ddraig-ssg Development Session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Language: Idris 2 (ONLY in src/)"
echo "Adapter:  ReScript (adapters/ only)"
echo "License:  AGPL-3.0-or-later"
echo ""
echo "Quick commands:"
echo "  just build     - Build Idris engine"
echo "  just test      - Run tests"
echo "  just lint      - Check compliance"
echo "  just info      - Project info"
echo ""

# Check if idris2 is available
if command -v idris2 &> /dev/null; then
    echo "Idris 2: $(idris2 --version 2>/dev/null || echo 'installed')"
else
    echo "⚠️  Idris 2 not found - install via Pack"
fi

# Check if just is available
if ! command -v just &> /dev/null; then
    echo "⚠️  just not found - install for automation: cargo install just"
fi
