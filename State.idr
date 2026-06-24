-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- State.idr - total validator for a2ml STATE descriptiles.
--
-- O1 of the verified-publishing stack (ARCHITECTURE.adoc): a TOTAL decision over
-- whether a STATE descriptile conforms to the STATE schema. The parser is the
-- untrusted, `covering` side of the trust boundary; `validateState` is `total`,
-- so "this descriptile is schema-valid" is decided by a function that cannot
-- diverge. This is "parse untrusted, then validate totally" in miniature.
--
-- NB: the STATE format is the TOML-like 6a2 descriptile syntax ([section] +
-- key = value), as used by .machine_readable/6a2/STATE.a2ml in the standards
-- repo -- distinct from the A2ML *markup* language (src/A2ML there). The schema
-- below is codified from the canonical STATE.a2ml; the exact required-key and
-- enum choices are documented in the PR for confirmation.

module State

import Data.List
import Data.String

%default covering

-- ============================================================================
-- Parsed model
-- ============================================================================

||| A parsed STATE descriptile: sections in source order, each a list of
||| (key, scalar-value). Array/complex values are recorded as present with an
||| empty scalar; only scalars (enums, numbers) carry a meaningful value.
public export
record StateDoc where
  constructor MkStateDoc
  sections : List (String, List (String, String))

-- ============================================================================
-- Parser (untrusted side of the boundary; covering)
-- ============================================================================

-- Strip an inline `# ...` comment that is not inside a double-quoted string.
stripInlineComment : String -> String
stripInlineComment s = pack (go (unpack s) False)
  where
    go : List Char -> Bool -> List Char
    go [] _ = []
    go ('"' :: cs) q = '"' :: go cs (not q)
    go ('#' :: cs) False = []
    go (c :: cs) q = c :: go cs q

isComment : String -> Bool
isComment t = isPrefixOf "#" t

isSectionHeader : String -> Bool
isSectionHeader t = isPrefixOf "[" t && isSuffixOf "]" t

sectionName : String -> String
sectionName t = trim (substr 1 (length t `minus` 2) t)

-- Strip surrounding quotes ("""triple""" or "double"); leave numbers/arrays.
unquote : String -> String
unquote v =
  if isPrefixOf "\"\"\"" v && isSuffixOf "\"\"\"" v && length v >= 6
     then substr 3 (length v `minus` 6) v
  else if isPrefixOf "\"" v && isSuffixOf "\"" v && length v >= 2
     then substr 1 (length v `minus` 2) v
  else v

-- `key = value` -> (key, scalar, opensMultiLineArray?)
parseKeyLine : String -> Maybe (String, String, Bool)
parseKeyLine t =
  case break (== '=') (unpack t) of
    (_, []) => Nothing
    (kChars, (_ :: vChars)) =>
      let key = trim (pack kChars)
          rawV = trim (stripInlineComment (pack vChars))
      in if key == "" then Nothing
         else if isPrefixOf "[" rawV && not (isSuffixOf "]" rawV)
                 then Just (key, "", True)            -- multi-line array opener
                 else Just (key, unquote rawV, False)

-- Drop lines until a line whose trimmed form is "]" (array body skip).
skipArray : List String -> List String
skipArray [] = []
skipArray (l :: ls) = if trim l == "]" then ls else skipArray ls

-- Collect (key, value) pairs until the next [header] or EOF.
collectKeys : List String -> (List (String, String), List String)
collectKeys [] = ([], [])
collectKeys (l :: ls) =
  let t = trim l in
  if t == "" || isComment t then collectKeys ls
  else if isSectionHeader t then ([], l :: ls)
  else case parseKeyLine t of
         Just (k, v, ml) =>
           let ls' = if ml then skipArray ls else ls
               (more, rest) = collectKeys ls'
           in ((k, v) :: more, rest)
         Nothing => collectKeys ls

parseSections : List String -> List (String, List (String, String))
parseSections [] = []
parseSections (l :: ls) =
  if isSectionHeader (trim l)
     then let (pairs, rest) = collectKeys ls
          in (sectionName (trim l), pairs) :: parseSections rest
     else parseSections ls

export
parseState : String -> StateDoc
parseState content = MkStateDoc (parseSections (lines content))

-- ============================================================================
-- Schema (codified from the canonical STATE.a2ml)
-- ============================================================================

-- (section, required keys). Every key present in the canonical STATE.a2ml is
-- treated as REQUIRED; relax in review if any should be OPTIONAL.
schema : List (String, List String)
schema =
  [ ("metadata",              ["project", "version", "last-updated", "status", "session"])
  , ("project-context",       ["name", "purpose", "completion-percentage"])
  , ("position",              ["phase", "maturity"])
  , ("route-to-mvp",          ["milestones"])
  , ("blockers-and-issues",   ["issues"])
  , ("critical-next-actions", ["actions"])
  , ("maintenance-status",    ["last-run-utc", "last-result"])
  ]

-- (section, key, closed allowed-value set).
-- NB: `phase` includes "pre-release" because the canonical STATE.a2ml uses it,
-- though that file's own inline comment lists only the other five -- flagged in
-- the PR for reconciliation.
enums : List (String, String, List String)
enums =
  [ ("position", "phase",    ["design", "implementation", "testing", "maintenance", "archived", "pre-release"])
  , ("position", "maturity", ["experimental", "alpha", "beta", "production", "lts"])
  , ("maintenance-status", "last-result", ["unknown", "pass", "warn", "fail"])
  ]

-- ============================================================================
-- Validator (total -- this is the O1 decision)
-- ============================================================================

total
sectionKeys : StateDoc -> String -> Maybe (List (String, String))
sectionKeys (MkStateDoc secs) name = lookup name secs

total
keyValue : StateDoc -> String -> String -> Maybe String
keyValue doc sec key = sectionKeys doc sec >>= lookup key

-- An integer 0..100, no cast needed: digits only, and either <= 2 digits
-- (0..99) or exactly "100".
total
isPct : String -> Bool
isPct v =
  let cs = unpack v in
  cs /= [] && all isDigit cs && (length cs <= 2 || v == "100")

total
checkRequired : StateDoc -> (String, List String) -> List String
checkRequired doc (sec, keys) =
  case sectionKeys doc sec of
    Nothing  => ["missing section [" ++ sec ++ "]"]
    Just kvs => mapMaybe (\k => case lookup k kvs of
                                  Just _  => Nothing
                                  Nothing => Just ("[" ++ sec ++ "] missing key: " ++ k)) keys

total
checkEnum : StateDoc -> (String, String, List String) -> List String
checkEnum doc (sec, key, allowed) =
  case keyValue doc sec key of
    Nothing => []                       -- presence is checkRequired's job
    Just v  => if v `elem` allowed
                  then []
                  else ["[" ++ sec ++ "] " ++ key ++ " = \"" ++ v ++ "\" not in {"
                         ++ concat (intersperse ", " allowed) ++ "}"]

total
checkPct : StateDoc -> List String
checkPct doc =
  case keyValue doc "project-context" "completion-percentage" of
    Nothing => []
    Just v  => if isPct v then []
               else ["[project-context] completion-percentage must be an integer 0..100, got: " ++ v]

||| The total schema-validity decision: the list of violations.
||| An empty list means the descriptile is schema-valid.
export total
validateState : StateDoc -> List String
validateState doc =
  concatMap (checkRequired doc) schema
    ++ concatMap (checkEnum doc) enums
    ++ checkPct doc

||| Total boolean validity (empty violation list).
export total
isValid : StateDoc -> Bool
isValid doc = null (validateState doc)
