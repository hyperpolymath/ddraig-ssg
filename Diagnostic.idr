-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Diagnostic.idr - located, explained problem reports for ddraig.
--
-- Every problem ddraig reports goes through this module, so every message has
-- the same shape (format: DIAGNOSTICS.adoc):
--
--   error[DDR0003]: unknown command "biuld"
--     = help: did you mean "build"?
--     = help: run `ddraig --help` to list the commands
--
-- and, for a problem in a file, the file:line:column, the source line, and a
-- caret under the exact text:
--
--   error[DDR0105]: unknown key "titel" in [site]
--    --> ddraig.toml:3:1
--     |
--   3 | titel = "My site"
--     | ^^^^^ not a [site] key
--     |
--     = help: did you mean "title"?
--
-- Three guarantees, all checked by the type checker because the module is
-- %default total:
--
--   * Every `Code` has a stable identifier and an explanation for
--     `ddraig explain`: `codeId` and `explanation` are total functions over
--     `Code`, so a new code without an explanation does not compile.
--   * Rendering cannot fail or diverge, so reporting a problem can never itself
--     crash the build.
--   * Rendering is deterministic (stable sort, no clock, no environment), so
--     the messages are golden-tested like any other output (tests/golden/).

module Diagnostic

import Data.List
import Data.Maybe
import Data.String

%default total

-- ============================================================================
-- Codes: every reported problem has one, and every code has an explanation
-- ============================================================================

||| The kinds of problem ddraig reports. Ranges (DIAGNOSTICS.adoc): DDR00xx
||| command line and environment; DDR01xx site configuration; DDR02xx
||| templates; and so on, one hundred per area.
public export
data Code
  = BadSourceDateEpoch
  | SourceDirMissing
  | UnknownCommand
  | WrongArguments
  | UnknownCode
  | TomlSyntax
  | TomlUnsupported
  | TomlDuplicate
  | ConfigUnknownTable
  | ConfigUnknownKey
  | ConfigWrongType
  | ConfigBadValue
  | ConfigMenuEntry
  | ConfigUnreadable
  | TemplateUnknownVariable
  | TemplateNotText

||| Every code, in identifier order. Keep in step with `Code`: the
||| test-diagnostics subcommand checks that identifiers are unique and that
||| each one round-trips through `fromId`.
public export
allCodes : List Code
allCodes =
  [ BadSourceDateEpoch, SourceDirMissing, UnknownCommand, WrongArguments, UnknownCode
  , TomlSyntax, TomlUnsupported, TomlDuplicate, ConfigUnknownTable, ConfigUnknownKey
  , ConfigWrongType, ConfigBadValue, ConfigMenuEntry, ConfigUnreadable
  , TemplateUnknownVariable, TemplateNotText ]

||| The stable identifier printed in messages and accepted by `ddraig explain`.
||| Never reuse or renumber one: people search for them.
public export
codeId : Code -> String
codeId BadSourceDateEpoch      = "DDR0001"
codeId SourceDirMissing        = "DDR0002"
codeId UnknownCommand          = "DDR0003"
codeId WrongArguments          = "DDR0004"
codeId UnknownCode             = "DDR0005"
codeId TomlSyntax              = "DDR0101"
codeId TomlUnsupported         = "DDR0102"
codeId TomlDuplicate           = "DDR0103"
codeId ConfigUnknownTable      = "DDR0104"
codeId ConfigUnknownKey        = "DDR0105"
codeId ConfigWrongType         = "DDR0106"
codeId ConfigBadValue          = "DDR0107"
codeId ConfigMenuEntry         = "DDR0108"
codeId ConfigUnreadable        = "DDR0109"
codeId TemplateUnknownVariable = "DDR0201"
codeId TemplateNotText         = "DDR0202"

||| Look a code up by its identifier (exact match).
export
fromId : String -> Maybe Code
fromId s = case filter (\c => codeId c == s) allCodes of
             (c :: _) => Just c
             []       => Nothing

