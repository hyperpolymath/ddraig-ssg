;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 hyperpolymath
;; META.scm - Meta-level information for ddraig-ssg

(meta
  (media-type "application/meta+scheme")
  (version "1.0")

  (architecture-decisions
    (adr-001
      (title "Use Idris 2 for dependent types")
      (status "accepted")
      (date "2024-12-29")
      (context "Exploring how dependent types can ensure template correctness")
      (decision "Implement SSG in Idris 2 to leverage full dependent type system")
      (consequences
        (positive
          ("Types can depend on values - encode invariants directly")
          ("Proofs of correctness checked at compile time")
          ("If it compiles, certain classes of bugs are impossible"))
        (negative
          ("Steep learning curve for non-type-theorists")
          ("Idris 2 ecosystem smaller than mainstream languages")
          ("Compilation can be slower due to proof checking"))))
    (adr-002
      (title "Schema-to-type derivation")
      (status "accepted")
      (date "2024-12-29")
      (context "Content schemas should be enforced at type level")
      (decision "Derive Idris types from content schemas at compile time")
      (consequences
        (positive
          ("Schema violations caught before runtime")
          ("Type errors provide meaningful diagnostics")
          ("Refactoring has compiler support"))
        (negative
          ("Schema changes require recompilation")
          ("Type-level programming complexity"))))
    (adr-003
      (title "Proof-carrying transformations")
      (status "accepted")
      (date "2024-12-29")
      (context "Template transformations should preserve validity")
      (decision "Encode transformation correctness as proof obligations")
      (consequences
        (positive
          ("Compiler verifies transformation safety")
          ("Documentation through types")
          ("Mathematical confidence in correctness"))
        (negative
          ("Proof writing can be tedious")
          ("Some proofs may require lemmas")))))

  (development-practices
    (code-style
      (formatter "Idris 2 built-in formatting")
      (naming "camelCase for functions, PascalCase for types")
      (modules "One module per concept, clear export lists")
      (proofs "Separate proof modules where complex"))
    (testing
      (approach "Type-driven development - types are tests")
      (property-tests "QuickCheck-style for runtime properties")
      (location "test/"))
    (versioning
      (scheme "semantic")
      (changelog "CHANGELOG.adoc"))
    (documentation
      (format "AsciiDoc")
      (literate-source "Extensive comments explaining types")
      (examples "examples/"))
    (branching
      (strategy "trunk-based")
      (main-branch "main")))

  (design-rationale
    (why-idris
      "Idris 2 is a general-purpose language with first-class dependent types. Unlike 
       Haskell or ML, types in Idris can depend on values. This means we can express 
       'a template with exactly three slots' or 'a document with valid schema' as 
       types that the compiler enforces. If the code compiles, the invariants hold.")
    (why-dependent-types-for-ssg
      "Static site generators often have subtle bugs: missing template variables, 
       schema violations, broken links. With dependent types, we can encode these 
       requirements in the type system. The compiler becomes a proof checker, 
       rejecting invalid sites before they're ever generated.")
    (why-welsh-name
      "Ddraig (pronounced roughly 'thraig') is Welsh for dragon - the symbol on 
       the Welsh flag. The name reflects the project's bite: bugs that slip past 
       other type systems are caught by ddraig's dependent types. A dragon guards 
       the codebase.")))
