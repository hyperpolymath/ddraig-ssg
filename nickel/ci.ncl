# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
#
# ci.ncl — ddraig-ssg CI/CD configuration schemas
# Nickel configuration for GitHub Actions workflows

let ActionRef = {
  uses | String | doc "Action reference with SHA pin",
  with | { _ : String } | optional | doc "Action inputs",
} in

let Job = {
  name | String | optional,
  runs-on | String | default = "ubuntu-latest",
  steps | Array { _ : Dyn },
} in

let Workflow = {
  name | String,
  permissions | String | [| 'read-all, 'write-all |] | default = 'read-all,
  on | { _ : Dyn },
  jobs | { _ : Job },
} in

# SHA-pinned action references for supply chain security
let actions = {
  checkout = {
    v4 = "actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11",
  },
  setup_idris = {
    v1 = "idris-community/setup-idris@a32a5481bce5bcb57fec37a6fbd1d2d4dbbe0da9",
  },
  codeql_init = {
    v3 = "github/codeql-action/init@ea9e4e37992a54ee68a9571571f9a567d8f90f78",
  },
  codeql_analyze = {
    v3 = "github/codeql-action/analyze@ea9e4e37992a54ee68a9571571f9a567d8f90f78",
  },
} in

# CI workflow configuration
{
  Workflow,
  Job,
  ActionRef,
  actions,

  # Generate CI workflow
  ci_workflow = {
    name = "Idris 2 CI",
    permissions = 'read-all,
    on = {
      push = { branches = ["main"] },
      pull_request = { branches = ["main"] },
    },
    jobs = {
      build = {
        runs-on = "ubuntu-latest",
        steps = [
          { uses = actions.checkout.v4 },
          {
            name = "Set up Idris 2",
            uses = actions.setup_idris.v1,
            with = { version = "0.8.0" },
          },
          {
            name = "Build",
            run = "idris2 --build ddraig.ipkg",
          },
          {
            name = "Type Check",
            run = "idris2 --typecheck src/Ddraig.idr",
          },
        ],
      },
      language-check = {
        runs-on = "ubuntu-latest",
        steps = [
          { uses = actions.checkout.v4 },
          {
            name = "Verify Idris-only in src/",
            run = m%"
              echo "Checking for forbidden languages in src/..."
              forbidden=$(find src/ -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.hs" \) 2>/dev/null || true)
              if [ -n "$forbidden" ]; then
                echo "ERROR: Found forbidden language files in src/:"
                echo "$forbidden"
                exit 1
              fi
              echo "OK: Only Idris files in src/"
            "%,
          },
        ],
      },
    },
  },

  # Validation
  validate_workflow = fun w => w & Workflow,
}