||| The longer explanation shown by `ddraig explain <code>`.
export
record Explanation where
  constructor MkExplanation
  heading : String        -- one line: what the code means
  details : List String   -- why it happens and how to fix it

||| Total over `Code`: a code without an explanation does not compile.
export
explanation : Code -> Explanation
explanation BadSourceDateEpoch = MkExplanation
  "SOURCE_DATE_EPOCH is not a whole number of seconds"
  [ "When SOURCE_DATE_EPOCH is set, ddraig uses it as the build date instead of"
  , "the clock, so the same sources always give the same output. See"
  , "https://reproducible-builds.org/specs/source-date-epoch/."
  , ""
  , "It must be a whole number of seconds since 1970-01-01 00:00 UTC, written with"
  , "digits only: no sign, spaces, or decimal point. For example:"
  , ""
  , "    SOURCE_DATE_EPOCH=1782086400 ddraig build site _site"
  , ""
  , "To use the current date instead, unset it or set it to the empty string."
  ]
explanation SourceDirMissing = MkExplanation
  "the source directory does not exist, or is not a directory"
  [ "`ddraig build <src> <out>` reads pages from <src>, which must be an existing"
  , "directory. A relative path is resolved from the directory you run ddraig in."
  , ""
  , "Check the spelling, and that you are in the directory you expect. If <src>"
  , "names a file, give the directory that contains it instead."
  ]
explanation UnknownCommand = MkExplanation
  "the first argument is not a ddraig command"
  [ "ddraig's first argument names what to do: build, clean, validate-state,"
  , "explain, --help or --version. `ddraig --help` lists them with their"
  , "arguments. When the name is close to a real command, the message suggests it."
  ]
explanation WrongArguments = MkExplanation
  "a command was given the wrong number of arguments"
  [ "Each command takes a fixed set of arguments; the message shows the one you"
  , "used. Arguments in [brackets] are optional. Quote paths that contain spaces,"
  , "so that the shell passes each one as a single argument."
  ]
explanation UnknownCode = MkExplanation
  "`ddraig explain` was given an identifier that is not a diagnostic code"
  [ "Diagnostic codes look like DDR0001. Run `ddraig explain` with no argument to"
  , "list every code with a one-line description."
  ]
explanation TomlSyntax = MkExplanation
  "a line of a TOML file is not valid TOML"
  [ "ddraig.toml and the files in data/ are TOML. Each line is a [table] header,"
  , "a key = value pair, a # comment, or blank. Strings are written in double"
  , "quotes (\"...\") or single quotes ('...') and must be closed on the same"
  , "line. The message points at the part that could not be read."
  , ""
  , "    [site]"
  , "    title = \"My site\"   # a comment"
  ]
explanation TomlUnsupported = MkExplanation
  "a TOML feature that ddraig does not read"
  [ "ddraig reads a subset of TOML, listed in CONFIGURATION.adoc, and reports"
  , "anything else rather than guessing. Not supported: floating-point numbers,"
  , "dates and times (write them as strings: \"2026-06-22\"), multi-line strings,"
  , "arrays that span several lines, inline tables { ... }, and dotted keys"
  , "(a.b = 1; use a [a] table header instead)."
  ]
explanation TomlDuplicate = MkExplanation
  "a key or a table is defined twice"
  [ "TOML allows each key once per table, and each [table] header once. The"
  , "message shows where the first definition is. Delete one of the two, or, for"
  , "a list of similar tables such as menu entries, use [[double brackets]]."
  ]
explanation ConfigUnknownTable = MkExplanation
  "ddraig.toml has a table ddraig does not know"
  [ "The tables of ddraig.toml are [site], [extra] and [[menus.<name>]]."
  , "Settings outside any table are not allowed: put site settings under [site],"
  , "and your own values under [extra]. CONFIGURATION.adoc lists every key."
  ]
explanation ConfigUnknownKey = MkExplanation
  "a table in ddraig.toml has a key ddraig does not know"
  [ "[site] takes title, base_url, language, description and author. A menu"
  , "entry ([[menus.<name>]]) takes name and url. Keys are case-sensitive. Values"
  , "of your own, for templates, go under [extra], where any key is allowed."
  ]
