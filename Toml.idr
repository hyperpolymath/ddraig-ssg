-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Toml.idr - the subset of TOML that ddraig reads, with source positions.
--
-- This is the untrusted, `covering` side of the configuration boundary, as
-- State.idr's parser is for STATE descriptiles: it turns text into tables of
-- located values, or into located diagnostics. Whether the tables form a valid
-- site configuration is decided, totally, in Config.idr.
--
-- Supported (CONFIGURATION.adoc): # comments; [table] and [[array of tables]]
-- headers made of bare names joined by dots; bare or "quoted" keys; one-line
-- basic ("...") and literal ('...') strings; integers; true and false; lists,
-- which may span lines and contain comments. Everything else TOML allows is
-- reported as unsupported (DDR0102) instead of being guessed at, so a file is
-- either read exactly or rejected with a reason and a suggested rewrite.
--
-- The text is read as a stream of characters that each carry their own line
-- and column, so every position reported is exact, including inside a list
-- that spans several lines.

module Toml

import Data.List
import Data.List1
import Data.String
import Diagnostic

%default covering

-- ============================================================================
-- Located documents
-- ============================================================================

public export
data TValue = TStr String | TInt Integer | TBool Bool | TArr (List TValue)

||| A `key = value` statement.
public export
record Entry where
  constructor MkEntry
  eKey  : String
  eVal  : TValue
  eLine : Nat    -- 1-based line of the key
  eCol  : Nat    -- 1-based column of the key
  eVCol : Nat    -- column where the value starts (on line eLine)
  eVLen : Nat    -- characters the value occupies on that line

||| A table: the keys before the first header (path []), or a [header] and
||| the keys up to the next one.
public export
record Table where
  constructor MkTable
  tPath    : List String   -- [] for the top level
  tArray   : Bool          -- written [[like.this]]
  tLine    : Nat           -- line of the header; 0 for the top level
  tCol     : Nat
  tWidth   : Nat           -- characters the header occupies
  tEntries : List Entry    -- in file order

||| A table path as a header writes it: ["menus", "main"] is "menus.main".
public export
pathName : List String -> String
pathName ps = concat (intersperse "." ps)

-- ============================================================================
-- Located characters
-- ============================================================================

-- A character with its 1-based line and column.
LChar : Type
LChar = (Char, Nat, Nat)

-- A position: line and column.
Pos : Type
Pos = (Nat, Nat)

-- Number every character; a carriage return before a newline is dropped.
locate : String -> List LChar
locate s = go 1 1 (unpack s)
  where
    go : Nat -> Nat -> List Char -> List LChar
    go _ _ []                   = []
    go l c ('\r' :: '\n' :: cs) = ('\n', l, c) :: go (S l) 1 cs
    go l c ('\n' :: cs)         = ('\n', l, c) :: go (S l) 1 cs
    go l c (ch :: cs)           = (ch, l, c) :: go l (S c) cs

chr0 : LChar -> Char
chr0 (ch, _, _) = ch

posOf : LChar -> Pos
posOf (_, l, c) = (l, c)

-- The position of the first character, or `dflt` at the end of the text.
here : List LChar -> Pos -> Pos
here (x :: _) _    = posOf x
here []       dflt = dflt

isBare : Char -> Bool
isBare c = isAlphaNum c || c == '_' || c == '-'

-- Spaces and tabs.
skipBlank : List LChar -> List LChar
skipBlank ((' ', _, _) :: cs)  = skipBlank cs
skipBlank (('\t', _, _) :: cs) = skipBlank cs
skipBlank cs                   = cs

-- A comment, up to (not including) the end of its line.
skipComment : List LChar -> List LChar
skipComment cs@(('\n', _, _) :: _) = cs
skipComment (_ :: cs)              = skipComment cs
skipComment []                     = []

-- Spaces, tabs, line breaks and comments.
skipSpace : List LChar -> List LChar
skipSpace cs = case skipBlank cs of
  (('\n', _, _) :: rest)    => skipSpace rest
  rest@(('#', _, _) :: _)   => skipSpace (skipComment rest)
  rest                      => rest

