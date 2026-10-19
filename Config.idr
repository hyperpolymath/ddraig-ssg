-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Config.idr - the site configuration (ddraig.toml) and data files (data/).
--
-- Toml.idr reads the text (the untrusted, covering side). This module decides,
-- with a TOTAL function, whether the tables form a valid site configuration:
-- `validateConfig` either returns the configuration or every problem in it,
-- each located at its file, line and key, in the same way that State.idr's
-- `validateState` decides STATE descriptiles (ARCHITECTURE.adoc, O1). The
-- schema, precedence rules and template variables are in CONFIGURATION.adoc.

module Config

import Data.List
import Data.Maybe
import Data.String
import Diagnostic
import Toml

%default total

-- ============================================================================
-- The configuration
-- ============================================================================

public export
record MenuItem where
  constructor MkMenuItem
  itemName : String
  itemUrl  : String

public export
record SiteConfig where
  constructor MkSiteConfig
  siteTitle       : Maybe String
  siteBaseUrl     : Maybe String
  siteLanguage    : Maybe String
  siteDescription : Maybe String
  siteAuthor      : Maybe String
  siteMenus       : List (String, List MenuItem)   -- menu name, entries in order
  siteExtra       : List (String, TValue)          -- [extra], in order

||| The configuration of a site without ddraig.toml: everything unset.
export
noConfig : SiteConfig
noConfig = MkSiteConfig Nothing Nothing Nothing Nothing Nothing [] []

||| The keys [site] accepts.
export
siteKeys : List String
siteKeys = ["title", "base_url", "language", "description", "author"]

menuKeys : List String
menuKeys = ["name", "url"]

-- ============================================================================
-- Checks on values (total)
-- ============================================================================

describe : TValue -> String
describe (TStr _)  = "a string"
describe (TInt _)  = "a number"
describe (TBool _) = "true/false"
describe (TArr _)  = "a list"

splitDash : List Char -> List (List Char)
splitDash cs = go cs []
  where
    go : List Char -> List Char -> List (List Char)
    go []           acc = [reverse acc]
    go ('-' :: xs)  acc = reverse acc :: go xs []
    go (x :: xs)    acc = go xs (x :: acc)

||| A BCP 47-shaped language tag: two or three letters, then any number of
||| "-" and one to eight letters or digits ("en", "cy", "pt-BR", "zh-Hant").
export
validLanguage : String -> Bool
validLanguage s =
  case splitDash (unpack s) of
    (p :: rest) => let n = length p in
                   n >= 2 && n <= 3 && all isAlpha p && all sub rest
    []          => False
  where
    sub : List Char -> Bool
    sub xs = let n = length xs in n >= 1 && n <= 8 && all isAlphaNum xs

||| An absolute http:// or https:// address with a host and no spaces.
export
validBaseUrl : String -> Bool
validBaseUrl u =
  ((isPrefixOf "https://" u && length u > 8) || (isPrefixOf "http://" u && length u > 7))
    && not (any isSpace (unpack u))

-- ============================================================================
-- The configuration decision (total)
-- ============================================================================

-- A located diagnostic for an entry's key or value.
atKey : String -> Entry -> String -> Diagnostic -> Diagnostic
atKey f e label d = atPos f e.eLine e.eCol (length e.eKey) label d

atValue : String -> Entry -> String -> Diagnostic -> Diagnostic
atValue f e label d = atPos f e.eLine e.eVCol e.eVLen label d

atHeader : String -> Table -> String -> Diagnostic -> Diagnostic
atHeader f t label d = atPos f t.tLine t.tCol t.tWidth label d

-- The entry must hold a string.
needString : String -> String -> Entry -> List Diagnostic
needString f tableName e = case e.eVal of
  TStr _ => []
  v      => [ withHelp ("write it in quotes: " ++ e.eKey ++ " = \"...\"") $
              atValue f e ("this is " ++ describe v) $
              diagError ConfigWrongType
                ("\"" ++ e.eKey ++ "\" in " ++ tableName ++ " must be a string") ]

checkSiteEntry : String -> Entry -> List Diagnostic
checkSiteEntry f e =
  if not (elem e.eKey siteKeys)
    then [ withHelp "values of your own, for templates, go under [extra]" $
           withHelps (didYouMean e.eKey siteKeys) $
           atKey f e "not a [site] key" $
           diagError ConfigUnknownKey ("unknown key \"" ++ e.eKey ++ "\" in [site]") ]
  else case needString f "[site]" e of
    (d :: ds) => d :: ds
    [] => case (e.eKey, e.eVal) of
      ("base_url", TStr u) =>
        if validBaseUrl u then []
        else [ withHelp "start it with https:// (or http://), e.g. \"https://example.org\"" $
               atValue f e "not an absolute http(s) address" $
               diagError ConfigBadValue ("base_url must be an absolute http:// or https:// address") ]
      ("language", TStr l) =>
        if validLanguage l then []
        else [ withHelp "use a language tag such as \"en\", \"cy\" or \"pt-BR\"" $
               atValue f e "not a language tag" $
               diagError ConfigBadValue ("language \"" ++ l ++ "\" is not a language tag") ]
      _ => []

