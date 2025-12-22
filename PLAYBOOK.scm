;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
;;; PLAYBOOK.scm — ddraig-ssg Operational Playbook

(define-module (ddraig-ssg playbook)
  #:export (build-procedures test-procedures deployment-procedures
            troubleshooting emergency-procedures maintenance))

;; ============================================================================
;; Build Procedures
;; ============================================================================

(define build-procedures
  '((standard-build
      (description . "Standard development build")
      (prerequisites . ("Idris2 >= 0.8.0" "Pack package manager"))
      (steps
        (("Navigate to src/" . "cd src/")
         ("Build with Idris2" . "idris2 --build ddraig.ipkg")
         ("Verify output" . "ls -la build/exec/ddraig")))
      (expected-output . "Compiled executable at build/exec/ddraig")
      (common-issues
        (("Missing Idris2" . "Install via Pack: pack install idris2")
         ("Missing .ipkg" . "Ensure ddraig.ipkg exists in project root"))))

    (clean-build
      (description . "Clean and rebuild from scratch")
      (steps
        (("Remove build artifacts" . "rm -rf src/build/")
         ("Clear type cache" . "rm -rf src/build/ttc/")
         ("Rebuild" . "idris2 --build ddraig.ipkg")))
      (when-to-use . "After major changes or when seeing stale type errors"))

    (adapter-build
      (description . "Build ReScript MCP adapter")
      (directory . "adapters/")
      (prerequisites . ("Node.js >= 18" "npm"))
      (steps
        (("Install dependencies" . "npm install")
         ("Build ReScript" . "npm run build")
         ("Verify output" . "ls -la src/*.mjs")))
      (output . "ES6 modules in adapters/src/"))))

;; ============================================================================
;; Test Procedures
;; ============================================================================

(define test-procedures
  '((unit-tests
      (description . "Run unit tests")
      (commands
        (("Markdown parsing" . "./build/exec/ddraig test-markdown")
         ("Frontmatter parsing" . "./build/exec/ddraig test-frontmatter")
         ("Full pipeline" . "./build/exec/ddraig test-full")))
      (expected . "All tests should print expected HTML output"))

    (type-check
      (description . "Type check without full build")
      (command . "idris2 --typecheck src/Ddraig.idr")
      (purpose . "Fast feedback on type errors"))

    (integration-test
      (description . "End-to-end site generation")
      (steps
        (("Create test content" . "echo '---\ntitle: Test\n---\n# Hello' > test.md")
         ("Run SSG" . "./build/exec/ddraig build test.md")
         ("Verify output" . "cat output/test.html")))
      (cleanup . "rm -rf test.md output/"))

    (language-check
      (description . "Verify no forbidden languages in src/")
      (command . "find src/ -type f \\( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.hs' \\)")
      (expected . "No output (empty result)")
      (failure-action . "Remove any non-Idris files from src/"))))

;; ============================================================================
;; Deployment Procedures
;; ============================================================================

(define deployment-procedures
  '((release-checklist
      (pre-release
        (("Update CHANGELOG.md" . "Add release notes")
         ("Update version in manifest.json" . "Bump version number")
         ("Run all tests" . "just test-all")
         ("Verify language compliance" . "just lint-language")
         ("Check security" . "just security-audit")))
      (release
        (("Tag release" . "git tag -a vX.Y.Z -m 'Release vX.Y.Z'")
         ("Push tag" . "git push origin vX.Y.Z")
         ("Create GitHub release" . "gh release create vX.Y.Z")))
      (post-release
        (("Verify CI passed" . "Check GitHub Actions")
         ("Update documentation" . "If needed")
         ("Announce" . "GitHub Discussions"))))

    (ci-deployment
      (trigger . "Push to main or PR to main")
      (stages
        (("checkout" . "Clone repository")
         ("setup-idris" . "Install Idris 2 v0.8.0")
         ("build" . "Compile with idris2")
         ("type-check" . "Verify types")
         ("language-check" . "Enforce Idris-only policy")))
      (artifacts . "None (library project)"))))

;; ============================================================================
;; Troubleshooting Guide
;; ============================================================================

(define troubleshooting
  '((build-failures
      (("Idris2 not found"
         (symptom . "Command 'idris2' not found")
         (cause . "Idris2 not installed or not in PATH")
         (solution . "Install via Pack: curl -sSL https://raw.githubusercontent.com/stefan-hoeck/pack/main/install.bash | bash && pack install idris2"))
       ("Type mismatch errors"
         (symptom . "Can't unify X with Y")
         (cause . "Type error in code")
         (solution . "Check the specific line and ensure types align"))
       ("Missing module"
         (symptom . "Module X not found")
         (cause . "Missing dependency or incorrect import")
         (solution . "Verify import paths and dependencies in .ipkg"))))

    (runtime-failures
      (("Executable not found"
         (symptom . "./build/exec/ddraig: No such file")
         (cause . "Build not run or failed")
         (solution . "Run: idris2 --build ddraig.ipkg"))
       ("Permission denied"
         (symptom . "Permission denied when running executable")
         (cause . "Executable bit not set")
         (solution . "chmod +x build/exec/ddraig"))))

    (adapter-failures
      (("npm install fails"
         (symptom . "npm ERR!")
         (cause . "Network issues or incompatible Node version")
         (solution . "Use Node 18+, check network, clear npm cache"))
       ("ReScript build fails"
         (symptom . "rescript: command not found or compilation errors")
         (cause . "ReScript not installed or syntax error")
         (solution . "npm install && check src/*.res syntax"))))))

;; ============================================================================
;; Emergency Procedures
;; ============================================================================

(define emergency-procedures
  '((security-incident
      (description . "Suspected security vulnerability discovered")
      (immediate-actions
        (("Do not disclose publicly" . "Keep details private")
         ("Contact security team" . "security@hyperpolymath.org")
         ("Document timeline" . "Record when discovered and by whom")))
      (escalation
        (("Critical/High" . "Immediate patch release")
         ("Medium" . "Include in next release")
         ("Low" . "Schedule for future release"))))

    (broken-main
      (description . "Main branch is broken")
      (immediate-actions
        (("Identify breaking commit" . "git bisect or review recent commits")
         ("Revert if simple" . "git revert <commit>")
         ("Hotfix branch if complex" . "git checkout -b hotfix/fix-main")))
      (prevention . "Always run CI before merging"))

    (data-loss
      (description . "Git history or content lost")
      (recovery
        (("Check reflog" . "git reflog")
         ("Recover commits" . "git checkout <sha>")
         ("Contact GitHub support" . "If pushed content lost"))))))

;; ============================================================================
;; Maintenance Procedures
;; ============================================================================

(define maintenance
  '((dependency-updates
      (frequency . "weekly via Dependabot")
      (review-process
        (("Check Dependabot PRs" . "Review security implications")
         ("Test locally" . "Pull PR branch and run tests")
         ("Merge if passing" . "Squash and merge"))))

    (security-audit
      (frequency . "weekly via CodeQL")
      (manual-checks
        (("Review .gitignore" . "Ensure no secrets exposed")
         ("Check dependencies" . "npm audit in adapters/")
         ("Review GitHub Actions" . "Ensure SHA-pinned"))))

    (documentation-review
      (frequency . "per release")
      (checklist
        (("README current" . "Reflects actual features")
         ("CHANGELOG updated" . "All changes documented")
         ("ROADMAP accurate" . "Reflects current priorities"))))))