-- After a value or header: spaces, an optional comment, then the end of the
-- line. Right with what follows the line, or Left with the offending position.
endOfLine : List LChar -> Either Pos (List LChar)
endOfLine cs = case skipBlank cs of
  []                       => Right []
  (('\n', _, _) :: rest)   => Right rest
  rest@(('#', _, _) :: _)  => endOfLine (skipComment rest)
  (x :: _)                 => Left (posOf x)

-- Recovery after a problem: skip the rest of the statement that starts here,
-- including the rest of any list still open at the end of its first line.
skipStatement : List LChar -> List LChar
skipStatement cs = go cs 0 Nothing
  where
    -- depth of [ ] outside strings; the quote character of an open string
    go : List LChar -> Nat -> Maybe Char -> List LChar
    go [] _ _ = []
    go (('\n', _, _) :: rest) Z _ = rest
    go (('\n', _, _) :: rest) d _ = go rest d Nothing
    go ((ch, _, _) :: rest) d (Just q) = go rest d (if ch == q then Nothing else Just q)
    go ((ch, _, _) :: rest) d Nothing =
      if ch == '"' || ch == '\'' then go rest d (Just ch)
      else if ch == '#' then go (skipComment rest) d Nothing
      else if ch == '[' then go rest (S d) Nothing
      else if ch == ']' then go rest (minus d 1) Nothing
      else go rest d Nothing

-- ============================================================================
-- Values
-- ============================================================================

hexDigit : Char -> Maybe Integer
hexDigit c =
  if c >= '0' && c <= '9' then Just (cast (ord c - ord '0'))
  else if c >= 'a' && c <= 'f' then Just (cast (ord c - ord 'a' + 10))
  else if c >= 'A' && c <= 'F' then Just (cast (ord c - ord 'A' + 10))
  else Nothing

hexValue : List Char -> Maybe Integer
hexValue cs = foldl (\acc, c => [| (\a, d => a * 16 + d) acc (hexDigit c) |]) (Just 0) cs

-- A diagnostic at a position in `f`.
problem : (f : String) -> Code -> Pos -> (width : Nat) -> (label : String)
       -> (message : String) -> Diagnostic
problem f code (l, c) width label message = atPos f l c width label (diagError code message)

-- A value's result: the value, the position just after it, what follows.
Parsed : Type
Parsed = (TValue, Pos, List LChar)

