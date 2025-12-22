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
    (forbidden-languages . ("Python" "JavaScript" "TypeScript" "Ruby" "Go" "Java" "Haskell"))
    (exceptions . ((adapters . "ReScript")))
    (rationale . "ddraig-ssg is the DEFINITIVE Idris static site generator. It MUST be written entirely in Idris.")
    (enforcement . "strict")))

;; ============================================================================
;; Current Position
;; ============================================================================

(define current-position
  '((phase . "v1.0 - Full Project Structure Complete")
    (overall-completion . 90)
    (components
      ((Idris-engine
         ((status . "complete")
          (completion . 100)
          (features . ("frontmatter" "markdown" "templates" "drafts" "code-blocks" "inline-formatting"))))
       (mcp-adapter
         ((status . "in-progress")
          (language . "ReScript")
          (completion . 20)
          (next-steps . ("Full MCP protocol" "Hub registration" "Event publishing"))))
       (build-system
         ((status . "complete")
          (completion . 100)
          (components . ("justfile" "Mustfile" "nickel/*.ncl" "CI pipeline"))))
       (security
         ((status . "complete")
          (completion . 100)
          (features . ("SHA-pinned-actions" "CodeQL" "SECURITY.md" "security.txt" "git-hooks"))))
       (documentation
         ((status . "complete")
          (completion . 100)
          (files . ("README.adoc" "cookbook.adoc" "ROADMAP.md" "CHANGELOG.md" "CONTRIBUTING.md"))))
       (configuration
         ((status . "complete")
          (completion . 100)
          (files . ("META.scm" "ECOSYSTEM.scm" "STATE.scm" "PLAYBOOK.scm" "AGENTIC.scm" "NEUROSYM.scm"))))
       (hooks
         ((status . "complete")
          (completion . 100)
          (files . ("hooks/pre-commit" "hooks/pre-push" ".claude/hooks/session-start.sh"))))))))

;; ============================================================================
;; Blockers and Issues
;; ============================================================================

(define blockers-and-issues
  '((critical . ())
    (high-priority . ())
    (medium-priority
      (("MCP adapter completion" . "Need full protocol implementation")))
    (resolved
      (("SECURITY.md placeholders" . "fixed 2025-12-17")
       ("CI version mismatch" . "fixed 2025-12-17")
       ("Dependabot unused ecosystems" . "cleaned 2025-12-17")
       ("Missing .scm files" . "added 2025-12-17")
       ("Missing Justfile/Mustfile" . "added 2025-12-17")
       ("Missing hooks" . "added 2025-12-17")
       ("Missing cookbook" . "added 2025-12-17")))))

;; ============================================================================
;; Critical Next Actions
;; ============================================================================

(define critical-next-actions
  '((immediate
      (("Complete MCP adapter protocol" . high)
       ("Test full CI pipeline" . medium)))
    (short-term
      (("Hub registration and discovery" . high)
       ("Extended Markdown support" . medium)
       ("Incremental builds" . medium)))
    (long-term
      (("Plugin architecture" . low)
       ("Theme system" . low)
       ("Production deployment guides" . low)))))

;; ============================================================================
;; Security Status
;; ============================================================================

(define security-status
  '((supply-chain . "protected")
    (actions-pinning . "SHA-pinned (all workflows)")
    (static-analysis . "CodeQL enabled")
    (dependency-updates . "Dependabot configured")
    (vulnerability-disclosure . "SECURITY.md complete")
    (rfc9116 . "security.txt present")
    (git-hooks . "pre-commit and pre-push available")
    (secrets-scanning . "CI check implemented")))

;; ============================================================================
;; Component Status
;; ============================================================================

(define component-status
  '((complete . ("Idris Engine" "Build System" "Security" "Documentation" "Configuration" "Hooks"))
    (in-progress . ("MCP Adapter"))
    (planned . ("Extended Markdown" "Plugin System" "Theme System"))))

;; ============================================================================
;; State Summary
;; ============================================================================

(define state-summary
  '((project . "ddraig-ssg")
    (language . "Idris 2")
    (idris-version . ">= 0.8.0")
    (completion . 90)
    (blockers . 0)
    (high-priority-issues . 0)
    (security-issues . 0)
    (components-complete . 6)
    (components-in-progress . 1)
    (updated . "2025-12-17")))