checkMenuEntry : String -> String -> Table -> List Diagnostic
checkMenuEntry f name t =
  concatMap entry t.tEntries ++ missing "name" ++ missing "url"
  where
    tableName : String
    tableName = "[[menus." ++ name ++ "]]"
    entry : Entry -> List Diagnostic
    entry e =
      if elem e.eKey menuKeys then needString f tableName e
      else [ withHelps (didYouMean e.eKey menuKeys) $
             atKey f e "not a menu key" $
             diagError ConfigUnknownKey ("unknown key \"" ++ e.eKey ++ "\" in a menu entry; a menu entry takes name and url") ]
    missing : String -> List Diagnostic
    missing k =
      if any (\e => e.eKey == k) t.tEntries then []
      else [ withHelp ("add " ++ k ++ " = \"...\" to this entry") $
             atHeader f t ("this entry has no " ++ k) $
             diagError ConfigMenuEntry ("menu entry in " ++ tableName ++ " has no " ++ k) ]

knownTables : List String
knownTables = ["site", "extra", "menus.main"]

checkTable : String -> Table -> List Diagnostic
checkTable f t =
  case (t.tPath, t.tArray) of
    ([], _) => map outside t.tEntries
    (["site"], False) => concatMap (checkSiteEntry f) t.tEntries
    (["extra"], False) => []
    (["menus", name], True) => checkMenuEntry f name t
    (["menus", name], False) =>
      [ withHelp ("write [[menus." ++ name ++ "]], once for each entry in the menu") $
        atHeader f t "a menu needs double brackets" $
        diagError ConfigUnknownTable ("[menus." ++ name ++ "] must be written [[menus." ++ name ++ "]]") ]
    (["menus"], _) =>
      [ withHelp "name the menu: [[menus.main]], then name = \"...\" and url = \"...\"" $
        atHeader f t "which menu?" $
        diagError ConfigUnknownTable "a menu needs a name, as in [[menus.main]]" ]
    (path, True) =>
      [ withHelp "the tables are [site], [extra] and [[menus.<name>]]" $
        withHelps (didYouMean (pathName path) knownTables) $
        atHeader f t "not a ddraig table" $
        diagError ConfigUnknownTable ("unknown table [[" ++ pathName path ++ "]]") ]
    (path, False) =>
      [ withHelp "the tables are [site], [extra] and [[menus.<name>]]" $
        withHelps (didYouMean (pathName path) knownTables) $
        atHeader f t "not a ddraig table" $
        diagError ConfigUnknownTable ("unknown table [" ++ pathName path ++ "]") ]
  where
    outside : Entry -> Diagnostic
    outside e =
      withHelp ("put it under a table: site settings go under [site], your own values under [extra]") $
      withHelps (if elem e.eKey siteKeys then [] else map (\s => "did you mean \"" ++ s ++ "\" under [site]?") (maybe [] pure (closest e.eKey siteKeys))) $
      atKey f e "outside any table" $
      diagError ConfigUnknownKey ("key \"" ++ e.eKey ++ "\" is not inside a table")

-- Assemble the configuration from tables already checked.
assemble : List Table -> SiteConfig
assemble ts =
  MkSiteConfig (str "title") (str "base_url") (str "language") (str "description")
               (str "author") (menus ts []) extras
  where
    siteEntries : List Entry
    siteEntries = concatMap (\t => if t.tPath == ["site"] && not t.tArray then t.tEntries else []) ts
    str : String -> Maybe String
    str k = case find (\e => e.eKey == k) siteEntries of
              Just e => case e.eVal of
                          TStr s => Just s
                          _      => Nothing
              Nothing => Nothing
    extras : List (String, TValue)
    extras = concatMap (\t => if t.tPath == ["extra"] && not t.tArray
                                then map (\e => (e.eKey, e.eVal)) t.tEntries else []) ts
    item : Table -> MenuItem
    item t = MkMenuItem (get "name") (get "url")
      where get : String -> String
            get k = case find (\e => e.eKey == k) t.tEntries of
                      Just e => case e.eVal of
                                  TStr s => s
                                  _      => ""
                      Nothing => ""
    -- group [[menus.<name>]] tables by name, keeping first-appearance order
    menus : List Table -> List (String, List MenuItem) -> List (String, List MenuItem)
    menus [] acc = reverse acc
    menus (t :: rest) acc =
      case (t.tPath, t.tArray) of
        (["menus", name], True) =>
          if any (\(n, _) => n == name) acc
            then menus rest (map (\(n, is) => if n == name then (n, is ++ [item t]) else (n, is)) acc)
            else menus rest ((name, [item t]) :: acc)
        _ => menus rest acc

