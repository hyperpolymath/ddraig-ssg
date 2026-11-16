-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Attest.idr - O3 echo-types: accessibility witnesses for rendered output.
--
-- The echo-type (ARCHITECTURE.adoc, obligation O3): an `Attested` value is a
-- rendered document string PAIRED WITH a proof that it is the render of a source
-- that satisfies a DECIDABLE accessibility predicate. It is exactly
--   Echo renderDoc out := (src ** out = renderDoc src.blocks)
-- refined so that `src` carries an accessibility proof. The only way to build an
-- `Attested` is to render an accessible document, so a certified page provably
-- came from a source that satisfies the predicates below. Both proofs are
-- record fields of quantity 0: they are checked at compile time and erased, so
-- they cost nothing at runtime.
--
-- Scope: these predicates are the CONTENT-tree, machine-decidable subset --
-- exactly one <h1>, non-skipping heading levels, and every image carrying alt
-- text (an `Img` carries a non-blank `Alt` by construction; an `UnlabelledImg`,
-- or an `Elem`/`Void` "img" without a non-blank alt attribute, fails). Tag
-- names are compared case-insensitively, as HTML does.
--
-- Not covered, and reported as such:
--   * `Raw` blocks (raw HTML passthrough) are opaque text. They are not
--     inspected, so a certificate says nothing about them; `countRaw` lets the
--     attestation file list how many each page has.
--   * Template/palette-owned criteria (page `lang`, the `<main>` landmark,
--     >=7:1 contrast) are not on the content tree and wait for the typed-
--     template step.
-- "Provably accessible" therefore means the decidable subset, over the typed
-- content only (see ARCHITECTURE.adoc, "What provably accessible means").

module Attest

import Html
import Data.Maybe
import Data.String
import Decidable.Equality

%default total

-- ============================================================================
-- Decidable content-tree accessibility predicates
-- ============================================================================

-- Tag names are case-insensitive in HTML.
tagIs : String -> String -> Bool
tagIs want tag = toLower tag == want

-- Count <h1> elements across a forest.
mutual
  public export
  countH1 : Html -> Nat
  countH1 (Elem tag _ kids) = (if tagIs "h1" tag then 1 else 0) + countH1F kids
  countH1 _                 = 0

  public export
  countH1F : List Html -> Nat
  countH1F []        = 0
  countH1F (h :: hs) = countH1 h + countH1F hs

-- Heading levels (1..6) in document order.
mutual
  public export
  hLevels : Html -> List Nat
  hLevels (Elem tag _ kids) = lvlOf (toLower tag) ++ hLevelsF kids
    where
      lvlOf : String -> List Nat
      lvlOf "h1" = [1]
      lvlOf "h2" = [2]
      lvlOf "h3" = [3]
      lvlOf "h4" = [4]
      lvlOf "h5" = [5]
      lvlOf "h6" = [6]
      lvlOf _    = []
  hLevels _ = []

  public export
  hLevelsF : List Html -> List Nat
  hLevelsF []        = []
  hLevelsF (h :: hs) = hLevels h ++ hLevelsF hs

-- A heading sequence "does not skip" when each level is at most one deeper than
-- the previous (shallower jumps by any amount are fine).
public export
noSkipB : List Nat -> Bool
noSkipB []               = True
noSkipB (_ :: [])        = True
noSkipB (a :: b :: rest) = (b <= S a) && noSkipB (b :: rest)

-- Images without alt text, by src. `Img` always has alt and `DecorativeImg` is
-- an explicit alt=""; an `UnlabelledImg`, or an <img> built as a generic
-- element without a non-blank alt attribute, is listed.
attrValue : String -> List Attr -> Maybe String
attrValue _ [] = Nothing
attrValue name ((k, v) :: rest) = if toLower k == name then Just v else attrValue name rest

bareImgTag : String -> List Attr -> List String
bareImgTag tag attrs =
  if tagIs "img" tag && maybe True (\a => trim a == "") (attrValue "alt" attrs)
     then [fromMaybe "" (attrValue "src" attrs)]
     else []

mutual
  public export
  unlabelled : Html -> List String
  unlabelled (UnlabelledImg src)   = [src]
  unlabelled (Elem tag attrs kids) = bareImgTag tag attrs ++ unlabelledF kids
  unlabelled (Void tag attrs)      = bareImgTag tag attrs
  unlabelled _                     = []

  public export
  unlabelledF : List Html -> List String
  unlabelledF []        = []
  unlabelledF (h :: hs) = unlabelled h ++ unlabelledF hs

-- Raw HTML blocks are not inspected; count them so the certificate can say so.
mutual
  public export
  countRaw : Html -> Nat
  countRaw (Raw _)           = 1
  countRaw (Elem _ _ kids)   = countRawF kids
  countRaw _                 = 0

  public export
  countRawF : List Html -> Nat
  countRawF []        = 0
  countRawF (h :: hs) = countRaw h + countRawF hs

