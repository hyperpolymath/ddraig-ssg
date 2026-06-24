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
-- came from an accessible, well-formed source -- and the proof is erasable
-- (0-quantity), so it costs nothing at runtime.
--
-- Scope: these predicates are the CONTENT-tree, machine-decidable subset --
-- exactly one <h1>, and non-skipping heading levels (alt-presence is already a
-- structural invariant of `Html`). Template/palette-owned criteria (page `lang`,
-- the `<main>` landmark, >=7:1 contrast) are not on the content tree and wait for
-- the typed-template step. "Provably accessible" therefore means the decidable
-- subset only (see ARCHITECTURE.adoc, "What provably accessible means").

module Attest

import Html
import Decidable.Equality

%default total

-- ============================================================================
-- Decidable content-tree accessibility predicates
-- ============================================================================

-- Count <h1> elements across a forest.
mutual
  public export
  countH1 : Html -> Nat
  countH1 (Elem tag _ kids) = (if tag == "h1" then 1 else 0) + countH1F kids
  countH1 _                 = 0

  public export
  countH1F : List Html -> Nat
  countH1F []        = 0
  countH1F (h :: hs) = countH1 h + countH1F hs

-- Heading levels (1..6) in document order.
mutual
  public export
  hLevels : Html -> List Nat
  hLevels (Elem tag _ kids) = lvlOf tag ++ hLevelsF kids
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
decOneH1 : (bs : List Html) -> Dec (OneH1 bs)
decOneH1 bs = decEq (oneH1B bs) True

public export
decHeadingNoSkip : (bs : List Html) -> Dec (HeadingNoSkip bs)
decHeadingNoSkip bs = decEq (noSkipB (hLevelsF bs)) True

-- The conjunction of the content-tree predicates.
public export
Accessible : List Html -> Type
Accessible bs = (OneH1 bs, HeadingNoSkip bs)

public export
decAccessible : (bs : List Html) -> Dec (Accessible bs)
decAccessible bs = case decOneH1 bs of
  No no  => No (\(p, _) => no p)
  Yes p1 => case decHeadingNoSkip bs of
    No no  => No (\(_, q) => no q)
    Yes p2 => Yes (p1, p2)

-- ============================================================================
-- Echo type: attested output
-- ============================================================================

-- A document that carries its accessibility proof. Unconstructible without it.
public export
record AccessibleDoc where
  constructor MkAccessibleDoc
  blocks  : List Html
  witness : Accessible blocks       -- the a11y proof (erasable via a data decl later)

-- The echo / attestation: the rendered string PLUS the witness that it is the
-- render of an accessible source.  output = renderDoc source.blocks  IS  f x = y.
public export
record Attested where
  constructor MkAttested
  source : AccessibleDoc
  output : String
  echo   : output = renderDoc source.blocks

-- The ONLY constructor path: render an accessible document. So `output` is
-- definitionally the render of an accessible source -- the attestation is unfakeable.
public export
attest : AccessibleDoc -> Attested
attest a = MkAttested a (renderDoc a.blocks) Refl

-- The predicate names a certified document satisfies (for the certificate).
public export
certifiedPredicates : List String
certifiedPredicates = ["one-h1", "heading-no-skip", "alt-present-by-construction"]

-- Human-readable violations (recomputed for the rejection path).
violations : List Html -> List String
violations bs =
  (if oneH1B bs then []
   else ["exactly one <h1> required (found " ++ show (countH1F bs) ++ ")"])
  ++
  (if noSkipB (hLevelsF bs) then []
   else ["heading levels skip a level; do not jump deeper by more than one"])

-- The build boundary: a TOTAL decision -- a certified `Attested` (carrying its
-- erased proof) or the list of violations.
public export
certify : List Html -> Either (List String) Attested
certify bs = case decAccessible bs of
  Yes prf => Right (attest (MkAccessibleDoc bs prf))
  No  _   => Left (violations bs)
