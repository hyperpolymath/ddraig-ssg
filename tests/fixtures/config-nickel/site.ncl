# SPDX-License-Identifier: MPL-2.0
# A site configuration written in Nickel. ddraig.toml beside it is its export:
#   nickel export --format toml site.ncl
{
  site = {
    title = "Ddraig",
    base_url = "https://hyperpolymath.github.io/ddraig-ssg",
    language = "en",
  },
  menus = {
    main = [
      { name = "Home", url = "/" },
      { name = "About", url = "/about.html" },
    ],
  },
  extra = { github = "https://github.com/hyperpolymath/ddraig-ssg", year = 2026, tags = ["a", "b"] },
}
