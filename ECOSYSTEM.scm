;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 hyperpolymath
;; ECOSYSTEM.scm - Project ecosystem positioning for ddraig-ssg

(ecosystem
  (version "1.0")
  (name "ddraig-ssg")
  (type "ssg-engine")
  (purpose "Exploring dependent types for provably correct static site generation")

  (position-in-ecosystem
    (role "satellite")
    (hub "poly-ssg-mcp")
    (category "theorem-prover-ssgs")
    (uniqueness "Full dependent types enabling compile-time proof of template correctness"))

  (related-projects
    (project
      (name "poly-ssg-mcp")
      (relationship "hub")
      (description "Central MCP orchestrator for all SSG engines")
      (integration "Provides ddraig adapter for unified SSG access"))
    (project
      (name "agda-ssg")
      (relationship "close-sibling")
      (description "Agda-based SSG")
      (shared-aspects ("dependent types" "proof-carrying code" "theorem prover heritage")))
    (project
      (name "lean-ssg")
      (relationship "sibling")
      (description "Lean 4 based SSG")
      (shared-aspects ("dependent types" "interactive theorem prover")))
    (project
      (name "coq-ssg")
      (relationship "sibling")
      (description "Coq-based SSG")
      (shared-aspects ("dependent types" "proof assistant")))
    (project
      (name "sparkle-ssg")
      (relationship "distant-sibling")
      (description "Gleam-based SSG")
      (shared-aspects ("functional paradigm" "BEAM runtime option"))
      (differences ("Gleam lacks dependent types"))))

  (what-this-is
    ("A static site generator written in Idris 2")
    ("A demonstration of dependent types in practical tooling")
    ("A proof-of-concept for type-level template validation")
    ("Named ddraig (Welsh: dragon) for its bite at compile time")
    ("Part of the poly-ssg theorem-prover language collection"))

  (what-this-is-not
    ("Not limited to type theory researchers")
    ("Not sacrificing usability for type safety")
    ("Not requiring formal verification expertise")
    ("Not just a research project - it generates real sites")))
