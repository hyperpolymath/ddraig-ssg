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
-- basic ("...") and literal ('...') strings; integers; true and false;
-- one-line arrays. Everything else TOML allows is reported as unsupported
-- (DDR0102) instead of being guessed at, so a file is either read exactly or
-- rejected with a reason and a suggested rewrite.

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

||| A `key = value` line.
public export
record Entry where
  constructor MkEntry
  eKey  : String
  eVal  : TValue
  eLine : Nat    -- 1-based line
  eCol  : Nat    -- 1-based column of the key
  eVCol : Nat    -- column where the value starts
  eVLen : Nat    -- characters the value occupies

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
-- Scanning one line
-- ============================================================================

-- A cursor: the characters still to read, and the column of the first one.
Cursor : Type
Cursor = (List Char, Nat)

isBare : Char -> Bool
isBare c = isAlphaNum c || c == '_' || c == '-'

skipSpaces : Cursor -> Cursor
skipSpaces (' '  :: cs, c) = skipSpaces (cs, S c)
skipSpaces ('\t' :: cs, c) = skipSpaces (cs, S c)
skipSpaces cur             = cur

-- Nothing but spaces and an optional comment remain.
atLineEnd : Cursor -> Bool
atLineEnd cur = case fst (skipSpaces cur) of
                  []         => True
                  ('#' :: _) => True
                  _          => False

hexDigit : Char -> Maybe Integer
hexDigit c =
  if c >= '0' && c <= '9' then Just (cast (ord c - ord '0'))
  else if c >= 'a' && c <= 'f' then Just (cast (ord c - ord 'a' + 10))
  else if c >= 'A' && c <= 'F' then Just (cast (ord c - ord 'A' + 10))
  else Nothing

hexValue : List Char -> Maybe Integer
hexValue cs = foldl (\acc, c => [| (\a, d => a * 16 + d) acc (hexDigit c) |]) (Just 0) cs

-- A diagnostic at line `ln` of `f`.
problem : (f : String) -> (ln : Nat) -> Code -> (col : Nat) -> (width : Nat)
       -> (label : String) -> (message : String) -> Diagnostic
problem f ln code col width label message = atPos f ln col width label (diagError code message)

