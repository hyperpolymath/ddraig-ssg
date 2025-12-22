;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
;;; ECOSYSTEM.scm — ddraig-ssg Ecosystem Configuration

(define-module (ddraig-ssg ecosystem)
  #:version "1.0.0"
  #:export (ecosystem-definition related-projects integration-points))

;; ============================================================================
;; Ecosystem Definition
;; ============================================================================

(ecosystem
  (version "1.0.0")
  (name "ddraig-ssg")
  (type "satellite-ssg")
  (purpose "The DEFINITIVE Idris static site generator")
  (tagline "Types that breathe fire")

  (language-identity
    (primary "Idris 2")
    (version ">= 0.8.0")
    (paradigm ("functional" "dependently-typed" "pure"))
    (rationale "ddraig-ssg exists to be THE Idris SSG. The entire engine is written in Idris.")
    (forbidden ("Python" "JavaScript" "TypeScript" "Ruby" "Go" "Java" "Haskell"))
    (exceptions ((adapters . "ReScript")))
    (enforcement "This is not negotiable. Any non-Idris implementation will be rejected."))

  (position-in-ecosystem
    "Satellite SSG in the poly-ssg constellation. Each satellite is the definitive SSG for its language.")

  (related-projects
    (project
      (name "poly-ssg-mcp")
      (url "https://github.com/hyperpolymath/poly-ssg-mcp")
      (relationship "hub")
      (description "Unified MCP server for 28+ SSGs - provides adapter interface")
      (integration "MCP protocol via adapters/src/DdraigAdapter.res"))
    (project
      (name "rhodium-standard-repositories")
      (url "https://github.com/hyperpolymath/rhodium-standard-repositories")
      (relationship "standard")
      (description "Repository standards and compliance guidelines")
      (compliance-level "RSR Gold target")))

  (integration-points
    (mcp-adapter
      (location "adapters/src/DdraigAdapter.res")
      (language "ReScript")
      (protocol "Model Context Protocol")
      (status "in-progress"))
    (ci-integration
      (platform "GitHub Actions")
      (workflows ("ci.yml" "codeql.yml"))
      (features ("build" "test" "language-check" "security"))))

  (what-this-is
    "- The DEFINITIVE static site generator written in Idris 2
     - Part of the poly-ssg satellite constellation
     - Dependent types for provable correctness
     - Type-safe content processing")

  (what-this-is-not
    "- NOT a template that can be reimplemented in other languages
     - NOT optional about being in Idris
     - NOT a general-purpose SSG (use Hugo, etc.)"))