explanation ConfigWrongType = MkExplanation
  "a setting in ddraig.toml has the wrong kind of value"
  [ "Every key of [site] and of a menu entry takes a string, written in quotes:"
  , ""
  , "    language = \"cy\""
  , ""
  , "not a number, true/false, or a list."
  ]
explanation ConfigBadValue = MkExplanation
  "a setting in ddraig.toml has a value ddraig cannot use"
  [ "base_url must be an absolute http:// or https:// address without spaces,"
  , "such as \"https://example.org\" or, for a site served under a sub-path,"
  , "\"https://user.github.io/repo\". language must be a language tag such as"
  , "\"en\", \"cy\" or \"pt-BR\": letters, digits and hyphens, starting with two or"
  , "three letters."
  ]
explanation ConfigMenuEntry = MkExplanation
  "a menu entry is missing its name or its url"
  [ "Each [[menus.<name>]] entry is one link and needs both keys:"
  , ""
  , "    [[menus.main]]"
  , "    name = \"About\""
  , "    url = \"/about.html\""
  , ""
  , "A url starting with / is inside the site and gets the base URL's path in"
  , "front of it; other urls are used as written."
  ]
explanation ConfigUnreadable = MkExplanation
  "a configuration file could not be read"
  [ "`ddraig validate-config <file>` needs an existing, readable file. `ddraig"
  , "build` reads <src>/ddraig.toml only if it exists; without it, the defaults"
  , "apply."
  ]
explanation TemplateUnknownVariable = MkExplanation
  "a template uses a {{site...}} or {{data...}} variable that does not exist"
  [ "{{site.title}}, {{site.base_url}}, {{site.language}}, {{site.description}},"
  , "{{site.author}} and {{site.extra.<key>}} come from ddraig.toml."
  , "{{data.<file>.<key>}} comes from data/<file>.toml, with table names in"
  , "between for keys inside a [table]: {{data.team.roles.editor}}."
  , ""
  , "Check the spelling; the message suggests the nearest variable that exists."
  , "A variable that exists but has no value set is shown as empty, not an error."
  ]
explanation TemplateNotText = MkExplanation
  "a template variable holds a list, which cannot be shown as text"
  [ "Templates can show strings, numbers and true/false. A list, such as"
  , "tags = [\"a\", \"b\"], needs a loop, which arrives with the template engine"
  , "(work package 1, milestone 2). Until then, use a string."
  ]

-- ============================================================================
-- Diagnostics
-- ============================================================================

data Severity = Error | Warning

-- A position in a file: 1-based line and column (counted in characters), and
-- how many characters to underline.
record Span where
  constructor MkSpan
  line  : Nat
  col   : Nat
  width : Nat

||| One reported problem. Abstract: build one with `diagError` or
||| `diagWarning`, then add a location, help and notes with the functions below.
export
record Diagnostic where
  constructor MkDiagnostic
  severity : Severity
  code     : Code
  message  : String          -- one line: what is wrong
  file     : Maybe String    -- the path as the user wrote it
  pos      : Maybe Span      -- where in `file`
  label    : String          -- short text after the carets; "" for none
  help     : List String     -- how to fix it, one suggestion per entry
  notes    : List String     -- further context

||| A problem that stops the build.
export
diagError : Code -> (message : String) -> Diagnostic
diagError c m = MkDiagnostic Error c m Nothing Nothing "" [] []

||| A problem worth knowing about that does not stop the build.
export
diagWarning : Code -> (message : String) -> Diagnostic
diagWarning c m = MkDiagnostic Warning c m Nothing Nothing "" [] []

||| Locate the problem in a whole file.
export
inFile : (file : String) -> Diagnostic -> Diagnostic
inFile f d = { file := Just f, pos := Nothing } d

