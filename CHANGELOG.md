# Changelog

<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2025 hyperpolymath -->

All notable changes to ddraig-ssg will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Build System
- `justfile` with comprehensive build automation (build, test, lint, ci commands)
- `Mustfile` with mandatory compliance checks (language, security, docs)
- Nickel configuration files (`nickel/config.ncl`, `schema.ncl`, `ci.ncl`)

#### Documentation
- `cookbook.adoc` with hyperlinked CLI, Just, Must, and Nickel recipes
- ROADMAP.md with comprehensive 5-phase project roadmap
- CHANGELOG.md for tracking releases

#### Configuration (.scm files)
- `PLAYBOOK.scm` - Operational playbook with build/test/deploy procedures
- `AGENTIC.scm` - AI agent configuration and capabilities
- `NEUROSYM.scm` - Neurosymbolic configuration for type-AI integration
- Updated `META.scm` with component inventory and new ADRs
- Updated `ECOSYSTEM.scm` with integration points
- Updated `STATE.scm` with current project status (90% complete)

#### Hooks
- Git hooks: `hooks/pre-commit`, `hooks/pre-push`
- Claude Code hooks: `.claude/hooks/session-start.sh`
- Claude settings: `.claude/settings.json`
- Hooks documentation: `hooks/README.md`

### Changed
- Enhanced CI workflow with 5 jobs: language-check, build, test, adapter, security
- Added build caching for Idris type-checked code
- Updated CI workflow to use Idris 2 v0.8.0 (was 0.7.0)
- Cleaned up dependabot.yml to only include used ecosystems

### Fixed
- SECURITY.md template placeholders replaced with actual values
- Dependabot now correctly monitors `/adapters` directory
- CI type check now uses correct file path (src/Ddraig.idr)

### Security
- Enhanced CI with dedicated security job
- SHA-pinned actions verification in CI
- Secrets scanning check in CI
- npm audit for adapter dependencies
- Pre-commit hook for language compliance
- Pre-push hook for test verification

## [1.0.0] - 2025-12-16

### Added
- Complete Idris 2 static site generator engine
- Frontmatter parsing with YAML-style delimiters
- Markdown to HTML conversion
- Template system with variable substitution
- Draft post support
- Code block handling with HTML escaping
- Inline formatting support (bold, italic, code)
- ReScript MCP adapter scaffold (`adapters/`)
- GitHub Actions CI with language enforcement
- CodeQL security scanning
- Dependabot configuration
- AIBDP manifest for AI boundary declaration
- RFC 9116 security.txt
- RSR-compliant repository structure
- Comprehensive documentation (README.adoc, CONTRIBUTING.md, CODE_OF_CONDUCT.md)

### Security
- SHA-pinned GitHub Actions for supply chain security
- Comprehensive .gitignore excluding secrets and credentials
- SECURITY.md with vulnerability disclosure process

---

## Component Status

| Component | Status | Count |
|-----------|--------|-------|
| Core Engine | Complete | 4 |
| Build System | Complete | 4 |
| Adapters | In Progress | 1 |
| Documentation | Complete | 8 |
| Configuration | Complete | 6 |
| Security | Complete | 5 |
| Testing | Complete | 3 |
| Hooks | Complete | 4 |
| **Total** | **90%** | **35** |

## Release Types

- **Major (X.0.0)**: Breaking changes, new major features
- **Minor (0.X.0)**: New features, backward compatible
- **Patch (0.0.X)**: Bug fixes, security patches

## Links

- [Source Repository](https://github.com/hyperpolymath/ddraig-ssg)
- [Security Policy](SECURITY.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Roadmap](ROADMAP.md)
- [Cookbook](cookbook.adoc)

[Unreleased]: https://github.com/hyperpolymath/ddraig-ssg/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hyperpolymath/ddraig-ssg/releases/tag/v1.0.0
