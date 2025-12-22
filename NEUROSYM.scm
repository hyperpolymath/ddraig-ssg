;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
;;; NEUROSYM.scm — ddraig-ssg Neurosymbolic Configuration
;;;
;;; Defines the intersection of neural (AI-assisted) and symbolic (type-driven)
;;; reasoning for the ddraig-ssg project.

(define-module (ddraig-ssg neurosym)
  #:export (symbolic-core neural-augmentation integration-points
            type-driven-constraints proof-assistance
            hybrid-workflows verification-pipeline))

;; ============================================================================
;; Symbolic Core
;; ============================================================================

(define symbolic-core
  '((foundation . "Idris 2 dependent type system")
    (description . "The symbolic foundation of ddraig-ssg is the Idris 2 type system,
                    which provides compile-time guarantees through dependent types.")

    (symbolic-guarantees
      (("Type safety" . "All operations are type-checked at compile time")
       ("Totality" . "Functions can be proven total (covering all cases)")
       ("Termination" . "Recursive functions can be checked for termination")
       ("Refinement" . "Values can carry proofs of properties")))

    (type-hierarchy
      (("Frontmatter" . "Record type with string, list, and bool fields")
       ("ParserState" . "State machine for Markdown parsing")
       ("Template" . "HTML output with variable substitution")))

    (proofs-available
      (("Input validation" . "Frontmatter must have valid structure")
       ("Output well-formedness" . "Generated HTML is syntactically valid")
       ("State invariants" . "Parser state transitions are correct")))))

;; ============================================================================
;; Neural Augmentation
;; ============================================================================

(define neural-augmentation
  '((purpose . "AI assistance for development, not replacement of type system")

    (augmentation-areas
      (("Code generation" . "AI suggests Idris code that must type-check")
       ("Error diagnosis" . "AI explains type errors in natural language")
       ("Documentation" . "AI generates docs from type signatures")
       ("Test generation" . "AI proposes test cases based on types")
       ("Refactoring" . "AI suggests type-preserving transformations")))

    (boundaries
      (("AI cannot bypass types" . "All suggestions must compile")
       ("AI cannot weaken proofs" . "Totality/termination preserved")
       ("AI cannot change language" . "Idris-only enforcement")))

    (neural-tools
      (("Claude Code" . "Primary AI assistant")
       ("GitHub Copilot" . "Inline suggestions (with Idris support)")
       ("CodeQL" . "AI-powered security analysis")))))

;; ============================================================================
;; Integration Points
;; ============================================================================

(define integration-points
  '((symbolic-to-neural
      (description . "Where symbolic artifacts inform neural processing")
      (points
        (("Type signatures" . "AI reads types to understand intent")
         ("Compile errors" . "AI interprets and explains errors")
         ("Proof holes" . "AI suggests terms to fill type holes")
         ("Documentation" . "AI uses types to generate accurate docs"))))

    (neural-to-symbolic
      (description . "Where neural suggestions become symbolic artifacts")
      (points
        (("Code suggestions" . "AI output is type-checked by Idris")
         ("Test proposals" . "AI tests are verified to compile")
         ("Refactoring" . "AI changes must preserve types")
         ("Documentation" . "AI prose validated against actual behavior"))))

    (feedback-loop
      (description . "Continuous improvement cycle")
      (stages
        (("AI suggests" . "Neural generates candidate code")
         ("Idris checks" . "Symbolic verifies type correctness")
         ("Error feedback" . "Type errors inform AI refinement")
         ("Success" . "Type-correct code is accepted")
         ("Learning" . "Pattern informs future suggestions"))))))

;; ============================================================================
;; Type-Driven Constraints
;; ============================================================================

(define type-driven-constraints
  '((constraint-types
      (("Proof obligations" . "Types that require proofs to construct")
       ("Refinement types" . "Values constrained by predicates")
       ("Indexed types" . "Types parameterized by values")
       ("Linear types" . "Resources used exactly once")))

    (current-usage
      (("Frontmatter record" . "Structured data with known fields")
       ("ParserState" . "State machine with boolean flags")
       ("List operations" . "Standard list types with totality")))

    (future-potential
      (("Schema validation" . "Frontmatter schemas as types")
       ("HTML well-formedness" . "Indexed types for valid HTML")
       ("Template safety" . "Proofs that all variables are bound")
       ("Path safety" . "File paths as verified strings")))))

;; ============================================================================
;; Proof Assistance
;; ============================================================================

(define proof-assistance
  '((ai-assisted-proofs
      (description . "AI helps construct proofs that Idris verifies")
      (workflow
        (("Identify goal" . "What property needs proving?")
         ("AI suggests" . "Propose proof term or strategy")
         ("Type check" . "Idris verifies proof is valid")
         ("Refine" . "Iterate if proof doesn't type-check"))))

    (proof-patterns
      (("Induction" . "Prove for base case and inductive step")
       ("Case analysis" . "Cover all constructors")
       ("Rewriting" . "Use equalities to transform goals")
       ("Contradiction" . "Derive False from inconsistent assumptions")))

    (tools
      (("Idris2 holes" . "?hole syntax for incremental proofs")
       ("Type-driven search" . ":search command for term finding")
       ("AI explanation" . "Natural language proof guidance")))))

;; ============================================================================
;; Hybrid Workflows
;; ============================================================================

(define hybrid-workflows
  '((development-workflow
      (name . "Type-AI Development Cycle")
      (steps
        (("Define types" . "Human/AI writes type signatures")
         ("AI generates" . "AI proposes implementation")
         ("Types verify" . "Idris checks correctness")
         ("AI explains" . "AI documents the code")
         ("Human reviews" . "Final approval")))
      (balance . "Types ensure correctness; AI accelerates development"))

    (debugging-workflow
      (name . "Neurosymbolic Debugging")
      (steps
        (("Error occurs" . "Idris reports type error")
         ("AI interprets" . "AI explains error in plain English")
         ("AI suggests" . "AI proposes fix candidates")
         ("Types verify" . "Only type-correct fixes accepted")
         ("Human confirms" . "Developer approves fix")))
      (balance . "Symbolic error; Neural interpretation"))

    (documentation-workflow
      (name . "Type-Derived Documentation")
      (steps
        (("Extract types" . "Parse type signatures")
         ("AI describes" . "Generate natural language docs")
         ("Verify accuracy" . "Check docs match behavior")
         ("Publish" . "Include in project documentation")))
      (balance . "Types are source of truth; AI makes them accessible"))))

;; ============================================================================
;; Verification Pipeline
;; ============================================================================

(define verification-pipeline
  '((stages
      (("parsing" . "Idris parses source, checks syntax")
       ("type-checking" . "Idris verifies types")
       ("totality-checking" . "Idris verifies coverage and termination")
       ("code-generation" . "Idris compiles to Chez Scheme")
       ("runtime-testing" . "Tests verify actual behavior")))

    (ai-integration-per-stage
      (("parsing" . "AI can suggest syntax fixes")
       ("type-checking" . "AI explains errors, suggests fixes")
       ("totality-checking" . "AI helps cover missing cases")
       ("code-generation" . "None - fully automatic")
       ("runtime-testing" . "AI generates test cases")))

    (trust-model
      (("Idris compiler" . "Fully trusted (formal foundations)")
       ("AI suggestions" . "Untrusted until type-checked")
       ("Human decisions" . "Trusted for non-formal properties")))

    (verification-properties
      (("Type correctness" . "Guaranteed by Idris")
       ("Totality" . "Optional, enabled per function")
       ("Termination" . "Optional, for total functions")
       ("Functional correctness" . "Via dependent types and tests")))))
