;;; STATE.scm — ddraig-ssg
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell

(define metadata
  '((version . "1.0.0")
    (updated . "2025-12-16")
    (project . "ddraig-ssg")
    (required-language . "Idris")))

(define language-enforcement
  '((primary-language . "Idris")
    (file-extension . ".idr")
    (interpreter . "Idris2")
    (forbidden-languages . ("Python" "JavaScript" "TypeScript" "Ruby" "Go"))
    (rationale . "ddraig-ssg is the DEFINITIVE Idris static site generator. It MUST be written entirely in Idris. No other implementation languages are permitted.")
    (enforcement . "strict")))

(define current-position
  '((phase . "v1.0 - Idris Implementation Complete")
    (overall-completion . 100)
    (components ((Idris-engine ((status . "complete") (completion . 100)))
                 (mcp-adapter ((status . "pending") (language . "ReScript") (completion . 0)))))))

(define blockers-and-issues
  '((critical ())
    (high-priority ())))

(define critical-next-actions
  '((immediate (("Connect MCP adapter in ReScript" . high)))))

(define state-summary
  '((project . "ddraig-ssg")
    (language . "Idris")
    (completion . 100)
    (blockers . 0)
    (updated . "2025-12-16")))