||| Locate the problem at `line`:`col` (both 1-based) in `file`, underlining
||| `width` characters (at least one) and labelling them.
export
atPos : (file : String) -> (line : Nat) -> (col : Nat) -> (width : Nat)
     -> (label : String) -> Diagnostic -> Diagnostic
atPos f l c w lbl d = { file := Just f, pos := Just (MkSpan l c w), label := lbl } d

||| Add a suggestion for fixing the problem.
export
withHelp : String -> Diagnostic -> Diagnostic
withHelp h d = { help $= (++ [h]) } d

||| Add several suggestions, in order (for example the result of `didYouMean`).
export
withHelps : List String -> Diagnostic -> Diagnostic
withHelps hs d = { help $= (++ hs) } d

||| Add a note with further context.
export
withNote : String -> Diagnostic -> Diagnostic
withNote n d = { notes $= (++ [n]) } d

export
isError : Diagnostic -> Bool
isError d = case d.severity of
              Error   => True
              Warning => False

||| The file a diagnostic refers to, if any (to load its text for `renderAll`).
export
diagFile : Diagnostic -> Maybe String
diagFile d = d.file

-- ============================================================================
-- "Did you mean ...?"
-- ============================================================================

-- 0, 1, ..., n
upTo : Nat -> List Nat
upTo n = go n []
  where
    go : Nat -> List Nat -> List Nat
    go Z     acc = Z :: acc
    go (S k) acc = go k (S k :: acc)

-- Next row of the Levenshtein table. `prev` is the row for the previous
-- character of the first string (one entry per prefix of `cs`), `c` this row's
-- character and `i` its 1-based index.
nextRow : (cs : List Char) -> (c : Char) -> (i : Nat) -> (prev : List Nat) -> List Nat
nextRow cs c i prev = i :: go i prev cs
  where
    go : Nat -> List Nat -> List Char -> List Nat
    go left (diag :: rest@(up :: _)) (x :: xs) =
      let v = min (up + 1) (min (left + 1) (diag + (if x == c then 0 else 1)))
      in v :: go v rest xs
    go _ _ _ = []