||| The configuration decision: the site configuration the tables describe, or
||| every problem in them, located at their file, line and key. TOTAL.
export
validateConfig : (file : String) -> List Table -> Either (List Diagnostic) SiteConfig
validateConfig f ts =
  case concatMap (checkTable f) ts of
    [] => Right (assemble ts)
    ds => Left ds

-- ============================================================================
-- Template variables
-- ============================================================================

||| A data file: data/<name>.toml.
public export
record DataFile where
  constructor MkDataFile
  dataName   : String
  dataTables : List Table

||| The variables templates can use, with their values, named as templates
||| write them: site.title ... site.extra.<key>, and data.<file>.<key> (with
||| table names in between for keys inside a [table]). `base` is the base URL
||| in effect (the command line's, else the configuration's).
export
templateVars : SiteConfig -> (base : String) -> List DataFile -> List (String, TValue)
templateVars c base ds =
  [ ("site.title",       TStr (fromMaybe "" c.siteTitle))
  , ("site.base_url",    TStr base)
  , ("site.language",    TStr (fromMaybe "en" c.siteLanguage))
  , ("site.description", TStr (fromMaybe "" c.siteDescription))
  , ("site.author",      TStr (fromMaybe "" c.siteAuthor)) ]
  ++ map (\(k, v) => ("site.extra." ++ k, v)) c.siteExtra
  ++ concatMap dataVars ds
  where
    dataVars : DataFile -> List (String, TValue)
    dataVars d = concatMap (\t => if t.tArray then [] else
                                    map (\e => ("data." ++ pathName (d.dataName :: t.tPath ++ [e.eKey]), e.eVal))
                                        t.tEntries)
                           d.dataTables

-- One variable's text, or why it has none.
valueText : (escape : String -> String) -> TValue -> Maybe String
valueText esc (TStr s)      = Just (esc s)
valueText _   (TInt n)      = Just (show n)
valueText _   (TBool True)  = Just "true"
valueText _   (TBool False) = Just "false"
valueText _   (TArr _)      = Nothing

-- Characters up to "}}" on the same line: (inside, after the braces).
untilClose : List Char -> List Char -> Maybe (List Char, List Char)
untilClose []                  _   = Nothing
untilClose ('\n' :: _)         _   = Nothing
untilClose ('}' :: '}' :: rest) acc = Just (reverse acc, rest)
untilClose (c :: rest)         acc = untilClose rest (c :: acc)

||| Replace every {{site...}} and {{data...}} variable in a template's text
||| with its value (strings escaped by `escape`), and report each unknown
||| variable, and each that holds a list, at its file, line and column. Other
||| {{...}} placeholders are left for the page step.
export covering
resolveVars : (escape : String -> String) -> (vars : List (String, TValue))
           -> (file : String) -> (text : String) -> (String, List Diagnostic)
resolveVars esc vars f text = go 1 1 (unpack text) [] []
  where
    one : Nat -> Nat -> Nat -> String -> (String, List Diagnostic)
    one ln col width name =
      case lookup name vars of
        Just v => case valueText esc v of
          Just s  => (s, [])
          Nothing => ("", [ withHelp "show one item at a time, or use a string instead of a list" $
                            atPos f ln col width "this is a list" $
                            diagError TemplateNotText ("{{" ++ name ++ "}} is a list, which a template cannot show as text") ])
        Nothing => ("", [ withHelp "site variables come from ddraig.toml, data variables from data/<file>.toml" $
                          withHelps (didYouMean name (map fst vars)) $
                          atPos f ln col width "no such variable" $
                          diagError TemplateUnknownVariable ("unknown template variable {{" ++ name ++ "}}") ])

    go : Nat -> Nat -> List Char -> List Char -> List Diagnostic -> (String, List Diagnostic)
    go _  _   []                  acc ds = (pack (reverse acc), reverse ds)
    go ln col ('{' :: '{' :: rest) acc ds =
      case untilClose rest [] of
        Just (inside, after) =>
          let name = trim (pack inside) in
          if isPrefixOf "site." name || isPrefixOf "data." name
            then let width = length inside + 4
                     (txt, found) = one ln col width name
                 in go ln (col + width) after (reverse (unpack txt) ++ acc) (found ++ ds)
            else go ln (col + 2) rest ('{' :: '{' :: acc) ds
        Nothing => go ln (col + 2) rest ('{' :: '{' :: acc) ds
    go ln _   ('\n' :: rest) acc ds = go (S ln) 1 rest ('\n' :: acc) ds
    go ln col (c :: rest)    acc ds = go ln (S col) rest (c :: acc) ds
