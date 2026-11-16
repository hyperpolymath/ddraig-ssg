-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-- Ddraig.idr - Dependently typed static site generator in Idris 2
--
-- "Ddraig" (Welsh for Dragon) - Types that breathe fire

module Ddraig

import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System
import System.Clock
import System.Directory
import System.File

import Html
import State
import Attest
import Diagnostic
import Toml
import Config

%default covering

ddraigVersion : String
ddraigVersion = "0.2.0"

-- ============================================================================
-- Frontmatter Types
-- ============================================================================

public export
record Frontmatter where
  constructor MkFrontmatter
  title : String
  date : String
  tags : List String
  draft : Bool
  template : String
  description : String
  slug : String
  brand : String
  lang : String     -- overrides [site] language for this page
  author : String   -- overrides [site] author for this page

export
emptyFrontmatter : Frontmatter
emptyFrontmatter = MkFrontmatter "" "" [] False "default" "" "" "" "" ""

-- A built page, retained for sitemap/feed generation.
public export
record Page where
  constructor MkPage
  url : String       -- site-relative URL, e.g. /blog/post.html
  fm  : Frontmatter

-- ============================================================================
-- String Utilities (all self-contained)
-- ============================================================================

strHasPrefix : String -> String -> Bool
strHasPrefix pre str = isPrefixOf pre str

strDropPrefix : String -> String -> String
strDropPrefix pre str =
  if strHasPrefix pre str
     then substr (length pre) (length str) str
     else str

strHasSuffix : String -> String -> Bool
strHasSuffix suf str = isSuffixOf suf str

strSplitOn : Char -> String -> List String
strSplitOn delim str = go (unpack str) [] []
  where
    go : List Char -> List Char -> List String -> List String
    go [] acc result = reverse (pack (reverse acc) :: result)
    go (x :: xs) acc result =
      if x == delim
         then go xs [] (pack (reverse acc) :: result)
         else go xs (x :: acc) result

strEscape : String -> String
strEscape s = concat (map esc (unpack s))
  where
    esc : Char -> String
    esc '<' = "&lt;"
    esc '>' = "&gt;"
    esc '&' = "&amp;"
    esc '"' = "&quot;"
    esc c = singleton c

-- Count leading spaces (treat a tab as two spaces for indentation purposes).
leadingIndent : String -> Nat
leadingIndent s = go (unpack s) 0
  where
    go : List Char -> Nat -> Nat
    go (' '  :: cs) n = go cs (S n)
    go ('\t' :: cs) n = go cs (S (S n))
    go _            n = n

strReplace : String -> String -> String -> String
strReplace hay needle rep =
  if needle == "" then hay
  else pack (go (unpack hay))
  where
    nlen : Nat
    nlen = length needle
    go : List Char -> List Char
    go [] = []
    go cs@(c :: rest) =
      if isPrefixOf needle (pack cs)
         then unpack rep ++ go (drop nlen cs)
         else c :: go rest

-- Slugify heading text into an id (lowercase, alnum + dashes).
slugify : String -> String
slugify s = pack (squash (map norm (unpack (toLower s))))
  where
    norm : Char -> Char
    norm c = if isAlphaNum c then c else '-'
    -- collapse runs of '-' and trim leading/trailing
    squash : List Char -> List Char
    squash cs = trimDash (collapse cs False)
      where
        collapse : List Char -> Bool -> List Char
        collapse [] _ = []
        collapse ('-' :: rest) True  = collapse rest True
        collapse ('-' :: rest) False = '-' :: collapse rest True
        collapse (x   :: rest) _     = x   :: collapse rest False
        trimDash : List Char -> List Char
        trimDash xs = reverse (dropDash (reverse (dropDash xs)))
          where dropDash : List Char -> List Char
                dropDash ('-' :: r) = r
                dropDash other      = other

-- ============================================================================
-- Frontmatter Parser
-- ============================================================================

parseFmLine : String -> Frontmatter -> Frontmatter
parseFmLine line fm =
  case break (== ':') (unpack line) of
    (_, []) => fm
    (keyChars, _ :: valueChars) =>
      let key = trim (pack keyChars)
          value = trim (pack valueChars)
      in case key of
           "title" => { title := value } fm
           "date" => { date := value } fm
           "template" => { template := value } fm
           "layout" => { template := value } fm
           "description" => { description := value } fm
           "slug" => { slug := value } fm
           "site" => { brand := value } fm
           "brand" => { brand := value } fm
           "lang" => { lang := value } fm
           "author" => { author := value } fm
           "draft" => { draft := (value == "true" || value == "yes") } fm
           "tags" =>
             let tagStr = if strHasPrefix "[" value
                            then substr 1 (length value `minus` 2) value
                            else value
                 tagList = map trim (strSplitOn ',' tagStr)
             in { tags := filter (\s => length s > 0) tagList } fm
           _ => fm

-- Tolerate leading blank lines and a single leading HTML comment before `---`.
export
parseFrontmatter : String -> (Frontmatter, String)
parseFrontmatter content =
  let allLines = skipPreamble (lines content)
  in case allLines of
       [] => (emptyFrontmatter, content)
       (first :: rest) =>
         if trim first /= "---"
            then (emptyFrontmatter, content)
            else findEnd rest emptyFrontmatter
  where
    isComment : String -> Bool
    isComment l = let t = trim l in strHasPrefix "<!--" t
    skipPreamble : List String -> List String
    skipPreamble [] = []
    skipPreamble (l :: ls) =
      if trim l == "" then skipPreamble ls
      else if isComment l then ls  -- drop the one comment line; keep rest
      else (l :: ls)
    findEnd : List String -> Frontmatter -> (Frontmatter, String)
    findEnd [] fm = (fm, "")
    findEnd (l :: ls) fm =
      if trim l == "---"
         then (fm, unlines ls)
         else findEnd ls (parseFmLine l fm)

-- ============================================================================
-- Inline Markdown (bold/italic/code/strike/links/images)
--
-- Inline content is parsed into the typed, total Html core (Html.idr) and
-- rendered from there. This is the build pipeline's trust boundary in
-- miniature: `inlineNodes` is the untrusted (covering) parser; `Html.render`
-- is the total renderer. Every image therefore flows through `Html.mkAlt`, so
-- informative images provably carry non-blank alt text. An image with no alt
-- is decorative (alt="") only when the author says so with `{.decorative}`
-- straight after it; otherwise it is an `UnlabelledImg`, which fails
-- certification and is reported as DDR0801. ddraig never guesses.
-- All inline HTML assembly now lives in the typed core, not string concat.
-- ============================================================================

