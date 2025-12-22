# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
#
# config.ncl — ddraig-ssg Nickel configuration
# Type-safe configuration for the Idris SSG

let Project = {
  name | String,
  version | String,
  language | String,
  license | String,
  description | String,
} in

let BuildConfig = {
  compiler | String,
  min_version | String,
  output_dir | String,
  entry_point | String,
} in

let LanguagePolicy = {
  primary | String,
  forbidden | Array String,
  exceptions | { [| String |] : String },
  enforcement | [| 'strict, 'warn, 'none |],
} in

# Project configuration
{
  project : Project = {
    name = "ddraig-ssg",
    version = "0.1.0",
    language = "Idris 2",
    license = "AGPL-3.0-or-later",
    description = "The DEFINITIVE Idris static site generator - types that breathe fire",
  },

  build : BuildConfig = {
    compiler = "idris2",
    min_version = "0.8.0",
    output_dir = "src/build/exec",
    entry_point = "src/Ddraig.idr",
  },

  language_policy : LanguagePolicy = {
    primary = "Idris",
    forbidden = ["Python", "JavaScript", "TypeScript", "Ruby", "Go", "Java", "Haskell"],
    exceptions = {
      adapters = "ReScript",
    },
    enforcement = 'strict,
  },

  paths = {
    src = "src/",
    adapters = "adapters/",
    output = "output/",
    content = "content/",
    templates = "templates/",
  },

  ci = {
    idris_version = "0.8.0",
    node_version = "18",
    actions_sha_pinned = true,
    codeql_enabled = true,
  },

  features = {
    markdown = true,
    frontmatter = true,
    templates = true,
    drafts = true,
    code_blocks = true,
    inline_formatting = true,
    syntax_highlighting = false,  # Planned
    latex = false,                # Planned
    mermaid = false,              # Planned
  },
}