-- Read one value starting at the cursor.
parseValue : (f : String) -> (ln : Nat) -> Cursor -> Either Diagnostic (TValue, Cursor)
parseValue f ln (cs, col) =
  case cs of
    ('"' :: '"' :: '"' :: _) =>
      Left (withHelp "write it on one line, with \\n where a line break is wanted" $
            problem f ln TomlUnsupported col 3 "" "multi-line strings are not supported")
    ('"' :: rest) => basic rest (S col) []
    ('\'' :: '\'' :: '\'' :: _) =>
      Left (withHelp "write it on one line" $
            problem f ln TomlUnsupported col 3 "" "multi-line strings are not supported")
    ('\'' :: rest) => literal rest (S col) []
    ('[' :: rest) => array rest (S col) []
    ('{' :: _) =>
      Left (withHelp "use a [table] header and one key = value per line instead" $
            problem f ln TomlUnsupported col 1 "" "inline tables { ... } are not supported")
    _ => scalar
  where
    unclosed : Diagnostic
    unclosed = withHelp "close it on the same line; ddraig does not read multi-line strings" $
               problem f ln TomlSyntax col 1 "this string is never closed" "unclosed string"

    basic : List Char -> Nat -> List Char -> Either Diagnostic (TValue, Cursor)
    basic [] _ _ = Left unclosed
    basic ('"' :: rest) c acc = Right (TStr (pack (reverse acc)), (rest, S c))
    basic ('\\' :: e :: rest) c acc =
      let simple = case e of
                     'n' => Just '\n'; 't' => Just '\t'; 'r' => Just '\r'
                     'b' => Just '\b'; 'f' => Just '\f'; '"' => Just '"'
                     '\\' => Just '\\'; _ => Nothing
      in case simple of
           Just ch => basic rest (c + 2) (ch :: acc)
           Nothing =>
             let digits = the (Maybe Nat) (if e == 'u' then Just 4 else if e == 'U' then Just 8 else Nothing) in
             case digits of
               Nothing =>
                 Left (withHelp "the escapes are \\n \\t \\r \\b \\f \\\" \\\\ \\uXXXX and \\UXXXXXXXX; write \\\\ for a backslash" $
                       problem f ln TomlSyntax c 2 "" ("unknown escape \\" ++ singleton e ++ " in a string"))
               Just n =>
                 let hex = take n rest in
                 case (length hex == n, hexValue hex) of
                   (True, Just v) =>
                     if v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)
                       then Left (problem f ln TomlSyntax c (n + 2) "" "this escape is not a Unicode character")
                       else basic (drop n rest) (c + n + 2) (chr (cast v) :: acc)
                   _ => Left (withHelp ("\\" ++ singleton e ++ " needs exactly " ++ show n ++ " hexadecimal digits") $
                              problem f ln TomlSyntax c (n + 2) "" "malformed Unicode escape")
    basic ('\\' :: []) _ _ = Left unclosed
    basic (ch :: rest) c acc =
      if ch < ' ' && ch /= '\t'
        then Left (problem f ln TomlSyntax c 1 "" "control character in a string")
        else basic rest (S c) (ch :: acc)

    literal : List Char -> Nat -> List Char -> Either Diagnostic (TValue, Cursor)
    literal [] _ _ = Left unclosed
    literal ('\'' :: rest) c acc = Right (TStr (pack (reverse acc)), (rest, S c))
    literal (ch :: rest) c acc =
      if ch < ' ' && ch /= '\t'
        then Left (problem f ln TomlSyntax c 1 "" "control character in a string")
        else literal rest (S c) (ch :: acc)

    array : List Char -> Nat -> List TValue -> Either Diagnostic (TValue, Cursor)
    array rest c acc =
      case skipSpaces (rest, c) of
        ([], _) =>
          Left (withHelp "write the whole list on one line: tags = [\"a\", \"b\"]" $
                problem f ln TomlUnsupported col 1 "this list is not closed on this line"
                  "lists that span several lines are not supported")
        ((']' :: more), c') => Right (TArr (reverse acc), (more, S c'))
        (('#' :: _), _) =>
          Left (withHelp "write the whole list on one line: tags = [\"a\", \"b\"]" $
                problem f ln TomlUnsupported col 1 "this list is not closed on this line"
                  "lists that span several lines are not supported")
        cur => do
          (v, after) <- parseValue f ln cur
          case skipSpaces after of
            ((',' :: more), c'') => array more (S c'') (v :: acc)
            ((']' :: more), c'') => Right (TArr (reverse (v :: acc)), (more, S c''))
            (_, c'') => Left (withHelp "separate list items with commas: [\"a\", \"b\"]" $
                              problem f ln TomlSyntax c'' 1 "" "expected , or ] in the list")

    -- [+-] digits, with single underscores between digits, no leading zeros.
    integer : String -> Nat -> List Char -> Either Diagnostic (TValue, Cursor)
    integer word w rest =
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
           Left (problem f ln TomlSyntax col w "" "this number is not written correctly")
         else if leadingZero then
           Left (withHelp "remove the leading zeros, or write it as a string" $
                 problem f ln TomlSyntax col w "" "numbers may not start with 0")
         else case parseInteger {a = Integer} plain of
                Just n  => Right (TInt n, (rest, col + w))
                Nothing => Left (problem f ln TomlSyntax col w "" "this number is not written correctly")

    delimiter : Char -> Bool
    delimiter ch = ch == ' ' || ch == '\t' || ch == ',' || ch == ']' || ch == '#'

    scalar : Either Diagnostic (TValue, Cursor)
    scalar =
      let (tok, rest) = break delimiter cs
          word = pack tok
          w = length tok
          isNum = case tok of
                    (s :: d :: _) => if s == '+' || s == '-' then isDigit d else isDigit s
                    (d :: _)      => isDigit d
                    []            => False
      in if w == 0 then
           Left (problem f ln TomlSyntax col 1 "" "expected a value after =")
         else if word == "true" then Right (TBool True, (rest, col + w))
         else if word == "false" then Right (TBool False, (rest, col + w))
         else if elem word ["inf", "+inf", "-inf", "nan", "+nan", "-nan"]
              || (isNum && any (\ch => ch == '.' || ch == 'e' || ch == 'E') tok
                  && not (isPrefixOf "0x" word))
           then Left (withHelp ("write it as a string, \"" ++ word ++ "\", or as a whole number") $
                      problem f ln TomlUnsupported col w "" "floating-point numbers are not supported")
         else if isNum && any (\ch => ch == ':' || ch == 'T' || ch == 'Z') tok
                 || (isNum && any (== '-') (drop 1 tok))
           then Left (withHelp ("write it as a string: \"" ++ word ++ "\"") $
                      problem f ln TomlUnsupported col w "" "dates and times are not supported")
         else if isPrefixOf "0x" word || isPrefixOf "0o" word || isPrefixOf "0b" word
           then Left (withHelp "write the number in decimal" $
                      problem f ln TomlUnsupported col w "" "hexadecimal, octal and binary numbers are not supported")
         else if isNum then integer word w rest
         else Left (withHelp ("if it is text, put it in quotes: \"" ++ word ++ "\"") $
                    problem f ln TomlSyntax col w "not a string, number, true/false or list"
                      "this value is not valid TOML")