-- Parse one line's inline Markdown into typed Html nodes. Consecutive plain
-- characters are batched into a single Text node (held reversed in `buf`).
inlineNodes : String -> List Html
inlineNodes text = go (unpack text) []
  where
    -- read until a delimiter substring is found; returns (before, after-delim).
    splitOnStr : List Char -> List Char -> Maybe (List Char, List Char)
    splitOnStr delim cs = goS cs []
      where
        goS : List Char -> List Char -> Maybe (List Char, List Char)
        goS [] _ = Nothing
        goS rest@(c :: more) acc =
          if isPrefixOf (pack delim) (pack rest)
             then Just (reverse acc, drop (length delim) rest)
             else goS more (c :: acc)
    -- read a balanced "[..]" then "(..)" for links/images.
    readLink : List Char -> Maybe (String, String, List Char)
    readLink cs =
      case splitOnStr [']'] cs of
        Nothing => Nothing
        Just (txt, afterB) =>
          case afterB of
            ('(' :: afterP) =>
              case splitOnStr [')'] afterP of
                Nothing => Nothing
                Just (url, rest) => Just (pack txt, pack url, rest)
            _ => Nothing
    -- the trust boundary: untrusted alt text enters via the total `mkAlt`.
    imageNode : (alt : String) -> (url : String) -> (decorative : Bool) -> Html
    imageNode alt url decorative =
      case mkAlt alt of
        Just a  => Img url a            -- informative: proof-carrying non-blank alt
        Nothing => if decorative
                      then DecorativeImg url  -- marked {.decorative}: explicit alt=""
                      else UnlabelledImg url  -- no alt, no marker: an error, not a guess
    -- `{.decorative}` straight after an image marks it decorative.
    decorativeMark : List Char
    decorativeMark = unpack "{.decorative}"
    takeMark : List Char -> (Bool, List Char)
    takeMark cs = if isPrefixOf decorativeMark cs
                     then (True, drop (length decorativeMark) cs)
                     else (False, cs)
    -- flush the buffered plain-text run (reversed) as one Text node.
    flush : List Char -> List Html -> List Html
    flush []  rest = rest
    flush buf rest = Text (pack (reverse buf)) :: rest
    go : List Char -> List Char -> List Html
    go [] buf = flush buf []
    -- image: ![alt](url)
    go ('!' :: '[' :: rest) buf =
      case readLink rest of
        Just (alt, url, after) =>
          let (dec, after') = takeMark after in
          flush buf (imageNode alt url dec :: go after' [])
        Nothing => go ('[' :: rest) ('!' :: buf)
    -- link: [text](url)  (link text is itself parsed for inline markup)
    go ('[' :: rest) buf =
      case readLink rest of
        Just (txt, url, after) =>
          flush buf (Elem "a" [("href", url)] (inlineNodes txt) :: go after [])
        Nothing => go rest ('[' :: buf)
    -- strikethrough: ~~text~~
    go ('~' :: '~' :: rest) buf =
      case splitOnStr ['~','~'] rest of
        Just (inner, after) =>
          flush buf (Elem "del" [] (inlineNodes (pack inner)) :: go after [])
        Nothing => go rest ('~' :: '~' :: buf)
    -- bold: **text**
    go ('*' :: '*' :: rest) buf =
      case splitOnStr ['*','*'] rest of
        Just (inner, after) =>
          flush buf (Elem "strong" [] (inlineNodes (pack inner)) :: go after [])
        Nothing => go rest ('*' :: '*' :: buf)
    -- italic: *text*
    go ('*' :: rest) buf =
      case splitOnStr ['*'] rest of
        Just (inner, after) =>
          flush buf (Elem "em" [] (inlineNodes (pack inner)) :: go after [])
        Nothing => go rest ('*' :: buf)
    -- inline code: `code` (verbatim; Text escapes it and never re-parses)
    go ('`' :: rest) buf =
      case splitOnStr ['`'] rest of
        Just (inner, after) =>
          flush buf (Elem "code" [] [Text (pack inner)] :: go after [])
        Nothing => go rest ('`' :: buf)
    -- plain character: accumulate; <, >, & are escaped by Text on render.
    go (c :: rest) buf = go rest (c :: buf)

-- Render inline Markdown to an HTML string via the typed core. Signature is
-- unchanged, so every caller (paragraphs, headings, lists, tables, quotes,
-- the TOC) now emits typed-and-rendered HTML with no edits to those sites.
doInline : String -> String
doInline text = renderForest (inlineNodes text)

-- ============================================================================
-- Block-level Markdown Parser
-- ============================================================================

-- Headings collected for TOC: (level, text, slug)
record Heading where
  constructor MkHeading
  level : Nat
  text  : String
  hslug : String

-- (The former string-accumulating ParserState machine, its close-helpers, the
-- list-stack machinery, renderTable, step and parseAll have been replaced by
-- the recursive-descent typed parser further below, which builds an Html tree
-- and renders it via the total Html.render.)

-- A thematic break: a trimmed line of three or more of the same '-', '*' or
-- '_'. (Previously only a handful of exact strings matched, so e.g. "------"
-- was not recognised.)
isHRule : String -> Bool
isHRule s =
  let t = trim s
  in length t >= 3 && sameMark (unpack t)
  where sameMark : List Char -> Bool
        sameMark [] = False
        sameMark (c :: cs) = (c == '-' || c == '*' || c == '_') && all (== c) cs

-- Does a line look like raw HTML block (starts with a tag)?
isRawHtml : String -> Bool
isRawHtml s =
  let t = trim s
  in case unpack t of
       ('<' :: '!' :: _) => False  -- comment / doctype: let comments pass too actually
       ('<' :: c :: _) => isAlpha c || c == '/'
       _ => False

headingLevel : String -> Maybe (Nat, String)
headingLevel s =
  let t = trim s
  in go 0 (unpack t)
  where
    go : Nat -> List Char -> Maybe (Nat, String)
    go n ('#' :: cs) = go (S n) cs
    go 0 _ = Nothing
    go n (' ' :: cs) = if n <= 6 then Just (n, trim (pack cs)) else Nothing
    go n [] = if n <= 6 then Just (n, "") else Nothing
    go _ _ = Nothing

-- ordered list item?  "<n>. text"   returns text
orderedItem : String -> Maybe String
orderedItem s =
  let t = ltrim s
  in case span isDigit (unpack t) of
       ([], _) => Nothing
       (_, ('.' :: ' ' :: rest)) => Just (trim (pack rest))
       _ => Nothing

unorderedItem : String -> Maybe String
unorderedItem s =
  let t = ltrim s
  in if strHasPrefix "- " t then Just (trim (strDropPrefix "- " t))
     else if strHasPrefix "* " t then Just (trim (strDropPrefix "* " t))
     else if strHasPrefix "+ " t then Just (trim (strDropPrefix "+ " t))
     else Nothing

-- Table detection: a line of the form | --- | --- | (separator)
isTableSep : String -> Bool
isTableSep s =
  let t = trim s
  in strHasPrefix "|" t && all (\c => c == '|' || c == '-' || c == ':' || c == ' ') (unpack t)
     && any (== '-') (unpack t)

isTableRow : String -> Bool
isTableRow s = strHasPrefix "|" (trim s)

splitRow : String -> List String
splitRow s =
  let t = trim s
      t1 = if strHasPrefix "|" t then strDropPrefix "|" t else t
      t2 = if strHasSuffix "|" t1 then substr 0 (length t1 `minus` 1) t1 else t1
  in map trim (strSplitOn '|' t2)

-- ============================================================================
-- Line dispatcher.  Tables and code blocks need lookahead, so the top-level
-- parser passes the *list of remaining lines* and we consume as needed.
-- ============================================================================

-- A list-item line -> (indent, ordered?, content).
listItemAt : String -> Maybe (Nat, Bool, String)
listItemAt l =
  case orderedItem l of
    Just c  => Just (leadingIndent l, True, c)
    Nothing => case unorderedItem l of
                 Just c  => Just (leadingIndent l, False, c)
                 Nothing => Nothing

isFence : String -> Bool
isFence t = strHasPrefix "```" t

-- Is the first remaining line a table separator (| --- | --- |)?
nextIsSep : List String -> Bool
nextIsSep (s :: _) = isTableSep s
nextIsSep []       = False

-- Drop one leading "> " (or ">") from a (possibly indented) quote line.
stripQuote : String -> String
stripQuote l = trim (strDropPrefix ">" (trim l))

joinSpace : List String -> String
joinSpace []        = ""
joinSpace [x]       = x
joinSpace (x :: xs) = x ++ " " ++ joinSpace xs

-- Does a line continue a paragraph? (False at blanks and every block starter.)
isParaLine : String -> Bool
isParaLine x =
  let t = trim x in
  t /= "" && not (isFence t) && not (isHRule x) && not (isHeadingLine x)
    && not (isTableRow x) && not (isRawHtml x) && not (strHasPrefix ">" t)
    && not (isListLine x)
  where
    isHeadingLine : String -> Bool
    isHeadingLine y = case headingLevel y of Just _ => True; Nothing => False
    isListLine : String -> Bool
    isListLine y = case listItemAt y of Just _ => True; Nothing => False

-- The recursive-descent block parser. Each block becomes a typed Html node;
-- nesting (lists, blockquotes) is ordinary recursion. Returns the block nodes
-- plus the headings collected in document order (for the TOC).
mutual
  parseBlocks : List String -> (List Html, List Heading)
  parseBlocks [] = ([], [])
  parseBlocks (l :: ls) =
    let t = trim l in
    if t == "" then parseBlocks ls
    else if isFence t then
      let (node, rest) = parseFence l ls
          (bs, hs) = parseBlocks rest
      in (node :: bs, hs)
    else if isHRule l then
      let (bs, hs) = parseBlocks ls in (Void "hr" [] :: bs, hs)
    else case headingLevel l of
      Just (lvl, htext) =>
        let sl = slugify htext
            node = Elem ("h" ++ show lvl) [("id", sl)] (inlineNodes htext)
            (bs, hs) = parseBlocks ls
        in (node :: bs, MkHeading lvl htext sl :: hs)
      Nothing =>
        if isTableRow l && nextIsSep ls then
          let (node, rest) = parseTable l ls
              (bs, hs) = parseBlocks rest
          in (node :: bs, hs)
        else if isRawHtml l then
          let (bs, hs) = parseBlocks ls in (Raw l :: bs, hs)
        else if strHasPrefix ">" t then
          let (qls, rest) = span (\x => strHasPrefix ">" (trim x)) (l :: ls)
              (inner, ih) = parseBlocks (map stripQuote qls)
              (bs, hs) = parseBlocks rest
          in (Elem "blockquote" [] inner :: bs, ih ++ hs)
        else case listItemAt l of
          Just (ind, ord, _) =>
            let (node, rest) = parseList ind ord (l :: ls)
                (bs, hs) = parseBlocks rest
            in (node :: bs, hs)
          Nothing =>
            let (cont, rest) = span isParaLine ls
                text = joinSpace (map trim (l :: cont))
                (bs, hs) = parseBlocks rest
            in (Elem "p" [] (inlineNodes text) :: bs, hs)

  -- Fenced code: `l` is the opening fence; gather lines until the closing one.
  parseFence : String -> List String -> (Html, List String)
  parseFence l ls =
    let lang = trim (strDropPrefix "```" (trim l))
        (code, rest) = break (\x => isFence (trim x)) ls
        content = concatMap (\c => c ++ "\n") code
        attrs = if lang == "" then [] else [("class", "language-" ++ lang)]
    in (Elem "pre" [] [Elem "code" attrs [Text content]], drop 1 rest)

  -- Pipe table: `hdr` is the header row; `ls` starts with the separator row.
  parseTable : String -> List String -> (Html, List String)
  parseTable hdr ls =
    let headRow = Elem "tr" [] (map (\h => Elem "th" [("scope", "col")] (inlineNodes h)) (splitRow hdr))
        (rows, rest) = span isTableRow (drop 1 ls)
        body = map (\r => Elem "tr" [] (map (\c => Elem "td" [] (inlineNodes c)) (splitRow r))) rows
    in (Elem "table" [] [Elem "thead" [] [headRow], Elem "tbody" [] body], rest)

  -- A list at base indent + orderedness; `lns` starts with a matching item.
  parseList : Nat -> Bool -> List String -> (Html, List String)
  parseList base ord lns =
    let (items, rest) = collectItems base ord lns
    in (Elem (if ord then "ol" else "ul") [] items, rest)

  -- Collect <li>s at exactly `base` indent with the `ord` marker; a more
  -- indented following item becomes a nested list inside the preceding <li>.
  collectItems : Nat -> Bool -> List String -> (List Html, List String)
  collectItems _    _   [] = ([], [])
  collectItems base ord (l :: ls) =
    case listItemAt l of
      Nothing => ([], l :: ls)
      Just (ind, o, content) =>
        if ind /= base || o /= ord then ([], l :: ls)
        else
          let (nested, rest1) = collectNested base ls
              li = Elem "li" [] (inlineNodes content ++ nested)
              (more, rest2) = collectItems base ord rest1
          in (li :: more, rest2)

  collectNested : Nat -> List String -> (List Html, List String)
  collectNested _    [] = ([], [])
  collectNested base (l :: ls) =
    case listItemAt l of
      Just (ind, o, _) =>
        if ind > base
           then let (sub, rest) = parseList ind o (l :: ls) in ([sub], rest)
           else ([], l :: ls)
      Nothing => ([], l :: ls)

-- Result of parsing: HTML body + collected headings (in order) + the typed
-- blocks (retained so the build can run the O3 accessibility decision over them).
record MdResult where
  constructor MkMdResult
  body     : String
  toc      : List Heading
  blocks   : List Html

parseMarkdownFull : String -> MdResult
parseMarkdownFull content =
  let (blocks, heads) = parseBlocks (lines content)
  in MkMdResult (renderDoc blocks) heads blocks

export
parseMarkdown : String -> String
parseMarkdown content = (parseMarkdownFull content).body

-- Build a nested-ish TOC (flat <ul> with classes per level for simplicity).
buildToc : List Heading -> String
buildToc [] = ""
buildToc hs =
  "<nav class=\"toc\"><ul>\n"
    ++ concat (map item hs)
    ++ "</ul></nav>\n"
  where
    item : Heading -> String
    item h = "<li class=\"toc-l" ++ show h.level ++ "\">"
               ++ "<a href=\"#" ++ h.hslug ++ "\">" ++ doInline h.text ++ "</a></li>\n"

-- ============================================================================
-- Template Engine
-- ============================================================================

-- Canonical AAA default template (WCAG 2.2 AAA-capable engine-owned surface):
-- skip link, <html lang>, labelled landmarks, main#main, viewport, stylesheet
-- link. Placeholders: {{title}} {{brand}} {{description}} {{date}} {{toc}}
-- {{root}} {{content}} — content substituted LAST so its body HTML is never
-- reprocessed. {{root}} is the site's path prefix (see `basePath`), so the
-- root-relative stylesheet and home links also work under a sub-path.
defTemplate : String
defTemplate = """
<!DOCTYPE html>
<html lang="{{lang}}" prefix="rdf: http://www.w3.org/1999/02/22-rdf-syntax-ns# rdfs: http://www.w3.org/2000/01/rdf-schema# owl: http://www.w3.org/2002/07/owl# schema: http://schema.org/">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title property="schema:name">{{title}}</title>
  <meta name="description" property="schema:description" content="{{description}}">
  <meta name="color-scheme" content="light dark">
  <link rel="canonical" href="{{canonical}}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="{{brand}}">
  <meta property="og:title" content="{{title}}">
  <meta property="og:description" content="{{description}}">
  <meta property="og:url" content="{{canonical}}">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="{{title}}">
  <meta name="twitter:description" content="{{description}}">
  <link rel="stylesheet" href="{{root}}/assets/style.css">
</head>
<body typeof="schema:WebPage">
  <a class="skip-link" href="#main">Skip to content</a>

  <header class="site-header" role="banner">
    <nav class="container nav" aria-label="Primary" role="navigation" typeof="schema:SiteNavigationElement">
      <a class="brand" href="{{root}}/" property="schema:url"><span property="schema:name">{{brand}}</span></a>
      <ul class="nav-links">
        {{menu}}
      </ul>
    </nav>
  </header>

  <main id="main" class="container" tabindex="-1" role="main">
    <article class="prose" role="article" typeof="schema:Article">
      <meta property="schema:datePublished" content="{{date}}">
      {{content}}
    </article>
  </main>

  <footer class="site-footer" role="contentinfo">
    <div class="container">
      <p class="muted">Built with ddraig-ssg &middot; <time property="schema:dateModified">{{date}}</time></p>
    </div>
  </footer>
</body>
</html>
"""

-- Canonical AAA default stylesheet (contrast-verified >= 7:1 palette,
-- :focus-visible, reduced-motion, reflow, target-size). Written to
-- <out>/assets/style.css during build unless the site supplies its own.
defStylesheet : String
defStylesheet = """
/* SPDX-License-Identifier: MPL-2.0 */
/* Copyright (c) 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> */
/*
 * Canonical accessible theme for ddraig-ssg.
 * Target: WCAG 2.2 AAA on the engine-owned surface.
 * All text/link/UI colours are contrast-verified (see ACCESSIBILITY-CHECKLIST):
 *   light: body #1a1b26/17.1:1, muted #3a3d4d/10.7:1, link #3730a3/9.9:1
 *   dark : body #e6e8f2/15.6:1, muted #a0a4bd/7.75:1, link #b9c2ff/11.1:1
 * All >= 7:1 (AAA 1.4.6). Focus ring >= 3:1 (2.4.11/2.4.13).
 */

:root {
  --bg: #ffffff;
  --bg-soft: #f4f5f9;
  --bg-code: #eceef5;
  --fg: #1a1b26;          /* 17.09:1 on --bg */
  --fg-muted: #3a3d4d;    /* 10.74:1 on --bg (AAA for normal text) */
  --link: #3730a3;        /*  9.93:1 on --bg */
  --link-hover: #1f1b6b;
  --border: #5a5e73;      /* 4.9:1 — non-text UI, needs >=3:1 (1.4.11) */
  --focus: #3730a3;       /* focus ring, 9.93:1 vs --bg */
  --radius: 6px;
  --maxw: 70rem;
  --measure: 38rem;       /* readable line length */
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0e0f1a;
    --bg-soft: #181a2a;
    --bg-code: #1c1f33;
    --fg: #e6e8f2;        /* 15.60:1 on --bg */
    --fg-muted: #a0a4bd;  /*  7.75:1 on --bg */
    --link: #b9c2ff;      /* 11.09:1 on --bg */
    --link-hover: #dde2ff;
    --border: #8c91ad;    /* >=3:1 vs --bg */
    --focus: #b9c2ff;     /* 11.09:1 vs --bg */
  }
}

/* 1.4.12 text spacing: never clip when users override; use rem + generous line-height. */
*, *::before, *::after { box-sizing: border-box; }
html { font-size: 100%; -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  font-size: 1.0625rem;
  line-height: 1.6;            /* >= 1.5 (1.4.12) */
  color: var(--fg);
  background: var(--bg);
  overflow-wrap: break-word;   /* 1.4.10 reflow: no horizontal scroll at 320px */
}
p, li { max-width: var(--measure); }
p { margin: 0 0 1rem; }        /* paragraph spacing >= 2x font (1.4.12) */

/* 2.4.1 skip link — visible on focus, high contrast, large target. */
.skip-link {
  position: absolute; left: -9999px; top: 0;
  background: var(--link); color: #ffffff;
  padding: .75rem 1.25rem; border-radius: 0 0 var(--radius) 0;
  font-weight: 600; z-index: 100; min-height: 44px; line-height: 1.4;
}
.skip-link:focus { left: 0; }

/* 2.4.7/2.4.11/2.4.13 visible focus — thick, offset, >=3:1, never removed. */
:focus-visible {
  outline: 3px solid var(--focus);
  outline-offset: 2px;
  border-radius: 2px;
}
/* keep a focus indicator even for browsers without :focus-visible */
a:focus, button:focus, input:focus, [tabindex]:focus { outline: 3px solid var(--focus); outline-offset: 2px; }

.container { width: 100%; max-width: var(--maxw); margin-inline: auto; padding-inline: 1.25rem; }

/* Header / nav landmark */
.site-header { border-bottom: 1px solid var(--border); }
.nav { display: flex; flex-wrap: wrap; align-items: center; gap: 1rem; padding-block: .75rem; }
.brand { font-weight: 700; font-size: 1.2rem; color: var(--fg); text-decoration: none; }
.nav-links { list-style: none; display: flex; flex-wrap: wrap; gap: .5rem 1.25rem; margin: 0; padding: 0; }
/* 2.5.8/2.5.5 target size: interactive nav targets >= 44x44. */
.nav-links a, .brand { display: inline-flex; align-items: center; min-height: 44px; }

/* 1.4.1 use of colour: links are underlined, not colour-only. */
a { color: var(--link); text-decoration: underline; text-underline-offset: 2px; }
a:hover { color: var(--link-hover); }
.brand, .nav-links a { text-decoration: none; }
.nav-links a:hover, .nav-links a:focus { text-decoration: underline; }

main { display: block; }
.prose { padding-block: 2rem; }
.prose h1 { font-size: 2rem; line-height: 1.25; margin: 0 0 1rem; }
.prose h2 { font-size: 1.5rem; line-height: 1.3; margin: 2rem 0 .75rem; }
.prose h3 { font-size: 1.25rem; margin: 1.5rem 0 .5rem; }
.prose :is(h1,h2,h3,h4) { max-width: var(--measure); }

/* Code */
code { background: var(--bg-code); padding: .15em .35em; border-radius: 4px; font-size: .9em; }
pre { background: var(--bg-code); padding: 1rem; border-radius: var(--radius); overflow-x: auto; }
pre code { background: none; padding: 0; }

/* Tables — caption + scoped headers handled in markup; styling here. */
.prose table { border-collapse: collapse; width: 100%; max-width: 100%; margin: 1rem 0; }
.prose caption { text-align: left; font-weight: 600; color: var(--fg-muted); padding: .5rem 0; }
.prose th, .prose td { border: 1px solid var(--border); padding: .5rem .75rem; text-align: left; }
.prose th { background: var(--bg-soft); }

blockquote {
  margin: 1rem 0; padding: .5rem 1rem; border-left: 4px solid var(--border);
  color: var(--fg-muted); background: var(--bg-soft);
}

img { max-width: 100%; height: auto; }
hr { border: none; border-top: 1px solid var(--border); margin: 2rem 0; }

.muted { color: var(--fg-muted); }
.toc { font-size: .95rem; }

.site-footer { border-top: 1px solid var(--border); margin-top: 3rem; padding-block: 1.5rem; color: var(--fg-muted); font-size: .95rem; }
.site-footer a { color: var(--link); }

/* 2.3.3 / user comfort: honour reduced-motion. */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: .001ms !important; animation-iteration-count: 1 !important; transition-duration: .001ms !important; scroll-behavior: auto !important; }
}

/* 1.4.10 reflow: stack nav on narrow viewports, no fixed widths. */
@media (max-width: 30rem) {
  .nav { gap: .5rem; }
  body { font-size: 1rem; }
}
"""

-- Resolve partial includes: {{> name}} -> contents of templates/partials/name.html
-- (done in IO before substitution).
-- Remove any unfilled "{{ ... }}" placeholders so none leak into output.
-- Run before {{content}} substitution so author content braces are untouched.
-- The {{content}} marker is preserved (substituted afterwards); every other
-- "{{ ... }}" is removed.
stripPlaceholders : String -> String
stripPlaceholders s = pack (go (unpack s))
  where
    -- return the list following the next "}}" (or [] if none)
    afterClose : List Char -> List Char
    afterClose [] = []
    afterClose ('}' :: '}' :: rest) = rest
    afterClose (_ :: rest) = afterClose rest
    go : List Char -> List Char
    go [] = []
    go cs@(c :: rest) =
      if isPrefixOf "{{content}}" (pack cs)
         then unpack "{{content}}" ++ go (drop 11 cs)
      else if isPrefixOf "{{" (pack cs)
         then go (afterClose (drop 2 cs))
      else c :: go rest

-- Page values a template can show besides the front matter's. The caller
-- applies the precedence (front matter, then ddraig.toml, then default).
record PageVars where
  constructor MkPageVars
  pvRoot      : String   -- {{root}}: the base URL's path, e.g. /ddraig-ssg
  pvCanonical : String   -- {{canonical}}
  pvLang      : String   -- {{lang}}
  pvMenu      : String   -- {{menu}}: the menu's list items, rendered HTML
  pvAuthor    : String   -- {{author}}

-- The menu shown when ddraig.toml defines no [[menus.main]].
defaultMenu : List MenuItem
defaultMenu = [MkMenuItem "Home" "/"]

-- A menu's list items, through the typed Html core. A url starting with "/"
-- (but not "//") is inside the site, so the root goes in front of it.
renderMenu : (root : String) -> List MenuItem -> String
renderMenu root items = concat (intersperse "\n        " (map (render . item) items))
  where
    href : String -> String
    href u = if strHasPrefix "/" u && not (strHasPrefix "//" u) then root ++ u else u
    item : MenuItem -> Html
    item m = Elem "li" [] [Elem "a" [("href", href m.itemUrl), ("property", "schema:url")] [Text m.itemName]]

export
applyTemplate : String -> Frontmatter -> PageVars -> String -> String -> String
applyTemplate template fm pv htmlContent tocHtml =
  let brand = if fm.brand == "" then fm.title else fm.brand
      t1 = strReplace template "{{title}}" (strEscape fm.title)
      t2 = strReplace t1 "{{date}}" (strEscape fm.date)
      t3 = strReplace t2 "{{description}}" (strEscape fm.description)
      t4 = strReplace t3 "{{brand}}" (strEscape brand)
      tc = strReplace t4 "{{canonical}}" (strEscape pv.pvCanonical)
      tr = strReplace tc "{{root}}" (strEscape pv.pvRoot)
      tl = strReplace tr "{{lang}}" (strEscape pv.pvLang)
      ta = strReplace tl "{{author}}" (strEscape pv.pvAuthor)
      tm = strReplace ta "{{menu}}" pv.pvMenu
      t5 = strReplace tm "{{toc}}" tocHtml
      -- strip any remaining unfilled placeholders BEFORE injecting content,
      -- so author content (which may legitimately contain braces) is untouched
      t6 = stripPlaceholders t5
      -- content LAST so its own braces (if any) are untouched
      t7 = strReplace t6 "{{content}}" htmlContent
  in t7

-- ============================================================================
-- Filesystem helpers
-- ============================================================================

-- Is this path a directory?  listDir returns Right for dirs, Left for files.
isDir : HasIO io => String -> io Bool
isDir path = do
  r <- listDir path
  case r of
    Right _ => pure True
    Left _ => pure False

joinPath : String -> String -> String
joinPath a b =
  if a == "" then b
  else if strHasSuffix "/" a then a ++ b
  else a ++ "/" ++ b

-- mkdir -p
mkDirP : HasIO io => String -> io ()
mkDirP path = go (parts (unpack path)) ""
  where
    -- split on '/', preserving a leading "/" as an absolute marker
    parts : List Char -> List String
    parts cs = filter (/= "") (strSplitOn '/' (pack cs))
    go : List String -> String -> io ()
    go [] _ = pure ()
    go (p :: ps) acc =
      let cur = if acc == ""
                   then (if strHasPrefix "/" path then "/" ++ p else p)
                   else acc ++ "/" ++ p
      in do _ <- createDir cur   -- ignore "already exists"
            go ps cur

-- directory portion of a file path
dirOf : String -> String
dirOf path =
  let segs = strSplitOn '/' path
  in case reverse segs of
       (_ :: rest@(_ :: _)) => fromMaybe "" (head' [pack' (reverse rest)])
       _ => ""
  where
    pack' : List String -> String
    pack' xs = case xs of
                 [] => ""
                 _  => foldr (\a, b => if b == "" then a else a ++ "/" ++ b) "" xs

-- Recursively gather all files under `root`, returning paths relative to
-- `root`. Each directory's entries are sorted first: listDir returns them in
-- the filesystem's own order (hash order on ext4, and different again on
-- another machine), and the sitemap, feed and attestation list pages in walk
-- order, so sorting is what makes the output the same everywhere.
walkFiles : HasIO io => (root : String) -> (rel : String) -> io (List String)
walkFiles root rel = do
  let dir = joinPath root rel
  r <- listDir dir
  case r of
    Left _ => pure []
    Right entries => concatMap' (sort entries)
  where
    concatMap' : List String -> io (List String)
    concatMap' [] = pure []
    concatMap' (e :: es) = do
      let childRel = if rel == "" then e else rel ++ "/" ++ e
      let childAbs = joinPath root childRel
      d <- isDir childAbs
      here <- if d then walkFiles root childRel else pure [childRel]
      rest <- concatMap' es
      pure (here ++ rest)

