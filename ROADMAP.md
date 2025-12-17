# ddraig-ssg Roadmap

<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2025 hyperpolymath -->

> **ddraig-ssg** is the DEFINITIVE Idris static site generator. The dragon breathes type-safe fire.

## Current Status

| Component | Status | Progress |
|-----------|--------|----------|
| **Idris 2 Engine** | Complete | 100% |
| **MCP Adapter (ReScript)** | In Progress | 20% |
| **Documentation** | Complete | 100% |
| **CI/CD Pipeline** | Complete | 100% |
| **Security Policies** | Complete | 100% |

---

## Phase 1: Foundation (COMPLETE)

### 1.1 Core Engine
- [x] Frontmatter parsing (YAML-style with `---` delimiters)
- [x] Markdown processing
- [x] Template system
- [x] Draft support
- [x] Code block handling
- [x] Inline formatting
- [x] HTML escaping & entity encoding
- [x] Type-safe configuration

### 1.2 Infrastructure
- [x] GitHub Actions CI pipeline with SHA-pinned actions
- [x] Language enforcement (Idris-only in `src/`)
- [x] CodeQL security scanning
- [x] Dependabot configuration
- [x] SPDX license headers throughout
- [x] RSR (Rhodium Standard Repository) compliance

### 1.3 Documentation & Governance
- [x] README.adoc with user-focused documentation
- [x] SECURITY.md with vulnerability reporting process
- [x] CODE_OF_CONDUCT.md
- [x] CONTRIBUTING.md
- [x] AI boundary declarations (AIBDP, ai.txt, consent-aware HTTP)
- [x] RFC 9116 security.txt

---

## Phase 2: Hub Integration (IN PROGRESS)

### 2.1 MCP Adapter Development
- [x] ReScript adapter scaffolding
- [x] `connect()` / `disconnect()` lifecycle
- [x] Idris2 command execution wrapper
- [ ] Full MCP protocol implementation
- [ ] Hub registration and discovery
- [ ] Bi-directional communication with poly-ssg-mcp

### 2.2 Inter-Satellite Communication
- [ ] Event publishing to hub
- [ ] Configuration synchronization
- [ ] Build status reporting
- [ ] Cross-satellite theme sharing

---

## Phase 3: Enhanced Features

### 3.1 Content Processing
- [ ] Extended Markdown support (tables, footnotes, definition lists)
- [ ] Syntax highlighting for code blocks
- [ ] LaTeX/KaTeX math rendering
- [ ] Mermaid diagram support
- [ ] Table of contents generation
- [ ] Reading time estimation

### 3.2 Type-Safe Schemas
- [ ] Dependent type enforcement for frontmatter schemas
- [ ] Custom schema definitions
- [ ] Schema validation at compile time
- [ ] Refinement types for content constraints

### 3.3 Build System
- [ ] Incremental builds with change detection
- [ ] Parallel page generation
- [ ] Asset pipeline (CSS/JS minification)
- [ ] Image optimization
- [ ] Sitemap generation
- [ ] RSS/Atom feed generation

---

## Phase 4: Advanced Capabilities

### 4.1 Theming System
- [ ] Theme package format specification
- [ ] Template inheritance
- [ ] Partial templates
- [ ] Theme configuration DSL
- [ ] Built-in responsive themes

### 4.2 Plugin Architecture
- [ ] Plugin API design
- [ ] Hook system for build lifecycle
- [ ] Content transformation plugins
- [ ] Output format plugins (PDF, EPUB)

### 4.3 Developer Experience
- [ ] Live reload development server
- [ ] Build time reporting
- [ ] Error messages with source locations
- [ ] VS Code / LSP integration guidance

---

## Phase 5: Production Readiness

### 5.1 Performance
- [ ] Build performance benchmarks
- [ ] Memory usage optimization
- [ ] Lazy loading strategies
- [ ] Caching layer

### 5.2 Deployment
- [ ] GitHub Pages integration guide
- [ ] Netlify adapter
- [ ] Vercel adapter
- [ ] Docker container for CI

### 5.3 Ecosystem
- [ ] Package manager integration (Pack)
- [ ] Starter templates
- [ ] Example sites gallery
- [ ] Migration guides from other SSGs

---

## Language Policy

**This project is written in Idris 2. This is non-negotiable.**

| Language | Allowed | Location |
|----------|---------|----------|
| Idris 2 | ✅ Required | `src/` |
| ReScript | ✅ Allowed | `adapters/` only |
| Python | ❌ FORBIDDEN | - |
| JavaScript/TypeScript | ❌ FORBIDDEN | - |
| Ruby, Go, Java | ❌ FORBIDDEN | - |

ddraig-ssg exists to be THE definitive Idris static site generator. Alternative language implementations belong in their respective poly-ssg satellites.

---

## Security Roadmap

### Completed
- [x] SHA-pinned GitHub Actions (supply chain protection)
- [x] CodeQL static analysis
- [x] Dependabot automated updates
- [x] SECURITY.md vulnerability disclosure policy
- [x] RFC 9116 security.txt
- [x] Proper .gitignore for secrets

### Planned
- [ ] Git commit signing guidance
- [ ] Pre-commit hooks for SPDX validation
- [ ] Secrets scanning in CI
- [ ] SBOM (Software Bill of Materials) generation
- [ ] Signed releases

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

The project follows the poly-ssg ecosystem conventions and RSR compliance standards.

---

## Version History

| Version | Date | Milestone |
|---------|------|-----------|
| 1.0.0 | 2025-12-16 | Idris engine complete |
| 0.1.0 | 2025-12-XX | Initial MCP adapter |
| 0.2.0 | TBD | Hub integration |
| 1.1.0 | TBD | Enhanced Markdown |
| 2.0.0 | TBD | Plugin system |

---

*Last updated: 2025-12-17*