-- What one line holds.
data Line
  = Blank
  | Header (List String) Bool Nat Nat   -- path, is [[array]], column, width
  | KeyValue Entry

-- Read a [header] or [[header]] whose name starts at the cursor (after the
-- opening brackets). `startCol` is the column of the first '['.
parseHeader : (f : String) -> (ln : Nat) -> (isArray : Bool) -> (startCol : Nat)
           -> Cursor -> Either Diagnostic Line
parseHeader f ln isArray startCol (cs, c) =
  let closing = if isArray then "]]" else "]"
      (nameChars, rest) = break (== ']') cs
      segments = map trim (forget (split (== '.') (pack nameChars)))
      width = length nameChars + (if isArray then 4 else 2)
      badName = withHelp "table names are bare words (letters, digits, _ and -) joined by dots, e.g. [menus.main]" $
                problem f ln TomlSyntax startCol width "" "this table header is not valid"
  in case rest of
       [] => Left (withHelp ("close it with " ++ closing) $
                   problem f ln TomlSyntax startCol 1 "" "this table header is never closed")
       _  =>
         let after = the (Maybe (List Char))
                       (if isArray then (case rest of
                                           (']' :: ']' :: more) => Just more
                                           _ => Nothing)
                        else (case rest of
                                (']' :: more) => Just more
                                _ => Nothing))
         in case after of
              Nothing => Left (withHelp ("close it with " ++ closing) $
                               problem f ln TomlSyntax startCol width "" "this table header is not closed correctly")
              Just more =>
                if any (\s => s == "" || not (all isBare (unpack s))) segments
                  then Left badName
                else if not (atLineEnd (more, startCol + width))
                  then Left (problem f ln TomlSyntax (startCol + width) 1 "" "unexpected text after the table header")
                else Right (Header segments isArray startCol width)