-- Recursive copy of a directory tree (text contents).
copyTree : HasIO io => (src : String) -> (dst : String) -> io ()
copyTree src dst = do
  d <- isDir src
  if not d
     then pure ()  -- nothing to copy
     else do
       _ <- mkDirP dst
       rels <- walkFiles src ""
       copyEach rels
  where
    copyEach : List String -> io ()
    copyEach [] = pure ()
    copyEach (rel :: rs) = do
      let s = joinPath src rel
      let dpath = joinPath dst rel
      _ <- mkDirP (dirOf dpath)
      content <- readFile s
      case content of
        Right txt => ignore (writeFile dpath txt)
        Left _ => pure ()
      copyEach rs

-- ============================================================================
-- Build pipeline
-- ============================================================================

-- Resolve {{> partial}} includes from <src>/templates/partials/<name>.html
resolvePartials : HasIO io => (src : String) -> String -> io String
resolvePartials src tpl = go tpl 64
  where
    go : String -> Nat -> io String
    go t Z = pure t      -- depth guard
    go t (S depth) =
      case findInclude (unpack t) [] of
        Nothing => pure t
        Just (before, name, after) => do
          let pf = joinPath src ("templates/partials/" ++ name ++ ".html")
          r <- readFile pf
          let body = case r of Right c => c; Left _ => ""
          go (before ++ body ++ after) depth
      where
        -- find first "{{> name}}"; returns (before, name, after)
        findInclude : List Char -> List Char -> Maybe (String, String, String)
        findInclude [] _ = Nothing
        findInclude cs@(c :: more) acc =
          if isPrefixOf "{{>" (pack cs)
             then let afterMark = drop 3 cs
                  in case break (== '}') afterMark of
                       (nameChars, ('}' :: '}' :: rest)) =>
                         Just (pack (reverse acc), trim (pack nameChars), pack rest)
                       _ => findInclude more (c :: acc)
             else findInclude more (c :: acc)

