;;; STATE.scm — ddraig-ssg Project State
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell

(define-module (ddraig-ssg state)
  #:export (metadata language-enforcement current-position
            blockers-and-issues critical-next-actions
            security-status component-status state-summary))

;; ============================================================================
;; Metadata
;; ============================================================================

(define metadata
  '((version . "1.0.0")
    (updated . "2025-12-17")
    (project . "ddraig-ssg")
    (required-language . "Idris")))

;; ============================================================================
;; Language Enforcement
;; ============================================================================

(define language-enforcement
  '((primary-language . "Idris")
    (file-extension . ".idr")
    (interpreter . "Idris2")
    (minimum-version . "0.8.0")
    (forbidden-languages . ("Python" "JavaScript" "TypeScript" "Ruby" "Go"))
    (rationale . "ddraig-ssg is the DEFINITIVE Idris static site generator. It MUST be written entirely in Idris. No other implementation languages are permitted.")
    (enforcement . "strict")))

;; ============================================================================
;; Current Position
;; ============================================================================

(define current-position
  '((phase . "v1.0 - Idris Implementation Complete, Hub Integration In Progress")
    (overall-completion . 75)
    (components
      ((Idris-engine
         ((status . "complete")
          (completion . 100)
          (features . ("frontmatter" "markdown" "templates" "drafts" "code-blocks"))))
       (mcp-adapter
         ((status . "in-progress")
          (language . "ReScript")
          (completion . 20)
          (next-steps . ("Full MCP protocol" "Hub registration" "Event publishing"))))
       (security
         ((status . "complete")
          (completion . 100)
          (features . ("SHA-pinned-actions" "CodeQL" "SECURITY.md" "security.txt"))))
       (documentation
         ((status . "complete")
          (completion . 100)
          (features . ("README" "CONTRIBUTING" "SECURITY" "ROADMAP" "CHANGELOG"))))))))

(define blockers-and-issues
  '((critical ())
    (high-priority ())
    (resolved
      (("SECURITY.md placeholders" . "fixed")
       ("CI version mismatch" . "fixed")
       ("Dependabot unused ecosystems" . "cleaned")))))

(define critical-next-actions
  '((immediate
      (("Complete MCP adapter protocol" . high)
       ("Hub registration and discovery" . high)))
    (short-term
      (("Extended Markdown support" . medium)
       ("Incremental builds" . medium)))
    (long-term
      (("Plugin architecture" . low)
       ("Theme system" . low)))))

(define security-status
  '((supply-chain . "protected")
    (actions-pinning . "SHA-pinned")
    (static-analysis . "CodeQL enabled")
    (dependency-updates . "Dependabot configured")
    (vulnerability-disclosure . "SECURITY.md complete")
    (rfc9116 . "security.txt present")))

(define state-summary
  '((project . "ddraig-ssg")
    (language . "Idris")
    (idris-version . ">= 0.8.0")
    (completion . 75)
    (blockers . 0)
    (security-issues . 0)
    (updated . "2025-12-17")))
