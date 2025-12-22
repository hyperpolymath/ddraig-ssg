;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
;;; META.scm — ddraig-ssg Project Metadata

(define-module (ddraig-ssg meta)
  #:export (architecture-decisions development-practices design-rationale
            language-rules build-system component-inventory))

;; ============================================================================
;; Language Rules (ABSOLUTE - NO EXCEPTIONS)
;; ============================================================================

(define language-rules
  '((mandatory-language . "Idris")
    (idris-version . ">= 0.8.0")
    (enforcement-level . "absolute")
    (rationale . "Each SSG satellite is the DEFINITIVE implementation for its language. ddraig-ssg IS the Idris SSG.")
    (violations
     ("Python implementation" . "FORBIDDEN")
     ("JavaScript/TypeScript" . "FORBIDDEN")
     ("Haskell" . "FORBIDDEN")
     ("Ruby" . "FORBIDDEN")
     ("Go" . "FORBIDDEN")
     ("Java" . "FORBIDDEN")
     ("Any non-Idris language" . "FORBIDDEN - defeats the purpose of this satellite"))
    (correct-implementation
     (interpreter . "Idris2")
     (mcp-adapter . "adapters/ in ReScript (only exception)"))))

;; ============================================================================
;; Architecture Decisions
;; ============================================================================

(define architecture-decisions
  '((adr-001
     (title . "Idris-Only Implementation")
     (status . "accepted")
     (date . "2025-12-16")
     (context . "SSG satellites must be in their target language")
     (decision . "ddraig-ssg is written entirely in Idris")
     (consequences . ("Language-specific features" "Idiomatic patterns" "Dependent type benefits")))

    (adr-002
     (title . "RSR Compliance")
     (status . "accepted")
     (date . "2025-12-15")
     (context . "Part of hyperpolymath ecosystem")
     (decision . "Follow Rhodium Standard Repository guidelines")
     (consequences . ("RSR Gold target" "SHA-pinned actions" "SPDX headers")))

    (adr-003
     (title . "MCP Integration via ReScript")
     (status . "accepted")
     (date . "2025-12-16")
     (context . "Need to connect to poly-ssg-mcp hub")
     (decision . "Use ReScript adapter in adapters/ directory")
     (consequences . ("Language exception for adapters/" "Node.js runtime for MCP")))

    (adr-004
     (title . "Justfile + Mustfile Build System")
     (status . "accepted")
     (date . "2025-12-17")
     (context . "Need consistent build automation")
     (decision . "Use just for automation, Mustfile for compliance checks")
     (consequences . ("Consistent commands" "Compliance enforcement" "CI integration")))

    (adr-005
     (title . "Nickel Configuration")
     (status . "accepted")
     (date . "2025-12-17")
     (context . "Need type-safe configuration")
     (decision . "Use Nickel for configuration schemas")
     (consequences . ("Type-safe configs" "Schema validation" "Consistent structure")))))

;; ============================================================================
;; Development Practices
;; ============================================================================

(define development-practices
  '((code-style
     (languages . ("Idris"))
     (formatting . "Follow Idris community conventions")
     (naming . "camelCase for functions, PascalCase for types"))

    (security
     (sast . "CodeQL for workflow scanning")
     (credentials . "env vars only")
     (actions . "SHA-pinned (supply chain security)")
     (dependencies . "Dependabot monitoring"))

    (versioning
     (scheme . "SemVer 2.0.0")
     (changelog . "Keep a Changelog format")
     (tagging . "v{MAJOR}.{MINOR}.{PATCH}"))

    (testing
     (unit . "Built-in test commands in Ddraig.idr")
     (integration . "Full pipeline tests")
     (ci . "GitHub Actions on push/PR"))

    (documentation
     (primary . "AsciiDoc (README.adoc, cookbook.adoc)")
     (secondary . "Markdown for simpler docs")
     (api . "Type signatures as documentation"))))

;; ============================================================================
;; Build System
;; ============================================================================

(define build-system
  '((primary
     (tool . "Idris2")
     (command . "idris2 Ddraig.idr -o ddraig")
     (output . "src/build/exec/ddraig"))

    (automation
     (just . "justfile for common tasks")
     (must . "Mustfile for compliance checks")
     (nickel . "nickel/*.ncl for configuration"))

    (ci
     (platform . "GitHub Actions")
     (jobs . ("language-check" "build" "test" "adapter" "security"))
     (triggers . ("push to main" "pull request to main")))))

;; ============================================================================
;; Component Inventory
;; ============================================================================

(define component-inventory
  '((total-components . 35)
    (categories
      (("Core Engine" . 4)
       ("Build System" . 4)
       ("Adapters" . 1)
       ("Documentation" . 8)
       ("Configuration (.scm)" . 6)
       ("Security" . 5)
       ("Testing" . 3)
       ("Hooks" . 4)))))

;; ============================================================================
;; Design Rationale
;; ============================================================================

(define design-rationale
  '((why-idris
     "ddraig-ssg exists to be THE Idris static site generator.
      Every poly-ssg satellite is the definitive SSG for its language.
      Using any other language defeats the entire purpose of this project.")

    (why-dependent-types
     "Dependent types provide compile-time guarantees that:
      - Frontmatter schemas are enforced
      - Template variables are bound
      - Output is well-formed
      This is the unique value proposition of an Idris SSG.")

    (why-rescript-adapter
     "The MCP adapter runs in Node.js for protocol compatibility.
      ReScript provides type safety while compiling to JavaScript.
      This is the ONLY exception to the Idris-only rule.")))
