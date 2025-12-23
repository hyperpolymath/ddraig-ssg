# Ddraig SSG

[![CI](https://github.com/hyperpolymath/ddraig-ssg/actions/workflows/ci.yml/badge.svg)](https://github.com/hyperpolymath/ddraig-ssg/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Language: Idris 2](https://img.shields.io/badge/Language-Idris%202-blue.svg)](https://www.idris-lang.org/)

> Dependently typed static site generator in Idris 2

**Ddraig** (Welsh for "Dragon") uses dependent types to breathe fire into your static sites. Types that prove your templates are valid.

## Features

- 🐉 Dependent types for compile-time guarantees
- 📝 Markdown parsing with inline formatting
- 📋 YAML frontmatter extraction
- 🎨 Template engine with placeholder substitution
- 🔒 Type-safe by design

## Installation

```bash
# Install Idris 2
# See: https://idris2.readthedocs.io/en/latest/tutorial/starting.html

# Compile
idris2 Ddraig.idr -o ddraig
```

## Usage

```bash
./build/exec/ddraig test-markdown
./build/exec/ddraig test-frontmatter
./build/exec/ddraig test-full
```

## Why Idris 2?

- **Dependent types**: Prove properties at compile time
- **Totality checking**: Functions that always terminate
- **First-class types**: Types are values, values are types

## Part of poly-ssg

This is one of 12 polyglot static site generators. See [poly-ssg](https://github.com/hyperpolymath/poly-ssg) for the full collection.

## License

MIT © [hyperpolymath](https://github.com/hyperpolymath)

## Topics

`static-site-generator` `ssg` `idris` `idris2` `dependent-types` `functional` `type-safe` `polyglot`