-- Load template by layout name; fall back to built-in. Partials are inlined,
-- then {{site...}} and {{data...}} variables are filled in (they were checked
-- before the build started, by checkTemplates).
loadTemplate : HasIO io => (src : String) -> (vars : List (String, TValue)) -> (layout : String) -> io String
loadTemplate src vars layout = do
  let name = if layout == "" then "default" else layout
  let name2 = if strHasSuffix ".html" name then name else name ++ ".html"
  let path = joinPath src ("templates/" ++ name2)
  r <- readFile path
  case r of
    Right c => do full <- resolvePartials src c
                  pure (fst (resolveVars strEscape vars path full))
    Left _ => pure defTemplate

-- change ".md"/".markdown" extension to ".html"
toHtmlPath : String -> String
toHtmlPath rel =
  if strHasSuffix ".markdown" rel
     then substr 0 (length rel `minus` 9) rel ++ ".html"
  else if strHasSuffix ".md" rel
     then substr 0 (length rel `minus` 3) rel ++ ".html"
  else rel ++ ".html"

isMarkdown : String -> Bool
isMarkdown p = strHasSuffix ".md" p || strHasSuffix ".markdown" p

-- Join a base URL and a site-absolute path into an absolute URL. With an empty
-- base the path is returned unchanged (best effort; a base URL is required for
-- a fully conformant sitemap, recommended for the feed, and used for the
-- per-page canonical/Open Graph URL).
absUrl : (base : String) -> (path : String) -> String
absUrl base path =
  if base == "" then path
  else (if strHasSuffix "/" base then substr 0 (length base `minus` 1) base else base) ++ path

-- The site's path prefix: the path part of the base URL without a trailing
-- slash. "https://example.org/docs/" gives "/docs"; a site at the domain root,
-- or no base URL, gives "". Templates use it as {{root}} for root-relative
-- links, so a project site served under a sub-path (GitHub Pages serves
-- /<repo>/) still finds its stylesheet and home page.
basePath : (base : String) -> String
basePath base = pack (reverse (dropSlashes (reverse (pathOf (afterScheme (unpack base))))))
  where
    afterScheme : List Char -> List Char
    afterScheme (':' :: '/' :: '/' :: rest) = rest
    afterScheme (_ :: rest) = afterScheme rest
    afterScheme [] = []
    -- drop the host, keeping everything from the first '/'
    pathOf : List Char -> List Char
    pathOf [] = []
    pathOf cs@('/' :: _) = cs
    pathOf (_ :: rest) = pathOf rest
    dropSlashes : List Char -> List Char
    dropSlashes ('/' :: rest) = dropSlashes rest
    dropSlashes cs = cs