-- Read one value. `at` is the position of its first character (also used at
-- the end of the text).
parseValue : (f : String) -> (at : Pos) -> List LChar -> Either Diagnostic Parsed
parseValue f at cs =
  case cs of
    (('"', _, _) :: ('"', _, _) :: ('"', _, _) :: _) =>
      Left (withHelp "write it on one line, with \\n where a line break is wanted" $
            problem f TomlUnsupported at 3 "" "multi-line strings are not supported")
    (('"', l, c) :: rest) => basic (l, c) rest []
    (('\'', _, _) :: ('\'', _, _) :: ('\'', _, _) :: _) =>
      Left (withHelp "write it on one line" $
            problem f TomlUnsupported at 3 "" "multi-line strings are not supported")
    (('\'', l, c) :: rest) => literal (l, c) rest []
    (('[', l, c) :: rest) => array (l, c) rest []
    (('{', _, _) :: _) =>
      Left (withHelp "use a [table] header and one key = value per line instead" $
            problem f TomlUnsupported at 1 "" "inline tables { ... } are not supported")
    _ => scalar
  where
    unclosed : Pos -> Diagnostic
    unclosed opening = withHelp "close it on the same line; ddraig does not read multi-line strings" $
                    problem f TomlSyntax opening 1 "this string is never closed" "unclosed string"

    after : Pos -> Pos
    after (l, c) = (l, S c)

    basic : Pos -> List LChar -> List Char -> Either Diagnostic Parsed
    basic opening [] _ = Left (unclosed opening)
    basic opening (('\n', _, _) :: _) _ = Left (unclosed opening)
    basic opening (('"', l, c) :: rest) acc = Right (TStr (pack (reverse acc)), (l, S c), rest)
    basic opening (('\\', l, c) :: (e, _, _) :: rest) acc =
      let simple = case e of
                     'n' => Just '\n'; 't' => Just '\t'; 'r' => Just '\r'
                     'b' => Just '\b'; 'f' => Just '\f'; '"' => Just '"'
                     '\\' => Just '\\'; _ => Nothing
      in case simple of
           Just ch => basic opening rest (ch :: acc)
           Nothing =>
             let digits = the (Maybe Nat) (if e == 'u' then Just 4 else if e == 'U' then Just 8 else Nothing) in
             case digits of
               Nothing =>
                 Left (withHelp "the escapes are \\n \\t \\r \\b \\f \\\" \\\\ \\uXXXX and \\UXXXXXXXX; write \\\\ for a backslash" $
                       problem f TomlSyntax (l, c) 2 "" ("unknown escape \\" ++ singleton e ++ " in a string"))
               Just n =>
                 let hex = map chr0 (take n rest) in
                 case (length hex == n, hexValue hex) of
                   (True, Just v) =>
                     if v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)
                       then Left (problem f TomlSyntax (l, c) (n + 2) "" "this escape is not a Unicode character")
                       else basic opening (drop n rest) (chr (cast v) :: acc)
                   _ => Left (withHelp ("\\" ++ singleton e ++ " needs exactly " ++ show n ++ " hexadecimal digits") $
                              problem f TomlSyntax (l, c) (n + 2) "" "malformed Unicode escape")
    basic opening [('\\', _, _)] _ = Left (unclosed opening)
    basic opening ((ch, l, c) :: rest) acc =
      if ch < ' ' && ch /= '\t'
        then Left (problem f TomlSyntax (l, c) 1 "" "control character in a string")
        else basic opening rest (ch :: acc)

    literal : Pos -> List LChar -> List Char -> Either Diagnostic Parsed
    literal opening [] _ = Left (unclosed opening)
    literal opening (('\n', _, _) :: _) _ = Left (unclosed opening)
    literal opening (('\'', l, c) :: rest) acc = Right (TStr (pack (reverse acc)), (l, S c), rest)
    literal opening ((ch, l, c) :: rest) acc =
      if ch < ' ' && ch /= '\t'
        then Left (problem f TomlSyntax (l, c) 1 "" "control character in a string")
        else literal opening rest (ch :: acc)

    -- A list may span lines and hold comments between its items.
    array : Pos -> List LChar -> List TValue -> Either Diagnostic Parsed
    array opening rest acc =
      case skipSpace rest of
        [] => Left (withHelp "close it with ]" $
                    problem f TomlSyntax opening 1 "this list is never closed" "unclosed list")
        ((']', l, c) :: more) => Right (TArr (reverse acc), (l, S c), more)
        cur => case parseValue f (here cur opening) cur of
          Left d => Left (withNote ("in the list that starts on line " ++ show (fst opening)) d)
          Right (v, _, afterV) =>
            case skipSpace afterV of
              ((',', _, _) :: more)  => array opening more (v :: acc)
              ((']', l, c) :: more)  => Right (TArr (reverse (v :: acc)), (l, S c), more)
              []                     => Left (withHelp "close it with ]" $
                                              problem f TomlSyntax opening 1 "this list is never closed" "unclosed list")
              (x :: _) => Left (withHelp "separate list items with commas: [\"a\", \"b\"]" $
                                withNote ("in the list that starts on line " ++ show (fst opening)) $
                                problem f TomlSyntax (posOf x) 1 "" "expected , or ] in the list")

    delimiter : Char -> Bool
    delimiter ch = ch == ' ' || ch == '\t' || ch == ',' || ch == ']' || ch == '#' || ch == '\n'

    -- [+-] digits, with single underscores between digits, no leading zeros.
    integer : String -> Nat -> Pos -> List LChar -> Either Diagnostic Parsed
    integer word w end rest =
      let unsigned = case unpack word of
                       ('+' :: ds) => ds
                       ('-' :: ds) => ds
                       ds          => ds
          digitsOk = case unsigned of
                       [] => False
                       ('_' :: _) => False
                       ds => all (\ch => isDigit ch || ch == '_') ds
                             && not (isSuffixOf ['_'] ds)
                             && not (isInfixOf ['_', '_'] ds)
          leadingZero = case unsigned of
                          ('0' :: _ :: _) => True
                          _               => False
          plain = pack (filter (/= '_') (unpack word))
      in if not digitsOk then
           Left (problem f TomlSyntax at w "" "this number is not written correctly")
         else if leadingZero then
           Left (withHelp "remove the leading zeros, or write it as a string" $
                 problem f TomlSyntax at w "" "numbers may not start with 0")
         else case parseInteger {a = Integer} plain of
                Just n  => Right (TInt n, end, rest)
                Nothing => Left (problem f TomlSyntax at w "" "this number is not written correctly")

    scalar : Either Diagnostic Parsed
    scalar =
      let (tokL, rest) = break (delimiter . chr0) cs
          tok = map chr0 tokL
          word = pack tok
          w = length tok
          end = (fst at, snd at + w)
          isNum = case tok of
                    (s :: d :: _) => if s == '+' || s == '-' then isDigit d else isDigit s
                    (d :: _)      => isDigit d
                    []            => False
      in if w == 0 then
           Left (problem f TomlSyntax at 1 "" "expected a value")
         else if word == "true" then Right (TBool True, end, rest)
         else if word == "false" then Right (TBool False, end, rest)
         else if elem word ["inf", "+inf", "-inf", "nan", "+nan", "-nan"]
              || (isNum && any (\ch => ch == '.' || ch == 'e' || ch == 'E') tok
                  && not (isPrefixOf "0x" word))
           then Left (withHelp ("write it as a string, \"" ++ word ++ "\", or as a whole number") $
                      problem f TomlUnsupported at w "" "floating-point numbers are not supported")
         else if isNum && any (\ch => ch == ':' || ch == 'T' || ch == 'Z') tok
                 || (isNum && any (== '-') (drop 1 tok))
           then Left (withHelp ("write it as a string: \"" ++ word ++ "\"") $
                      problem f TomlUnsupported at w "" "dates and times are not supported")
         else if isPrefixOf "0x" word || isPrefixOf "0o" word || isPrefixOf "0b" word
           then Left (withHelp "write the number in decimal" $
                      problem f TomlUnsupported at w "" "hexadecimal, octal and binary numbers are not supported")
         else if isNum then integer word w end rest
         else Left (withHelp ("if it is text, put it in quotes: \"" ++ word ++ "\"") $
                    problem f TomlSyntax at w "not a string, number, true/false or list"
                      "this value is not valid TOML")

