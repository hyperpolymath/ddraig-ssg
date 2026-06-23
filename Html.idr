-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Html.idr - Ddraig's typed, correct-by-construction HTML core.
--
-- This is the first load-bearing theorem of the "proof end" of the stack
-- (see ARCHITECTURE.adoc, obligation O2 plus a fragment of O3):
--
--   * `render` is TOTAL: every value of `Html` maps to a String. There is no
--     partial path and no "should-not-happen" guard. (O2: well-formedness.)
--
--   * An `Img` node CANNOT be constructed without a non-empty `Alt`. WCAG
--     1.1.1 "images carry alt text" is therefore an invariant of the AST,
--     enforced by the type-checker, not a lint that runs afterwards.
--     (O3 fragment: alt *presence* is decidable; alt *meaningfulness* stays
--     author-owned -- see ARCHITECTURE.adoc "What provably accessible means".)
--
-- Text content is escaped on render; raw passthrough is an explicit, named
-- constructor so the one trust boundary in the output is visible in source.

module Html

import Data.So
import Data.String

%default total

-- ============================================================================
-- Alt text: non-empty by construction
-- ============================================================================

||| Alternative text for an image. `MkAlt` is inhabited only when its argument
||| is statically non-empty: the erased `So (text /= "")` witness carries the
||| proof and costs nothing at runtime. `MkAlt ""` does not type-check, because
||| `So ("" /= "")` = `So False` is uninhabited.
public export
data Alt : Type where
  MkAlt : (text : String) -> {auto 0 prf : So (text /= "")} -> Alt

||| Recover the underlying text (total).
public export
altText : Alt -> String
altText (MkAlt t) = t

||| Boundary validator for alt text arriving from untrusted input (a2ml /
||| front-matter): a TOTAL decision that trims, rejects empty/whitespace-only,
||| and otherwise yields a proof-carrying `Alt`. This is "parse untrusted,
||| then validate totally" in miniature (ARCHITECTURE.adoc, trust boundaries).
public export
mkAlt : String -> Maybe Alt
mkAlt raw =
  let t = trim raw in
  case choose (t /= "") of
    Left  prf => Just (MkAlt t {prf})
    Right _   => Nothing

-- ============================================================================
-- HTML AST
-- ============================================================================

||| An attribute is a (name, value) pair; both are escaped on render.
public export
Attr : Type
Attr = (String, String)

||| A correct-by-construction HTML fragment. The set of constructors is the set
||| of shapes the renderer can emit; there is no constructor for malformed
||| markup, and (crucially) no way to build an image without alt text.
public export
data Html : Type where
  ||| Plain text -- HTML-escaped on render.
  Text : String -> Html
  ||| Trusted raw passthrough -- the ONE place output is not escaped.
  Raw  : String -> Html
  ||| A generic element: tag, attributes, children.
  Elem : (tag : String) -> List Attr -> List Html -> Html
  ||| An image: src plus a MANDATORY non-empty alt. Cannot be built otherwise.
  Img  : (src : String) -> Alt -> Html
  ||| A decorative image: explicitly empty alt (WCAG: decorative images take
  ||| alt=""). Kept distinct from `Img` so the "informative images carry
  ||| non-empty alt" invariant stays exact -- decorative is a deliberate,
  ||| visible choice, never an accidental empty `Img`.
  DecorativeImg : (src : String) -> Html

-- ============================================================================
-- Rendering (total)
-- ============================================================================

escape : String -> String
escape s = concat (map esc (unpack s))
  where
    esc : Char -> String
    esc '<' = "&lt;"
    esc '>' = "&gt;"
    esc '&' = "&amp;"
    esc '"' = "&quot;"
    esc c   = singleton c

renderAttr : Attr -> String
renderAttr (k, v) = " " ++ escape k ++ "=\"" ++ escape v ++ "\""

-- `render` and `renderForest` are mutually recursive over the rose tree. The
-- recursion is structural (children are subterms), so the totality checker
-- accepts it without `assert_total` -- which matters: an `assert_total` here
-- would forfeit the very property this module exists to demonstrate.
mutual
  ||| Render an HTML fragment to a String. TOTAL.
  public export
  render : Html -> String
  render (Text s) = escape s
  render (Raw s)  = s
  render (Img src alt) =
    "<img src=\"" ++ escape src ++ "\" alt=\"" ++ escape (altText alt) ++ "\" />"
  render (DecorativeImg src) =
    "<img src=\"" ++ escape src ++ "\" alt=\"\" />"
  render (Elem tag attrs kids) =
    "<" ++ escape tag ++ concat (map renderAttr attrs) ++ ">"
      ++ renderForest kids
      ++ "</" ++ escape tag ++ ">"

  ||| Render a list of fragments in order. TOTAL.
  public export
  renderForest : List Html -> String
  renderForest []        = ""
  renderForest (h :: hs) = render h ++ renderForest hs

-- ============================================================================
-- Worked example (this type-checks)
-- ============================================================================

||| A figure with a captioned, alt-texted image. Compiles, because the alt is
||| non-empty.
public export
exampleOk : Html
exampleOk =
  Elem "figure" []
    [ Img "/dragon.png" (MkAlt "A red dragon breathing fire")
    , Elem "figcaption" [] [ Text "Ddraig -- types that breathe fire" ]
    ]

-- The counterexample below is left in a comment ON PURPOSE: it does NOT
-- type-check, which is the whole point of this module.
--
--   bad : Html
--   bad = Img "/dragon.png" (MkAlt "")
--
-- `So ("" /= "")` reduces to `So False`, which has no inhabitant, so there is
-- no proof for `auto` to find and the program is rejected at compile time.