public export
oneH1B : List Html -> Bool
oneH1B bs = countH1F bs == 1

public export
OneH1 : List Html -> Type
OneH1 bs = oneH1B bs = True

public export
HeadingNoSkip : List Html -> Type
HeadingNoSkip bs = noSkipB (hLevelsF bs) = True

public export
ImagesLabelled : List Html -> Type
ImagesLabelled bs = null (unlabelledF bs) = True

public export
decOneH1 : (bs : List Html) -> Dec (OneH1 bs)
decOneH1 bs = decEq (oneH1B bs) True

public export
decHeadingNoSkip : (bs : List Html) -> Dec (HeadingNoSkip bs)
decHeadingNoSkip bs = decEq (noSkipB (hLevelsF bs)) True

public export
decImagesLabelled : (bs : List Html) -> Dec (ImagesLabelled bs)
decImagesLabelled bs = decEq (null (unlabelledF bs)) True

-- The conjunction of the content-tree predicates.
public export
Accessible : List Html -> Type
Accessible bs = (OneH1 bs, HeadingNoSkip bs, ImagesLabelled bs)

public export
decAccessible : (bs : List Html) -> Dec (Accessible bs)
decAccessible bs = case decOneH1 bs of
  No no  => No (\(p, _, _) => no p)
  Yes p1 => case decHeadingNoSkip bs of
    No no  => No (\(_, q, _) => no q)
    Yes p2 => case decImagesLabelled bs of
      No no  => No (\(_, _, r) => no r)
      Yes p3 => Yes (p1, p2, p3)

-- ============================================================================
-- Echo type: attested output
-- ============================================================================

-- A document that carries its accessibility proof. Unconstructible without it;
-- the proof is erased (quantity 0).
public export
record AccessibleDoc where
  constructor MkAccessibleDoc
  blocks    : List Html
  0 witness : Accessible blocks

-- The echo / attestation: the rendered string PLUS the (erased) witness that it
-- is the render of an accessible source.  output = renderDoc source.blocks  IS  f x = y.
public export
record Attested where
  constructor MkAttested
  source : AccessibleDoc
  output : String
  0 echo : output = renderDoc source.blocks

-- The ONLY constructor path: render an accessible document. So `output` is
-- definitionally the render of an accessible source -- the attestation is unfakeable.
public export
attest : AccessibleDoc -> Attested
attest a = MkAttested a (renderDoc a.blocks) Refl

-- The predicate names a certified document satisfies (for the certificate).
public export
certifiedPredicates : List String
certifiedPredicates = ["one-h1", "heading-no-skip", "images-labelled", "alt-non-blank-by-construction"]

-- Human-readable violations (recomputed for the rejection path).
export
violations : List Html -> List String
violations bs =
  (if oneH1B bs then []
   else ["exactly one <h1> required (found " ++ show (countH1F bs) ++ ")"])
  ++
  (if noSkipB (hLevelsF bs) then []
   else ["heading levels skip a level; do not jump deeper by more than one"])
  ++
  map (\src => "image has no alt text: " ++ src
               ++ " (describe it, or mark a purely decorative image with {.decorative})")
      (unlabelledF bs)

-- The build boundary: a TOTAL decision -- a certified `Attested` (carrying its
-- erased proof) or the list of violations.
public export
certify : List Html -> Either (List String) Attested
certify bs = case decAccessible bs of
  Yes prf => Right (attest (MkAccessibleDoc bs prf))
  No  _   => Left (violations bs)

-- ============================================================================
-- Machine-checked examples (these are proofs: the module fails to compile if
-- any of them stops holding)
-- ============================================================================

-- (Whitespace-only alt text being rejected by `mkAlt` is checked by the
-- test-attest run instead: `trim` on a blank literal does not reduce at compile
-- time, so it cannot be stated as a Refl proof here.)

-- An <img> built as a generic element without alt is caught.
elemImgCaught : unlabelledF [Void "IMG" [("src", "x.png")]] = ["x.png"]
elemImgCaught = Refl

-- An <img> built as a generic element WITH alt is accepted.
elemImgWithAltOk : unlabelledF [Void "img" [("src", "x.png"), ("ALT", "a cat")]] = []
elemImgWithAltOk = Refl

-- Upper-case heading tags are counted.
upperH1Counted : countH1F [Elem "H1" [] [Text "Title"]] = 1
upperH1Counted = Refl

-- Raw blocks are counted, including inside elements.
rawCounted : countRawF [Raw "<b>x</b>", Elem "div" [] [Raw "<i>y</i>"]] = 2
rawCounted = Refl