-- ============================================================================
-- Statements
-- ============================================================================

-- What one statement holds.
data Stmt
  = Header (List String) Bool Nat Nat Nat   -- path, is [[array]], line, column, width
  | KeyValue Entry

-- A [header] or [[header]]; `cs` starts at its first '['.
parseHeader : (f : String) -> Pos -> (isArray : Bool) -> List LChar
           -> Either Diagnostic (Stmt, List LChar)
parseHeader f (l, c) isArray cs =
  let afterOpen = drop (if isArray then 2 else 1) cs
      (nameL, rest) = break (\x => chr0 x == ']' || chr0 x == '\n') afterOpen
      name = pack (map chr0 nameL)
      segments = map trim (forget (split (== '.') name))
      closing = if isArray then "]]" else "]"
      width = length nameL + (if isArray then 4 else 2)
  in case (isArray, rest) of
       (True, ((']', _, _) :: (']', _, _) :: more)) => finish segments width more
       (False, ((']', _, _) :: more))               => finish segments width more
       _ => Left (withHelp ("close it with " ++ closing ++ " on the same line") $
                  problem f TomlSyntax (l, c) (length nameL + (if isArray then 2 else 1)) ""
                    "this table header is not closed")
  where
    finish : List String -> Nat -> List LChar -> Either Diagnostic (Stmt, List LChar)
    finish segments width more =
      if any (\s => s == "" || not (all isBare (unpack s))) segments
        then Left (withHelp "table names are bare words (letters, digits, _ and -) joined by dots, e.g. [menus.main]" $
                   problem f TomlSyntax (l, c) width "" "this table header is not valid")
        else case endOfLine more of
               Right next => Right (Header segments isArray l c width, next)
               Left p => Left (problem f TomlSyntax p 1 "" "unexpected text after the table header")