-- Everything a page build needs to know about the site.
record BuildCtx where
  constructor MkBuildCtx
  ctxSrc  : String
  ctxOut  : String
  ctxBase : String                  -- the base URL in effect
  ctxCfg  : SiteConfig              -- ddraig.toml (noConfig without one)
  ctxVars : List (String, TValue)   -- {{site...}} and {{data...}} values

-- The first non-empty of a front matter value and a site value, else a default.
pick : String -> Maybe String -> String -> String
pick page site dflt =
  if page /= "" then page else case site of
    Just s  => if s /= "" then s else dflt
    Nothing => dflt

-- One built page: its O3 certification status (certified?, violations), how
-- many raw HTML blocks it has (not inspected by the certifier, so the
-- attestation lists them), and located DDR0801 errors for images without alt.
record PageResult where
  constructor MkPageResult
  page       : Page
  certified  : Bool
  violations : List String
  rawBlocks  : Nat
  imageDiags : List Diagnostic

-- DDR0801 for each image without alt text, in document order. The parser has
-- already decided which images lack alt (so an image inside code is never
-- reported); this only finds where to point, by searching the page source
-- for each image's `](src)` in turn. One that cannot be found is reported
-- against the file without a position.
missingAltDiags : (file : String) -> (content : String) -> List String -> List Diagnostic
missingAltDiags file content srcs =
  case lines content of
    []        => map (\s => inFile file (diag s)) srcs
    (l :: ls) => go 1 0 (unpack l) ls srcs
  where
    diag : String -> Diagnostic
    diag src = withHelp "describe the image inside the brackets, or add {.decorative} straight after it if it is purely decorative" $
               diagError ImageMissingAlt ("image \"" ++ src ++ "\" has no alt text")
    findFrom : List Char -> List Char -> Nat -> Maybe Nat
    findFrom needle hay i =
      if isPrefixOf needle hay then Just i
      else case hay of
             []          => Nothing
             (_ :: rest) => findFrom needle rest (S i)
    -- index of the last "![" in a line prefix (0 if none)
    lastBang : List Char -> Nat
    lastBang cs = goB 0 cs 0
      where
        goB : Nat -> List Char -> Nat -> Nat
        goB _ [] best = best
        goB i ('!' :: '[' :: rest) _ = goB (S i) ('[' :: rest) i
        goB i (_ :: rest) best = goB (S i) rest best
    -- n: line number (1-based); off: column offset of `cs` within the line
    go : Nat -> Nat -> List Char -> List String -> List String -> List Diagnostic
    go _ _ _ _ [] = []
    go n off cs ls (s :: ss) =
      let needle = unpack ("](" ++ s ++ ")") in
      case findFrom needle cs 0 of
        Just i =>
          let bang = lastBang (take i cs)
              endI = i + length needle in
          atPos file n (S (off + bang)) (endI `minus` bang) "no alt text" (diag s)
            :: go n (off + endI) (drop endI cs) ls ss
        Nothing => case ls of
          []          => map (\x => inFile file (diag x)) (s :: ss)
          (l :: rest) => go (S n) 0 (unpack l) rest (s :: ss)

-- Build one markdown file. Nothing only when the file is a draft or unreadable.
buildOne : HasIO io => BuildCtx -> (rel : String) -> io (Maybe PageResult)
buildOne ctx rel = do
  let src = ctx.ctxSrc
  let out = ctx.ctxOut
  let base = ctx.ctxBase
  let cfg = ctx.ctxCfg
  let inPath = joinPath src rel
  r <- readFile inPath
  case r of
    Left e => do putStrLn ("  ! read error: " ++ inPath); pure Nothing
    Right content => do
      let (fm, body) = parseFrontmatter content
      if fm.draft
         then do putStrLn ("  - skip (draft): " ++ rel); pure Nothing
         else do
           let md = parseMarkdownFull body
           let toc = buildToc md.toc
           tpl <- loadTemplate src ctx.ctxVars fm.template
           let title = if fm.title == "" then rel else fm.title
           let fm2 = { title := title } fm
           let relHtml = toHtmlPath rel
           let canonical = absUrl base ("/" ++ relHtml)
           let root = basePath base
           -- precedence: front matter, then ddraig.toml, then the default
           let shown = { brand := pick fm.brand cfg.siteTitle ""
                       , description := pick fm.description cfg.siteDescription "" } fm2
           let menuItems = fromMaybe defaultMenu (lookup "main" cfg.siteMenus)
           let pv = MkPageVars root canonical (pick fm.lang cfg.siteLanguage "en")
                               (renderMenu root menuItems) (pick fm.author cfg.siteAuthor "")
           let html = applyTemplate tpl shown pv md.body toc
           let outPath = joinPath out relHtml
           _ <- mkDirP (dirOf outPath)
           w <- writeFile outPath html
           case w of
             Left e => do putStrLn ("  ! write error: " ++ outPath); pure Nothing
             Right () => do
               -- O3: the total accessibility decision over the typed content tree.
               let (certified, viols) = case certify md.blocks of
                                          Right _  => (True, the (List String) [])
                                          Left  vs => (False, vs)
               putStrLn ("  + " ++ rel ++ " -> " ++ relHtml
                          ++ (if certified then "  [a11y ok]" else "  [a11y FAIL]"))
               traverse_ (\v => putStrLn ("    a11y: " ++ v)) viols
               pure (Just (MkPageResult (MkPage ("/" ++ relHtml) fm2) certified viols
                             (countRawF md.blocks)
                             (missingAltDiags inPath content (unlabelledF md.blocks))))

-- Copy known asset dirs (assets/static/css/js/images) preserving name.
copyAssets : HasIO io => (src : String) -> (out : String) -> io ()
copyAssets src out = go ["assets","static","css","js","images"]
  where
    go : List String -> io ()
    go [] = pure ()
    go (d :: ds) = do
      let s = joinPath src d
      present <- isDir s
      when present $ do
        putStrLn ("  asset dir: " ++ d ++ "/")
        copyTree s (joinPath out d)
      go ds

-- Does a file exist (readable)?
fileExists : HasIO io => String -> io Bool
fileExists path = do
  r <- readFile path
  case r of
    Right _ => pure True
    Left _ => pure False

-- Write the canonical AAA default stylesheet to <out>/assets/style.css,
-- UNLESS the source site already provides assets/style.css (then the site's
-- own file wins — copyAssets will have copied it).
writeDefaultStyle : HasIO io => (src : String) -> (out : String) -> io ()
writeDefaultStyle src out = do
  let srcStyle = joinPath src "assets/style.css"
  has <- fileExists srcStyle
  if has
     then putStrLn "  assets/style.css: provided by site (default theme skipped)"
     else do
       let dst = joinPath out "assets/style.css"
       _ <- mkDirP (dirOf dst)
       w <- writeFile dst defStylesheet
       case w of
         Right () => putStrLn "  + assets/style.css (default AAA theme)"
         Left _ => putStrLn "  ! could not write assets/style.css"