parseLine : (f : String) -> (ln : Nat) -> String -> Either Diagnostic Line
parseLine f ln text =
  let raw = if isSuffixOf "\r" text then substr 0 (minus (length text) 1) text else text
      (cs, c) = skipSpaces (unpack raw, 1)
  in case cs of
       []                  => Right Blank
       ('#' :: _)          => Right Blank
       ('[' :: '[' :: rest) => parseHeader f ln True c (rest, c + 2)
       ('[' :: rest)       => parseHeader f ln False c (rest, S c)
       _                   => keyValue (cs, c)
  where
    keyValue : Cursor -> Either Diagnostic Line
    keyValue (cs, c) = do
      (key, (afterKey, ck)) <-
        case cs of
          ('"' :: _) => do (TStr k, cur) <- parseValue f ln (cs, c)
                             | _ => Left (problem f ln TomlSyntax c 1 "" "expected a key")
                           pure (k, cur)
          _ => let (k, more) = span isBare cs in
               if null k
                 then Left (withHelp "a line is a [table] header, key = value, or a # comment" $
                            problem f ln TomlSyntax c 1 "" "expected a key")
                 else pure (pack k, (more, c + length k))
      let (rest, ce) = skipSpaces (afterKey, ck)
      case rest of
        ('.' :: _) =>
          Left (withHelp ("use a table header: [" ++ key ++ "] and then one key = value per line") $
                problem f ln TomlUnsupported c (minus ce c + 1) "" "dotted keys are not supported")
        ('=' :: more) => do
          let (vcs, vc) = skipSpaces (more, S ce)
          (v, (after, vend)) <- parseValue f ln (vcs, vc)
          if atLineEnd (after, vend)
            then Right (KeyValue (MkEntry key v ln c vc (minus vend vc)))
            else let bad = snd (skipSpaces (after, vend)) in
                 Left (withHelp "put each key = value on its own line; start comments with #" $
                       problem f ln TomlSyntax bad 1 "" "unexpected text after the value")
        _ => Left (withHelp ("write it as " ++ key ++ " = value") $
                   problem f ln TomlSyntax ce 1 "" "expected = after the key")

-- ============================================================================
-- The document
-- ============================================================================

||| Read a TOML document: its tables in file order (the top-level keys first,
||| as a table with path []), and every problem found. A line with a problem
||| is skipped, so later lines are still checked.
export
parseToml : (file : String) -> (text : String) -> (List Table, List Diagnostic)
parseToml f text = go 1 (lines text) (MkTable [] False 0 0 0 []) [] [] []
  where
    close : Table -> Table
    close t = { tEntries $= reverse } t

    firstLine : String -> List Entry -> Maybe Nat
    firstLine k es = map eLine (find (\e => e.eKey == k) es)

    go : Nat -> List String -> (cur : Table) -> (done : List Table)
      -> (seen : List (List String, Bool, Nat)) -> (errs : List Diagnostic)
      -> (List Table, List Diagnostic)
    go _ [] cur done _ errs = (reverse (close cur :: done), reverse errs)
    go ln (l :: ls) cur done seen errs =
      case parseLine f ln l of
        Left d => go (S ln) ls cur done seen (d :: errs)
        Right Blank => go (S ln) ls cur done seen errs
        Right (Header path isArray c w) =>
          let next = MkTable path isArray ln c w []
              clash = find (\(p, a, _) => p == path && (not isArray || not a)) seen
              errs' = case clash of
                        Just (_, a, first) =>
                          (withNote ("first defined on line " ++ show first) $
                           withHelp (if a || isArray
                                       then "use [[" ++ pathName path ++ "]] for every entry, or [" ++ pathName path ++ "] once"
                                       else "merge the two into one [" ++ pathName path ++ "] table")
                                    (problem f ln TomlDuplicate c w "" ("table [" ++ pathName path ++ "] is defined twice")))
                          :: errs
                        Nothing => errs
          in go (S ln) ls next (close cur :: done) ((path, isArray, ln) :: seen) errs'
        Right (KeyValue e) =>
          case firstLine e.eKey cur.tEntries of
            Just first =>
              let d = withNote ("first set on line " ++ show first) $
                      withHelp "delete one of the two" $
                      problem f ln TomlDuplicate e.eCol (length e.eKey) "" ("key \"" ++ e.eKey ++ "\" is set twice in this table")
              in go (S ln) ls cur done seen (d :: errs)
            Nothing => go (S ln) ls ({ tEntries $= (e ::) } cur) done seen errs