-- A key = value statement; `cs` starts at the key.
parseKeyValue : (f : String) -> Pos -> List LChar -> Either Diagnostic (Stmt, List LChar)
parseKeyValue f (l, c) cs = do
  (key, afterKey) <-
    case cs of
      (('"', _, _) :: _) =>
        case parseValue f (l, c) cs of
          Right (TStr k, _, more) => Right (k, more)
          Right _                 => Left (problem f TomlSyntax (l, c) 1 "" "expected a key")
          Left d                  => Left d
      _ => let (kL, more) = span (isBare . chr0) cs in
           if null kL
             then Left (withHelp "a line is a [table] header, key = value, or a # comment" $
                        problem f TomlSyntax (l, c) 1 "" "expected a key")
             else Right (pack (map chr0 kL), more)
  let rest = skipBlank afterKey
  let keyEnd = here rest (l, c + length key)
  case rest of
    (('.', _, _) :: _) =>
      Left (withHelp ("use a table header, [" ++ key ++ "], and then one key = value per line") $
            problem f TomlUnsupported (l, c) (minus (snd keyEnd) c + 1) "" "dotted keys are not supported")
    (('=', _, _) :: more) => do
      let valueStart = skipBlank more
      let vpos = here valueStart keyEnd
      (v, vend, afterV) <- parseValue f vpos valueStart
      case endOfLine afterV of
        Right next =>
          let vlen = if fst vend == fst vpos then minus (snd vend) (snd vpos) else 1 in
          Right (KeyValue (MkEntry key v l c (snd vpos) vlen), next)
        Left p => Left (withHelp "put each key = value on its own line; start comments with #" $
                        problem f TomlSyntax p 1 "" "unexpected text after the value")
    _ => Left (withHelp ("write it as " ++ key ++ " = value") $
               problem f TomlSyntax keyEnd 1 "" "expected = after the key")

-- ============================================================================
-- The document
-- ============================================================================

||| Read a TOML document: its tables in file order (the top-level keys first,
||| as a table with path []), and every problem found. A statement with a
||| problem is skipped, so later statements are still checked.
export
parseToml : (file : String) -> (text : String) -> (List Table, List Diagnostic)
parseToml f text = go (locate text) (MkTable [] False 0 0 0 []) [] [] []
  where
    close : Table -> Table
    close t = { tEntries $= reverse } t

    firstLine : String -> List Entry -> Maybe Nat
    firstLine k es = map eLine (find (\e => e.eKey == k) es)

    go : List LChar -> (cur : Table) -> (done : List Table)
      -> (seen : List (List String, Bool, Nat)) -> (errs : List Diagnostic)
      -> (List Table, List Diagnostic)
    go cs cur done seen errs =
      case skipSpace cs of
        [] => (reverse (close cur :: done), reverse errs)
        stmt@((ch, l, c) :: more) =>
          let parsed = if ch == '['
                         then parseHeader f (l, c) (case more of
                                                      (('[', _, _) :: _) => True
                                                      _ => False) stmt
                         else parseKeyValue f (l, c) stmt
          in case parsed of
               Left d => go (skipStatement stmt) cur done seen (d :: errs)
               Right (Header path isArray hl hc w, next) =>
                 let clash = find (\(p, a, _) => p == path && (not isArray || not a)) seen
                     errs' = case clash of
                               Just (_, a, first) =>
                                 (withNote ("first defined on line " ++ show first) $
                                  withHelp (if a || isArray
                                              then "use [[" ++ pathName path ++ "]] for every entry, or [" ++ pathName path ++ "] once"
                                              else "merge the two into one [" ++ pathName path ++ "] table")
                                           (problem f TomlDuplicate (hl, hc) w "" ("table [" ++ pathName path ++ "] is defined twice")))
                                 :: errs
                               Nothing => errs
                 in go next (MkTable path isArray hl hc w []) (close cur :: done) ((path, isArray, hl) :: seen) errs'
               Right (KeyValue e, next) =>
                 case firstLine e.eKey cur.tEntries of
                   Just first =>
                     let d = withNote ("first set on line " ++ show first) $
                             withHelp "delete one of the two" $
                             problem f TomlDuplicate (e.eLine, e.eCol) (length e.eKey) ""
                               ("key \"" ++ e.eKey ++ "\" is set twice in this table")
                     in go next cur done seen (d :: errs)
                   Nothing => go next ({ tEntries $= (e ::) } cur) done seen errs