||| Levenshtein distance: the fewest single-character insertions, deletions and
||| substitutions that turn one string into the other.
export
editDistance : String -> String -> Nat
editDistance a b =
  let bs   = unpack b
      rows = foldl (\row, (i, c) => nextRow bs c i row) (upTo (length bs)) (numbered 1 (unpack a))
  in fromMaybe 0 (last' rows)
  where
    numbered : Nat -> List Char -> List (Nat, Char)
    numbered _ []        = []
    numbered k (x :: xs) = (k, x) :: numbered (S k) xs

-- n `div` 3, without a partial division.
third : Nat -> Nat
third (S (S (S k))) = S (third k)
third _             = 0

||| The name in `known` most plausibly meant by `wanted`: one that differs only
||| in case, otherwise the nearest by edit distance, within about a third of
||| the word's length (at least one edit). Ties go to the earliest in `known`,
||| so the suggestion is deterministic. Nothing when no name is close enough.
export
closest : (wanted : String) -> (known : List String) -> Maybe String
closest wanted known =
  case filter (\k => k /= wanted && toLower k == toLower wanted) known of
    (k :: _) => Just k
    []       => best Nothing known
  where
    limit : Nat
    limit = max 1 (third (length wanted + 2))
    best : Maybe (Nat, String) -> List String -> Maybe String
    best acc [] = map snd acc
    best acc (k :: ks) =
      let d = editDistance wanted k in
      if d == 0 || d > limit then best acc ks
      else case acc of
             Just (bd, _) => if d < bd then best (Just (d, k)) ks else best acc ks
             Nothing      => best (Just (d, k)) ks

||| A ready-made help line, or nothing when no name is close enough.
export
didYouMean : (wanted : String) -> (known : List String) -> List String
didYouMean wanted known = case closest wanted known of
  Just k  => ["did you mean \"" ++ k ++ "\"?"]
  Nothing => []

-- ============================================================================
-- Rendering (total and deterministic)
-- ============================================================================

severityText : Severity -> String
severityText Error   = "error"
severityText Warning = "warning"

spaces : Nat -> String
spaces n = Data.String.replicate n ' '

-- Line `n` (1-based) of a text, without a trailing carriage return.
lineOf : Nat -> String -> Maybe String
lineOf Z     _   = Nothing
lineOf (S k) src = case drop k (lines src) of
  (l :: _) => Just (if isSuffixOf "\r" l then substr 0 (minus (length l) 1) l else l)
  []       => Nothing

-- Tabs are shown as one space, so a caret lines up with its column.
detab : String -> String
detab s = pack (map (\c => if c == '\t' then ' ' else c) (unpack s))

||| Render one diagnostic. `source` is the text of the diagnostic's file, when
||| it can be read; it is used only to quote the offending line.
export
render : (source : Maybe String) -> Diagnostic -> String
render source d = unlines (header :: location ++ snippet ++ trailers)
  where
    -- gutter width: the digits of the line number (1 when there is none)
    w : Nat
    w = case d.pos of
          Just sp => length (show sp.line)
          Nothing => 1
    gutter : String
    gutter = spaces (S w) ++ "|"
    header : String
    header = severityText d.severity ++ "[" ++ codeId d.code ++ "]: " ++ d.message
    location : List String
    location = case d.file of
      Nothing => []
      Just f  => [spaces w ++ "--> " ++ f
                    ++ maybe "" (\sp => ":" ++ show sp.line ++ ":" ++ show sp.col) d.pos]
    quoted : Maybe (Span, String)
    quoted = do sp  <- d.pos
                src <- source
                l   <- lineOf sp.line src
                pure (sp, detab l)
    snippet : List String
    snippet = case quoted of
      Nothing => []
      Just (sp, l) =>
        let start = minus sp.col 1
            room  = minus (length l) start
            width = if room == 0 then 1 else min (max 1 sp.width) room
            lbl   = if d.label == "" then "" else " " ++ d.label
            code  = if l == "" then show sp.line ++ " |" else show sp.line ++ " | " ++ l
        in [gutter, code, gutter ++ " " ++ spaces start ++ Data.String.replicate width '^' ++ lbl]
    trailers : List String
    trailers =
      let items = map ("help: " ++) d.help ++ map ("note: " ++) d.notes in
      if null items then []
      else (if isJust quoted then [gutter] else [])
             ++ map (\t => spaces (S w) ++ "= " ++ t) items

plural : Nat -> String -> String
plural 1 noun = "1 " ++ noun
plural n noun = show n ++ " " ++ noun ++ "s"

||| A one-line count, e.g. "2 errors and 1 warning".
export
summary : List Diagnostic -> String
summary ds =
  let e = length (filter isError ds)
      w = minus (length ds) e
  in case (e, w) of
       (0, 0) => "no problems"
       (_, 0) => plural e "error"
       (0, _) => plural w "warning"
       _      => plural e "error" ++ " and " ++ plural w "warning"

||| Render several diagnostics in a stable order (those without a file first,
||| then by file, line and column), separated by blank lines. `sourceOf` gives
||| the text of a file, when it can be read.
export
renderAll : (sourceOf : String -> Maybe String) -> List Diagnostic -> String
renderAll sourceOf ds =
  concat (intersperse "\n" (map (\d => render (d.file >>= sourceOf) d) (sortBy order ds)))
  where
    key : Diagnostic -> (String, Nat, Nat)
    key d = (fromMaybe "" d.file, maybe 0 line d.pos, maybe 0 col d.pos)
    order : Diagnostic -> Diagnostic -> Ordering
    order x y = compare (key x) (key y)

||| `ddraig explain <code>`.
export
renderExplanation : Code -> String
renderExplanation c =
  let e = explanation c in unlines ((codeId c ++ ": " ++ e.heading) :: "" :: e.details)

||| `ddraig explain` with no code: every code and its one-line meaning.
export
renderCodeList : String
renderCodeList = unlines (map (\c => codeId c ++ "  " ++ (explanation c).heading) allCodes)
