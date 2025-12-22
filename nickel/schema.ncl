# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
#
# schema.ncl — ddraig-ssg type schemas
# Nickel schemas for configuration validation

# Frontmatter schema (mirrors Idris Frontmatter record)
let Frontmatter = {
  title | String | doc "Page title",
  date | String | optional | doc "Publication date (ISO 8601)",
  tags | Array String | default = [] | doc "Content tags",
  draft | Bool | default = false | doc "Draft status",
  template | String | default = "default" | doc "Template to use",
  author | String | optional | doc "Content author",
  description | String | optional | doc "Meta description",
  slug | String | optional | doc "Custom URL slug",
} in

# Site configuration schema
let SiteConfig = {
  title | String | doc "Site title",
  base_url | String | doc "Base URL for the site",
  language | String | default = "en" | doc "Site language",
  description | String | optional | doc "Site description",

  build = {
    output_dir | String | default = "output",
    content_dir | String | default = "content",
    template_dir | String | default = "templates",
    static_dir | String | default = "static",
    clean_urls | Bool | default = true,
    minify_html | Bool | default = false,
  },

  frontmatter = {
    required_fields | Array String | default = ["title"],
    date_format | String | default = "%Y-%m-%d",
  },
} in

# Template variable schema
let TemplateVars = {
  title | String,
  date | String | optional,
  content | String,
  tags | Array String | default = [],
  site = {
    title | String,
    base_url | String,
  },
} in

# Export schemas
{
  Frontmatter,
  SiteConfig,
  TemplateVars,

  # Validation functions
  validate_frontmatter = fun fm =>
    fm & Frontmatter,

  validate_site_config = fun cfg =>
    cfg & SiteConfig,

  # Default configurations
  defaults = {
    frontmatter = {
      title = "",
      tags = [],
      draft = false,
      template = "default",
    },
    site = {
      title = "My Site",
      base_url = "https://example.com",
      language = "en",
      build = {
        output_dir = "output",
        content_dir = "content",
        template_dir = "templates",
        static_dir = "static",
        clean_urls = true,
        minify_html = false,
      },
    },
  },
}
