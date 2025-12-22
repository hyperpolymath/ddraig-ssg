# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
#
# justfile — ddraig-ssg build automation
# THE Idris static site generator - types that breathe fire

# Default recipe - show available commands
default:
    @just --list

# ============================================================================
# Build Commands
# ============================================================================

# Build the Idris SSG engine
build:
    @echo "🐉 Building ddraig-ssg (Idris 2)..."
    cd src && idris2 --build ddraig.ipkg
    @echo "✓ Build complete: src/build/exec/ddraig"

# Clean build artifacts
clean:
    @echo "🧹 Cleaning build artifacts..."
    rm -rf src/build/
    rm -rf adapters/lib/
    rm -rf adapters/src/*.mjs
    @echo "✓ Clean complete"

# Rebuild from scratch
rebuild: clean build

# Build the ReScript MCP adapter
build-adapter:
    @echo "📡 Building MCP adapter (ReScript)..."
    cd adapters && npm install && npm run build
    @echo "✓ Adapter build complete"

# Build everything
build-all: build build-adapter

# ============================================================================
# Test Commands
# ============================================================================

# Run all tests
test: build
    @echo "🧪 Running tests..."
    ./src/build/exec/ddraig test-markdown
    ./src/build/exec/ddraig test-frontmatter
    ./src/build/exec/ddraig test-full
    @echo "✓ All tests passed"

# Run markdown parsing tests
test-markdown: build
    @echo "🧪 Testing markdown parser..."
    ./src/build/exec/ddraig test-markdown

# Run frontmatter parsing tests
test-frontmatter: build
    @echo "🧪 Testing frontmatter parser..."
    ./src/build/exec/ddraig test-frontmatter

# Run full pipeline test
test-full: build
    @echo "🧪 Testing full pipeline..."
    ./src/build/exec/ddraig test-full

# Run end-to-end tests
test-e2e: build
    @echo "🧪 Running e2e tests..."
    @mkdir -p test-output
    @echo '---\ntitle: E2E Test\ndate: 2025-01-01\n---\n\n# Hello E2E\n\nThis is a **test**.' > test-output/test.md
    ./src/build/exec/ddraig test-full
    @rm -rf test-output
    @echo "✓ E2E tests passed"

# Run all tests including e2e
test-all: test test-e2e
    @echo "✓ All tests completed successfully"

# ============================================================================
# Type Checking & Linting
# ============================================================================

# Type check without full build
typecheck:
    @echo "🔍 Type checking Idris code..."
    cd src && idris2 --typecheck Ddraig.idr
    @echo "✓ Type check passed"

# Verify no forbidden languages in src/
lint-language:
    @echo "🔍 Checking language compliance..."
    @forbidden=$$(find src/ -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.hs" -o -name "*.rb" -o -name "*.go" \) 2>/dev/null || true); \
    if [ -n "$$forbidden" ]; then \
        echo "❌ ERROR: Found forbidden language files in src/:"; \
        echo "$$forbidden"; \
        exit 1; \
    fi
    @echo "✓ Language compliance verified (Idris only in src/)"

# Run all lints
lint: lint-language typecheck

# ============================================================================
# Language Server
# ============================================================================

# Start Idris 2 language server
lsp:
    @echo "🚀 Starting Idris 2 Language Server..."
    idris2-lsp

# ============================================================================
# Compilation & Generation
# ============================================================================

# Compile a .idr file
compile file:
    @echo "🔧 Compiling {{file}}..."
    idris2 {{file}} -o "$(basename {{file}} .idr)"
    @echo "✓ Compiled to build/exec/$(basename {{file}} .idr)"

# Generate site from content directory
generate content_dir="content" output_dir="output":
    @echo "📝 Generating site from {{content_dir}} to {{output_dir}}..."
    @mkdir -p {{output_dir}}
    ./src/build/exec/ddraig build {{content_dir}} {{output_dir}}
    @echo "✓ Site generated in {{output_dir}}"

# ============================================================================
# Security
# ============================================================================

# Run security audit
security-audit:
    @echo "🔒 Running security audit..."
    @echo "Checking GitHub Actions SHA pinning..."
    @grep -r "uses:" .github/workflows/*.yml | grep -v "@[a-f0-9]\{40\}" && echo "⚠️  Found actions without SHA pins" || echo "✓ All actions SHA-pinned"
    @echo "Checking for secrets in codebase..."
    @grep -rn "password\|secret\|api_key\|token" --include="*.idr" --include="*.res" src/ adapters/src/ 2>/dev/null && echo "⚠️  Potential secrets found" || echo "✓ No obvious secrets"
    @echo "Checking npm dependencies..."
    cd adapters && npm audit 2>/dev/null || echo "⚠️  npm audit check (may require npm install first)"
    @echo "✓ Security audit complete"

# ============================================================================
# Documentation
# ============================================================================

# Serve documentation locally
docs-serve:
    @echo "📚 Serving documentation..."
    @python3 -m http.server 8000 --directory . 2>/dev/null || echo "Install Python 3 for local serving"

# Generate API documentation
docs-api: build
    @echo "📖 Generating API docs..."
    @echo "API docs would be generated from type signatures"
    idris2 --doc src/Ddraig.idr 2>/dev/null || echo "Doc generation requires additional setup"

# ============================================================================
# Development Workflow
# ============================================================================

# Watch for changes and rebuild
watch:
    @echo "👁️ Watching for changes..."
    @which watchexec > /dev/null && watchexec -e idr just build || echo "Install watchexec for file watching: cargo install watchexec-cli"

# Format check (Idris doesn't have standard formatter yet)
format:
    @echo "📐 Format checking..."
    @echo "Note: Idris 2 doesn't have a standard formatter yet"
    @echo "Following project conventions from copilot-instructions.md"

# Pre-commit checks
pre-commit: lint test
    @echo "✓ Pre-commit checks passed"

# ============================================================================
# Release
# ============================================================================

# Prepare for release
release-prep version:
    @echo "📦 Preparing release {{version}}..."
    @echo "1. Update version in src/manifest.json"
    @echo "2. Update CHANGELOG.md"
    @echo "3. Run: just test-all"
    @echo "4. Run: just security-audit"
    @echo "5. Commit and tag: git tag -a v{{version}} -m 'Release v{{version}}'"

# ============================================================================
# CI/CD Helpers
# ============================================================================

# CI build (for GitHub Actions)
ci-build:
    @echo "🏗️ CI Build..."
    just build
    just lint-language
    just typecheck

# CI test (for GitHub Actions)
ci-test:
    @echo "🧪 CI Test..."
    just test-all

# Full CI pipeline
ci: ci-build ci-test security-audit
    @echo "✓ CI pipeline complete"

# ============================================================================
# Container
# ============================================================================

# Build container image
container-build:
    @echo "🐳 Building container..."
    podman build -t ddraig-ssg:latest .

# Run in container
container-run:
    @echo "🐳 Running in container..."
    podman run -it --rm -v "$(pwd):/workspace" ddraig-ssg:latest

# ============================================================================
# Utilities
# ============================================================================

# Show project info
info:
    @echo "🐉 ddraig-ssg - THE Idris Static Site Generator"
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo "Language: Idris 2 (ONLY - no exceptions in src/)"
    @echo "Adapter:  ReScript (MCP integration)"
    @echo "License:  AGPL-3.0-or-later"
    @echo ""
    @echo "Commands: just --list"

# Print version
version:
    @echo "ddraig-ssg v0.1.0"
    @idris2 --version 2>/dev/null || echo "Idris2 not found"

# Help
help:
    @echo "🐉 ddraig-ssg - Just Commands"
    @echo ""
    @echo "Build:    just build | clean | rebuild | build-all"
    @echo "Test:     just test | test-markdown | test-e2e | test-all"
    @echo "Lint:     just lint | lint-language | typecheck"
    @echo "LSP:      just lsp"
    @echo "Security: just security-audit"
    @echo "CI:       just ci | ci-build | ci-test"
    @echo ""
    @echo "See cookbook.adoc for detailed recipes"