-- Copy <src>/public/* into the OUTPUT ROOT.
copyPublic : HasIO io => (src : String) -> (out : String) -> io ()
copyPublic src out = do
  let p = joinPath src "public"
  present <- isDir p
  when present $ do
    putStrLn "  public/ -> output root"
    copyTree p out

-- ----------------------------------------------------------------------------
-- URL + date helpers for sitemap / Atom feed
-- (absUrl is defined earlier, before buildOne, as the canonical-URL builder
-- also uses it.)
-- ----------------------------------------------------------------------------

-- A stable Atom id for a resource: an absolute URL when a base is set, else a
-- urn: fallback so the feed is still valid Atom (RFC 4287 only requires an IRI).
atomId : (base : String) -> (path : String) -> String
atomId base path = if base == "" then "urn:ddraig:" ++ path else absUrl base path

-- Normalise a front-matter date to an RFC 3339 timestamp for Atom <updated>:
-- "YYYY-MM-DD" -> "YYYY-MM-DDT00:00:00Z"; values already carrying a time pass
-- through; empty stays empty (the caller supplies a fallback).
rfc3339 : String -> String
rfc3339 d =
  if d == "" then ""
  else if 'T' `elem` unpack d then d
  else d ++ "T00:00:00Z"

-- Civil (year, month, day) from days since the Unix epoch, valid for days >= 0
-- (every "now" qualifies). Hinnant's algorithm; non-negative integer arithmetic
-- throughout, so div rounding is immaterial.
civilFromDays : Integer -> (Integer, Integer, Integer)
civilFromDays days =
  let z   = days + 719468
      era = z `div` 146097
      doe = z - era * 146097
      yoe = (doe - (doe `div` 1460) + (doe `div` 36524) - (doe `div` 146096)) `div` 365
      y   = yoe + era * 400
      doy = doe - (365 * yoe + (yoe `div` 4) - (yoe `div` 100))
      mp  = (5 * doy + 2) `div` 153
      d   = doy - ((153 * mp + 2) `div` 5) + 1
      m   = if mp < 10 then mp + 3 else mp - 9
  in (if m <= 2 then y + 1 else y, m, d)

-- The build's "now" in seconds since the Unix epoch. SOURCE_DATE_EPOCH
-- (https://reproducible-builds.org/specs/source-date-epoch/), when set and
-- non-empty, replaces the clock, so a build and its golden tests do not depend
-- on the day they run. A value that is not a non-negative integer is reported
-- (DDR0001) rather than silently ignored.
buildEpochSeconds : HasIO io => io (Either Diagnostic Integer)
buildEpochSeconds = do
  env <- getEnv "SOURCE_DATE_EPOCH"
  case env of
    Just s =>
      if s == "" then map Right clock
      else case (all isDigit (unpack s), parsePositive s) of
             (True, Just n) => pure (Right n)
             _ => pure (Left (badEpoch s))
    Nothing => map Right clock
  where
    clock : io Integer
    clock = do c <- liftIO (clockTime UTC); pure (seconds c)
    badEpoch : String -> Diagnostic
    badEpoch s =
      withHelp "unset it, or set it to the empty string, to use today's date" $
      withHelp "use whole seconds since 1970-01-01 UTC, digits only: SOURCE_DATE_EPOCH=1782086400" $
      diagError BadSourceDateEpoch
        ("SOURCE_DATE_EPOCH must be a whole number of seconds, but it is \"" ++ s ++ "\"")

-- The build date as "YYYY-MM-DD": the attestation's "generated" date and the
-- feed <updated> fallback when no page carries a date. Read once per build,
-- so the two always agree.
currentUtcDate : HasIO io => io (Either Diagnostic String)
currentUtcDate = map (map toDate) buildEpochSeconds
  where
    pad2 : Integer -> String
    pad2 n = if n < 10 then "0" ++ show n else show n
    toDate : Integer -> String
    toDate secs = let (y, m, d) = civilFromDays (secs `div` 86400)
                  in show y ++ "-" ++ pad2 m ++ "-" ++ pad2 d

-- sitemap.xml (locs are absolute when a base URL is supplied)
genSitemap : HasIO io => (base : String) -> (out : String) -> List Page -> io ()
genSitemap base out pages = do
  let urls = concatMap entry pages
  let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            ++ "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
            ++ urls
            ++ "</urlset>\n"
  ignore (writeFile (joinPath out "sitemap.xml") xml)
  putStrLn "  + sitemap.xml"
  where
    entry : Page -> String
    entry pg = "  <url><loc>" ++ strEscape (absUrl base pg.url) ++ "</loc>"
               ++ (if pg.fm.date == "" then "" else "<lastmod>" ++ strEscape pg.fm.date ++ "</lastmod>")
               ++ "</url>\n"

-- feed.xml (Atom). Emits every RFC 4287-required element: feed
-- id/title/updated/author and per-entry id/title/updated. Ids and links are
-- absolute when a base URL is supplied, urn: ids otherwise.
genFeed : HasIO io => (base : String) -> (out : String) -> (now : String)
       -> (siteTitle : Maybe String) -> List Page -> io ()
genFeed base out now siteTitle pages = do
  let dated = filter (/= "") (map (\pg => pg.fm.date) pages)
  let feedUpdated = rfc3339 (case dated of
                               [] => now
                               _  => foldl (\a, b => if a >= b then a else b) "" dated)
  -- [site] title from ddraig.toml if set, else the first page's site/brand
  let siteName = case filter (/= "") (maybe [] pure siteTitle ++ map (\pg => pg.fm.brand) pages) of
                   (b :: _) => b
                   []       => "Ddraig Site"
  let entries = concatMap (entry feedUpdated) pages
  let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            ++ "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            ++ "  <title>" ++ strEscape siteName ++ "</title>\n"
            ++ "  <id>" ++ strEscape (atomId base "/feed.xml") ++ "</id>\n"
            ++ "  <updated>" ++ feedUpdated ++ "</updated>\n"
            ++ "  <author><name>" ++ strEscape siteName ++ "</name></author>\n"
            ++ (if base == "" then ""
                else "  <link rel=\"self\" href=\"" ++ strEscape (absUrl base "/feed.xml") ++ "\"/>\n")
            ++ "  <generator>Ddraig SSG " ++ ddraigVersion ++ "</generator>\n"
            ++ entries
            ++ "</feed>\n"
  ignore (writeFile (joinPath out "feed.xml") xml)
  putStrLn "  + feed.xml"
  where
    entry : (feedUpdated : String) -> Page -> String
    entry feedUpdated pg =
      let upd = let r = rfc3339 pg.fm.date in if r == "" then feedUpdated else r
      in "  <entry>\n"
         ++ "    <title>" ++ strEscape pg.fm.title ++ "</title>\n"
         ++ "    <id>" ++ strEscape (atomId base pg.url) ++ "</id>\n"
         ++ "    <link href=\"" ++ strEscape (absUrl base pg.url) ++ "\"/>\n"
         ++ "    <updated>" ++ upd ++ "</updated>\n"
         ++ "    <summary>" ++ strEscape pg.fm.description ++ "</summary>\n"
         ++ "  </entry>\n"

-- Full build command.
-- Escape a string for embedding inside a JSON string literal.
jsonEsc : String -> String
jsonEsc s = concat (map e (unpack s))
  where
    e : Char -> String
    e '"'  = "\\\""
    e '\\' = "\\\\"
    e '\n' = "\\n"
    e c    = singleton c

-- Emit the O3 attestation certificate: one record per page stating whether it
-- satisfies the decidable accessibility predicates, and any violations. A page
-- marked `certified: true` is so because `certify` produced the proof. Raw
-- HTML blocks are not inspected, so each page also states how many it has.
writeAttestation : HasIO io => (base : String) -> (out : String) -> (now : String)
                -> List PageResult -> io ()
writeAttestation base out now results = do
  let entries = concat (intersperse ",\n" (map entryJson results))
  let json = "{\n"
          ++ "  \"generator\": \"Ddraig SSG " ++ ddraigVersion ++ "\",\n"
          ++ "  \"generated\": \"" ++ now ++ "T00:00:00Z\",\n"
          ++ "  \"scope\": \"decidable WCAG subset (typed content tree; raw HTML blocks are not inspected)\",\n"
          ++ "  \"predicates\": [" ++ concat (intersperse ", " (map (\p => "\"" ++ p ++ "\"") certifiedPredicates)) ++ "],\n"
          ++ "  \"pages\": [\n" ++ entries ++ "\n  ]\n"
          ++ "}\n"
  let dst = joinPath out ".well-known/accessibility-attestation.json"
  _ <- mkDirP (dirOf dst)
  ignore (writeFile dst json)
  putStrLn "  + .well-known/accessibility-attestation.json"
  where
    entryJson : PageResult -> String
    entryJson r =
      "    {\"page\": \"" ++ jsonEsc (absUrl base r.page.url)
        ++ "\", \"certified\": " ++ (if r.certified then "true" else "false")
        ++ ", \"unchecked_raw_html_blocks\": " ++ show r.rawBlocks
        ++ ", \"violations\": ["
        ++ concat (intersperse ", " (map (\v => "\"" ++ jsonEsc v ++ "\"") r.violations))
        ++ "]}"

-- ----------------------------------------------------------------------------
-- Reporting problems (format and codes: Diagnostic.idr, DIAGNOSTICS.adoc)
-- ----------------------------------------------------------------------------

-- Print diagnostics on stderr, quoting the source line of any that point into
-- a readable file.
report : HasIO io => List Diagnostic -> io ()
report ds = do
  srcs <- traverse load (nub (mapMaybe diagFile ds))
  -- progress written so far comes first, even when stdout is a buffered pipe
  fflush stdout
  ignore (fPutStr stderr (renderAll (\f => join (lookup f srcs)) ds))
  where
    load : String -> io (String, Maybe String)
    load f = do r <- readFile f; pure (f, either (const Nothing) Just r)

-- Report problems, then a one-line verdict, and exit with status 1.
failWith : HasIO io => (verdict : String) -> List Diagnostic -> io a
failWith verdict ds = do
  report ds
  ignore (fPutStrLn stderr ("\nddraig: " ++ verdict ++ ": " ++ summary ds))
  exitWith (ExitFailure 1)

-- Report problems that stop a build, and exit with status 1.
failBuild : HasIO io => List Diagnostic -> io a
failBuild = failWith "build stopped"

-- Report a mistake on the command line, and exit with status 2.
failUsage : HasIO io => List Diagnostic -> io a
failUsage ds = do report ds; exitWith (ExitFailure 2)

-- The source directory must exist and be a directory (DDR0002).
checkSourceDir : HasIO io => String -> io (List Diagnostic)
checkSourceDir src = do
  dir <- isDir src
  if dir then pure [] else do
    file <- fileExists src
    pure [ if file
             then withHelp "give the directory that contains your pages instead" $
                  diagError SourceDirMissing
                    ("\"" ++ src ++ "\" is a file; `ddraig build` needs the directory of source pages")
             else withHelp "check the spelling; a relative path starts from the directory ddraig runs in" $
                  diagError SourceDirMissing ("source directory \"" ++ src ++ "\" does not exist") ]

-- Parse and check the text of a site configuration (DDR01xx).
checkConfigText : (path : String) -> (text : String) -> Either (List Diagnostic) SiteConfig
checkConfigText path text =
  let (tables, syntaxProblems) = parseToml path text in
  case validateConfig path tables of
    Left ds   => Left (syntaxProblems ++ ds)
    Right cfg => if null syntaxProblems then Right cfg else Left syntaxProblems

-- <src>/ddraig.toml, checked; the defaults when there is none.
loadSiteConfig : HasIO io => (src : String) -> io (Maybe String, Either (List Diagnostic) SiteConfig)
loadSiteConfig src = do
  let path = joinPath src "ddraig.toml"
  r <- readFile path
  case r of
    Left _     => pure (Nothing, Right noConfig)
    Right text => pure (Just path, checkConfigText path text)

-- <src>/data/*.toml, read for templates; any TOML problems in them.
loadDataFiles : HasIO io => (src : String) -> io (List DataFile, List Diagnostic)
loadDataFiles src = do
  r <- listDir (joinPath src "data")
  case r of
    Left _      => pure ([], [])
    Right names => go (sort (filter (strHasSuffix ".toml") names)) [] []
  where
    go : List String -> List DataFile -> List Diagnostic -> io (List DataFile, List Diagnostic)
    go [] fs ds = pure (reverse fs, ds)
    go (n :: ns) fs ds = do
      let path = joinPath src ("data/" ++ n)
      r <- readFile path
      case r of
        Left _ => go ns fs (ds ++ [ inFile path (diagError ConfigUnreadable ("cannot read \"" ++ path ++ "\"")) ])
        Right text =>
          let (ts, errs) = parseToml path text in
          go ns (MkDataFile (substr 0 (length n `minus` 5) n) ts :: fs) (ds ++ errs)

-- Every template and partial, checked for {{site...}} and {{data...}}
-- variables that do not exist (DDR0201) or hold a list (DDR0202).
checkTemplates : HasIO io => (src : String) -> List (String, TValue) -> io (List Diagnostic)
checkTemplates src vars = do
  let dir = joinPath src "templates"
  rels <- walkFiles dir ""
  found <- traverse (\rel => do
             let path = joinPath dir rel
             r <- readFile path
             pure (case r of
                     Right text => snd (resolveVars strEscape vars path text)
                     Left _     => []))
           (filter (strHasSuffix ".html") rels)
  pure (concat found)

-- `ddraig validate-config <file>`: the same checks `ddraig build` makes.
validateConfigFile : HasIO io => String -> io ()
validateConfigFile path = do
  r <- readFile path
  case r of
    Left _ => failWith ("cannot check " ++ path)
                [ withHelp "check the path; `ddraig build` reads ddraig.toml from the source directory" $
                  diagError ConfigUnreadable ("cannot read \"" ++ path ++ "\"") ]
    Right text => case checkConfigText path text of
      Right _ => putStrLn ("OK: " ++ path ++ " is a valid site configuration")
      Left ds => failWith (path ++ " is not a valid site configuration") ds

-- Full build command. Everything that can be checked before writing output is
-- checked first, and all of it is reported together.
buildSite : HasIO io => (src : String) -> (out : String) -> (cliBase : String) -> io ()
buildSite src out cliBase = do
  putStrLn ("Ddraig build: " ++ src ++ " -> " ++ out)
  srcProblems <- checkSourceDir src
  today <- currentUtcDate
  let srcOk = null srcProblems
  -- (with no source directory these find nothing, and report nothing)
  (cfgPath, cfgResult) <- loadSiteConfig src
  (datas, dataProblems) <- loadDataFiles src
  let cfg = either (const noConfig) id cfgResult
  -- base URL: the command line's, else ddraig.toml's
  let base = if cliBase /= "" then cliBase else fromMaybe "" cfg.siteBaseUrl
  let vars = templateVars cfg base datas
  -- templates are checked only against a valid configuration and readable
  -- data files, so one mistake is not reported again as many
  tplProblems <- if srcOk && either (const False) (const True) cfgResult && null dataProblems
                   then checkTemplates src vars else pure []
  let problems = srcProblems ++ either id (const []) cfgResult ++ dataProblems
                 ++ tplProblems ++ either (\d => [d]) (const []) today
  case today of
    Left _ => failBuild problems
    Right now =>
     if not (null problems)
     then failBuild problems
     else do
       traverse_ (\p => putStrLn ("  config: " ++ p)) cfgPath
       when (base /= "") $
         putStrLn ("  base URL: " ++ base
                   ++ (if cliBase /= "" then " (from the command line)" else " (from ddraig.toml)"))
       let ctx = MkBuildCtx src out base cfg vars
       _ <- mkDirP out
       all <- walkFiles src ""
       -- skip files under templates/, public/, and the asset dirs (handled separately)
       let mdFiles = filter (\p => isMarkdown p && not (underSpecial p)) all
       putStrLn ("Found " ++ show (length mdFiles) ++ " markdown file(s).")
       results <- buildEach ctx mdFiles
       let pages = map (.page) results
       copyAssets src out
       writeDefaultStyle src out
       copyPublic src out
       genSitemap base out pages
       genFeed base out now cfg.siteTitle pages
       writeAttestation base out now results
       putStrLn ("Done. " ++ show (length pages) ++ " page(s) built.")
       -- images without alt: located errors (each page is also uncertified)
       let imgDiags = concatMap (.imageDiags) results
       when (not (null imgDiags)) $ report imgDiags
       let failed = filter (\r => not r.certified) results
       when (not (null failed)) $ do
         putStrLn ("ACCESSIBILITY: " ++ show (length failed) ++ " page(s) failed certification:")
         traverse_ (\r => do
                      putStrLn ("  " ++ r.page.url)
                      traverse_ (\v => putStrLn ("    - " ++ v)) r.violations) failed
         exitFailure
  where
    underSpecial : String -> Bool
    underSpecial p =
      any (\d => strHasPrefix (d ++ "/") p)
          ["templates","public","assets","static","css","js","images","data"]
    buildEach : BuildCtx -> List String -> io (List PageResult)
    buildEach _ [] = pure []
    buildEach ctx (f :: fs) = do
      mp <- buildOne ctx f
      rest <- buildEach ctx fs
      pure (maybe rest (:: rest) mp)

-- clean command: remove output dir contents (best-effort, recursive).
cleanOut : HasIO io => String -> io ()
cleanOut out = do
  present <- isDir out
  if not present
     then putStrLn ("Nothing to clean: " ++ out)
     else do
       rels <- walkFiles out ""
       traverse_ (\rel => ignore (removeFile (joinPath out rel))) rels
       putStrLn ("Cleaned files under: " ++ out)

-- ============================================================================
-- Tests (retained)
-- ============================================================================

testMarkdown : IO ()
testMarkdown = do
  putStrLn "=== Test: Markdown ==="
  let md = "# Hello World\n\nThis is a **bold** test with *italic* and ~~strike~~ text.\n\n- Item 1\n- Item 2\n\n> a quote\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n[link](https://x) and ![img](y.png)\n\n```idris\nfoo : Int\n```\n"
  putStrLn (parseMarkdown md)

testFrontmatter : IO ()
testFrontmatter = do
  putStrLn "=== Test: Frontmatter ==="
  let content = "<!-- SPDX-License-Identifier: MPL-2.0 -->\n---\ntitle: My Post\ndate: 2024-01-15\ntags: [idris, ssg]\ndraft: false\ndescription: hi\nsite: Ddraig\n---\n\nContent here\n"
  let (fm, body) = parseFrontmatter content
  putStrLn ("Title: " ++ fm.title)
  putStrLn ("Date: " ++ fm.date)
  putStrLn ("Tags: " ++ show fm.tags)
  putStrLn ("Draft: " ++ show fm.draft)
  putStrLn ("Desc: " ++ fm.description)
  putStrLn ("Brand: " ++ fm.brand)
  putStrLn ("Body: " ++ body)

testFull : IO ()
testFull = do
  putStrLn "=== Test: Full Pipeline ==="
  let content = "---\ntitle: Welcome\ndate: 2024-01-15\n---\n\n# Welcome\n\nThis is **Ddraig**, an Idris 2-powered SSG.\n\n- Dependently typed\n- Provably correct\n"
  let (fm, body) = parseFrontmatter content
  let md = parseMarkdownFull body
  let output = applyTemplate defTemplate fm
                 (MkPageVars "" "/welcome.html" "en" (renderMenu "" defaultMenu) "")
                 md.body (buildToc md.toc)
  putStrLn output
  -- {{root}}: a sub-path site's links must carry its prefix.
  let cases = [ ("", ""), ("https://example.com", ""), ("https://example.com/", "")
              , ("https://hyperpolymath.github.io/ddraig-ssg", "/ddraig-ssg")
              , ("https://example.org/a/b/", "/a/b") ]
  let wrong = filter (\(b, want) => basePath b /= want) cases
  let rooted = applyTemplate defTemplate fm
                 (MkPageVars "/sub" "/sub/welcome.html" "en" (renderMenu "/sub" defaultMenu) "")
                 md.body ""
  let styled = strReplace rooted "href=\"/sub/assets/style.css\"" "" /= rooted
  if null wrong && styled
     then putStrLn "OK: basePath and {{root}}"
     else do putStrLn ("FAIL: basePath/{{root}} " ++ show wrong ++ " stylesheet-prefixed=" ++ show styled)
             exitFailure

-- ============================================================================
-- a2ml STATE descriptile validation (O1)
-- ============================================================================

-- Validate a STATE descriptile file: parse (untrusted) then run the total
-- `validateState` decision. Exits non-zero on any violation.
validateStateFile : HasIO io => String -> io ()
validateStateFile path = do
  r <- readFile path
  case r of
    Left _ => do putStrLn ("ERROR: cannot read " ++ path); exitFailure
    Right content => do
      let errs = validateState (parseState content)
      if null errs
         then putStrLn ("OK: " ++ path ++ " is a valid STATE descriptile")
         else do
           putStrLn ("INVALID: " ++ path ++ " (" ++ show (length errs) ++ " violation(s))")
           traverse_ (\e => putStrLn ("  - " ++ e)) errs
           exitFailure

-- Negative assertion: a deliberately broken descriptile MUST be rejected.
testState : IO ()
testState = do
  putStrLn "=== Test: STATE validator ==="
  let bad = "[metadata]\nproject = \"x\"\n\n[position]\nphase = \"bogus\"\nmaturity = \"experimental\"\n"
  let errs = validateState (parseState bad)
  putStrLn ("violations: " ++ show (length errs))
  traverse_ (\e => putStrLn ("  - " ++ e)) errs
  if null errs
     then do putStrLn "FAIL: invalid descriptile not rejected"; exitFailure
     else putStrLn "OK: invalid descriptile rejected"

-- O3 assertion: an accessible document certifies; an inaccessible one (two
-- <h1>, a skipped heading level) is rejected by the total `certify` decision.
testAttest : IO ()
testAttest = do
  putStrLn "=== Test: a11y attestation (O3) ==="
  let good = parseMarkdownFull "# One\n\nsome text\n\n## Two\n"
  let bad  = parseMarkdownFull "# One\n\n# Two\n\n### Skip\n"
  case certify good.blocks of
    Right _  => putStrLn "OK: accessible document certified"
    Left  vs => do putStrLn "FAIL: accessible document not certified"
                   traverse_ (\v => putStrLn ("  - " ++ v)) vs
                   exitFailure
  case certify bad.blocks of
    Left vs => do putStrLn ("OK: inaccessible document rejected (" ++ show (length vs) ++ " violation(s))")
                  traverse_ (\v => putStrLn ("  - " ++ v)) vs
    Right _ => do putStrLn "FAIL: inaccessible document certified"; exitFailure
  -- alt text: whitespace-only is rejected at the trust boundary
  case mkAlt "   " of
    Nothing => putStrLn "OK: whitespace-only alt text rejected"
    Just _  => do putStrLn "FAIL: whitespace-only alt text accepted"; exitFailure
  -- images: described and {.decorative} certify; no alt without the marker does not
  let labelled = parseMarkdownFull "# One\n\n![A red dragon](d.png) and ![](rule.png){.decorative}\n"
  let unlabelled = parseMarkdownFull "# One\n\n![](d.png)\n"
  case certify labelled.blocks of
    Right _  => putStrLn "OK: described and decorative images certified"
    Left  vs => do putStrLn "FAIL: described/decorative images not certified"
                   traverse_ (\v => putStrLn ("  - " ++ v)) vs
                   exitFailure
  case certify unlabelled.blocks of
    Left vs => do putStrLn "OK: image without alt rejected"
                  traverse_ (\v => putStrLn ("  - " ++ v)) vs
    Right _ => do putStrLn "FAIL: image without alt certified"; exitFailure

-- Rendering samples and invariants for the diagnostics core. The rendered
-- text is pinned by tests/golden/cli/test-diagnostics.out; the invariants
-- (unique, round-tripping codes; the expected suggestions) fail the test.
testDiagnostics : IO ()
testDiagnostics = do
  putStrLn "=== Test: diagnostics ==="
  let ids = map codeId allCodes
  let unique = length (nub ids) == length ids
  let roundTrip = all (\c => map codeId (fromId (codeId c)) == Just (codeId c)) allCodes
  putStrLn ("codes: " ++ show (length ids) ++ ", unique: " ++ show unique
            ++ ", round-trip: " ++ show roundTrip)
  let cases = the (List (String, List String, Maybe String))
                [ ("titel",  ["title", "date", "tags"], Just "title")    -- transposed letters
                , ("Title",  ["title", "date"],         Just "title")    -- case only
                , ("biuld",  ["build", "clean", "explain"], Just "build")
                , ("DDR002", ids,                       Just "DDR0002")  -- a missing digit
                , ("xyz",    ["title", "date"],         Nothing)         -- nothing close
                , ("title",  ["title"],                 Nothing) ]       -- identical: no typo
  traverse_ (\(w, _, e) => putStrLn ("closest " ++ show w ++ ": " ++ show e)) cases
  let wrong = filter (\(w, k, e) => closest w k /= e) cases
  putStrLn ""
  putStr (renderAll sourceOf samples)
  putStrLn ""
  putStrLn ("summary: " ++ summary samples)
  if unique && roundTrip && null wrong
     then putStrLn "OK: diagnostics"
     else do putStrLn ("FAIL: diagnostics; wrong suggestions for " ++ show (map fst wrong))
             exitFailure
  where
    toml : String
    toml = "[site]\ntitle = \"Example\"\ntitel = \"Typo\"\n"
    long : String
    long = concat (Data.List.replicate 10 "filler = 1\n") ++ "\tvalue = [1, 2\n"
    gappy : String
    gappy = "first\n\nthird\n"
    sourceOf : String -> Maybe String
    sourceOf "sample/site.toml"  = Just toml
    sourceOf "sample/long.toml"  = Just long
    sourceOf "sample/gappy.md"   = Just gappy
    sourceOf _                   = Nothing
    samples : List Diagnostic
    samples =
      [ withNote "this is a rendering sample, not a real message" $
        withHelp "did you mean \"title\"?" $
        atPos "sample/site.toml" 3 1 5 "not a known key" $
        diagError UnknownCommand "sample: located error with a label, help and a note"
      , withHelp "a two-digit line number widens the gutter; the tab shows as one space" $
        atPos "sample/long.toml" 11 10 5 "this list is never closed" $
        diagWarning WrongArguments "sample: warning on line 11"
      , atPos "sample/site.toml" 2 18 3 "one caret just past the end, e.g. for something missing" $
        diagError WrongArguments "sample: span past the end of the line"
      , atPos "sample/gappy.md" 2 1 1 "" $
        diagError WrongArguments "sample: an empty source line"
      , withHelp "the file could not be read, so no line is quoted" $
        atPos "sample/unreadable.md" 4 2 1 "unseen" $
        diagError SourceDirMissing "sample: located in a file that cannot be read"
      , inFile "sample/whole-file.md" $
        diagError SourceDirMissing "sample: a whole file"
      , withHelp "no file at all, as for a command-line mistake" $
        diagError UnknownCode "sample: no location"
      ]

-- ============================================================================
-- Main
-- ============================================================================

-- A command, as `ddraig --help` and the command-line errors describe it.
record Command where
  constructor MkCommand
  cmdName : String
  cmdArgs : String   -- e.g. "<src> <out> [base-url]"
  minArgs : Nat
  maxArgs : Nat

commands : List Command
commands =
  [ MkCommand "build"          "<src> <out> [base-url]" 2 3
  , MkCommand "clean"          "<out>"                  1 1
  , MkCommand "validate-state" "<file.a2ml>"            1 1
  , MkCommand "validate-config" "<ddraig.toml>"         1 1
  , MkCommand "explain"        "[code]"                 0 1
  , MkCommand "--help"         ""                       0 0
  , MkCommand "--version"      ""                       0 0 ]

-- Everything accepted as a first argument, for "did you mean ...?".
commandNames : List String
commandNames =
  map cmdName commands
    ++ ["help", "-h", "-v", "test-markdown", "test-frontmatter", "test-full",
        "test-state", "test-attest", "test-diagnostics"]

-- The command line matched no command: either an unknown command (DDR0003)
-- or a known one with the wrong number of arguments (DDR0004).
badInvocation : String -> List String -> Diagnostic
badInvocation cmd rest =
  case filter (\c => c.cmdName == cmd) commands of
    (c :: _) =>
      withHelp ("usage: " ++ synopsis c) $
      diagError WrongArguments
        ("`ddraig " ++ cmd ++ "` takes " ++ takes c.minArgs c.maxArgs
         ++ ", but was given " ++ show (length rest))
    [] =>
      withHelp "run `ddraig --help` to list the commands" $
      withHelps (didYouMean cmd commandNames) $
      diagError UnknownCommand ("unknown command \"" ++ cmd ++ "\"")
  where
    synopsis : Command -> String
    synopsis c = "ddraig " ++ c.cmdName ++ (if c.cmdArgs == "" then "" else " " ++ c.cmdArgs)
    takes : Nat -> Nat -> String
    takes 0 0 = "no arguments"
    takes 1 1 = "1 argument"
    takes lo hi = if lo == hi then show lo ++ " arguments"
                  else show lo ++ " or " ++ show hi ++ " arguments"

-- `ddraig explain <code>`: the code may be given in either case.
explainCode : String -> IO ()
explainCode c =
  case fromId (toUpper (trim c)) of
    Just code => putStr (renderExplanation code)
    Nothing =>
      failUsage [ withHelp "run `ddraig explain` with no code to list every code" $
                  withHelps (didYouMean (toUpper (trim c)) (map codeId allCodes)) $
                  diagError UnknownCode ("\"" ++ c ++ "\" is not a diagnostic code") ]

usage : IO ()
usage = do
  putStrLn "Ddraig SSG - Idris 2 powered (\"types that breathe fire\")"
  putStrLn ""
  putStrLn "Usage:"
  putStrLn "  ddraig build <src> <out> [base-url]  Build a site"
  putStrLn "        base-url (e.g. https://example.com) makes sitemap.xml and"
  putStrLn "        feed.xml URLs absolute (recommended; required for a valid sitemap)"
  putStrLn "        SOURCE_DATE_EPOCH (seconds since 1970-01-01 UTC), if set, fixes the"
  putStrLn "        build date, so the same sources always give the same output"
  putStrLn "  ddraig clean <out>         Remove built files under <out>"
  putStrLn "  ddraig validate-state <file.a2ml>  Validate an a2ml STATE descriptile"
  putStrLn "  ddraig validate-config <ddraig.toml>  Check a site configuration"
  putStrLn "        (ddraig build reads <src>/ddraig.toml if there is one)"
  putStrLn "  ddraig explain [code]      Explain a diagnostic code such as DDR0002;"
  putStrLn "                             with no code, list them all"
  putStrLn "  ddraig --version           Print version"
  putStrLn "  ddraig --help              This help"
  putStrLn ""
  putStrLn "Problems are reported on stderr as error[DDRnnnn] with the file, line and"
  putStrLn "column where known. Exit status: 0 success, 1 the build found problems,"
  putStrLn "2 the command line was wrong."
  putStrLn ""
  putStrLn "Test subcommands:"
  putStrLn "  ddraig test-markdown | test-frontmatter | test-full | test-state | test-attest"
  putStrLn "  ddraig test-diagnostics"

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "test-markdown"] => testMarkdown
    [_, "test-frontmatter"] => testFrontmatter
    [_, "test-full"] => testFull
    [_, "test-state"] => testState
    [_, "test-attest"] => testAttest
    [_, "test-diagnostics"] => testDiagnostics
    [_, "--version"] => putStrLn ("ddraig " ++ ddraigVersion)
    [_, "-v"] => putStrLn ("ddraig " ++ ddraigVersion)
    [_, "--help"] => usage
    [_, "-h"] => usage
    [_, "help"] => usage
    [_, "build", src, out] => buildSite src out ""
    [_, "build", src, out, base] => buildSite src out base
    [_, "clean", out] => cleanOut out
    [_, "validate-state", path] => validateStateFile path
    [_, "validate-config", path] => validateConfigFile path
    [_, "explain"] => putStr renderCodeList
    [_, "explain", code] => explainCode code
    (_ :: cmd :: rest) => failUsage [badInvocation cmd rest]
    _ => usage
