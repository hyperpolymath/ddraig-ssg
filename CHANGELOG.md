# Changelog

<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2025 hyperpolymath -->

All notable changes to ddraig-ssg will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- ROADMAP.md with comprehensive project roadmap
- CHANGELOG.md for tracking releases

### Changed
- Updated CI workflow to use Idris 2 v0.8.0 (was 0.7.0)
- Cleaned up dependabot.yml to only include used ecosystems (github-actions, npm for adapters)

### Fixed
- SECURITY.md template placeholders replaced with actual project values
- Dependabot now correctly monitors `/adapters` directory for npm dependencies

### Security
- All security policy placeholders now point to correct hyperpolymath/ddraig-ssg resources
- Security email: security@hyperpolymath.org
- PGP key: https://hyperpolymath.org/gpg/security.asc

## [1.0.0] - 2025-12-16

### Added
- Complete Idris 2 static site generator engine
- Frontmatter parsing with YAML-style delimiters
- Markdown to HTML conversion
- Template system with variable substitution
- Draft post support
- Code block handling with HTML escaping
- Inline formatting support
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

## Release Types

- **Major (X.0.0)**: Breaking changes, new major features
- **Minor (0.X.0)**: New features, backward compatible
- **Patch (0.0.X)**: Bug fixes, security patches

## Links

- [Source Repository](https://github.com/hyperpolymath/ddraig-ssg)
- [Security Policy](SECURITY.md)
- [Contributing Guidelines](CONTRIBUTING.md)

[Unreleased]: https://github.com/hyperpolymath/ddraig-ssg/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hyperpolymath/ddraig-ssg/releases/tag/v1.0.0
