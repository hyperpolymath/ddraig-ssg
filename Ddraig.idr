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

export
emptyFrontmatter : Frontmatter
emptyFrontmatter = MkFrontmatter "" "" [] False "default" "" "" ""

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
-- informative images provably carry non-empty alt text, and empty/whitespace
-- alt becomes an explicit `DecorativeImg` (alt="") rather than a silent alt="".
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
    imageNode : (alt : String) -> (url : String) -> Html
    imageNode alt url =
      case mkAlt alt of
        Just a  => Img url a            -- informative: proof-carrying non-empty alt
        Nothing => DecorativeImg url    -- empty/whitespace alt: explicit alt=""
    -- flush the buffered plain-text run (reversed) as one Text node.
    flush : List Char -> List Html -> List Html
    flush []  rest = rest
    flush buf rest = Text (pack (reverse buf)) :: rest
    go : List Char -> List Char -> List Html
    go [] buf = flush buf []
    -- image: ![alt](url)
    go ('!' :: '[' :: rest) buf =
      case readLink rest of
        Just (alt, url, after) => flush buf (imageNode alt url :: go after [])
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
-- {{content}} — content substituted LAST so its body HTML is never reprocessed.
defTemplate : String
defTemplate = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{title}}</title>
  <meta name="description" content="{{description}}">
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
  <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
  <a class="skip-link" href="#main">Skip to content</a>

  <header class="site-header">
    <nav class="container nav" aria-label="Primary">
      <a class="brand" href="/">{{brand}}</a>
      <ul class="nav-links">
        <li><a href="/">Home</a></li>
      </ul>
    </nav>
  </header>

  <main id="main" class="container" tabindex="-1">
    <article class="prose">
      {{content}}
    </article>
  </main>

  <footer class="site-footer">
    <div class="container">
      <p class="muted">Built with ddraig-ssg · <time>{{date}}</time></p>
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

export
applyTemplate : String -> Frontmatter -> (canonical : String) -> String -> String -> String
applyTemplate template fm canonical htmlContent tocHtml =
  let brand = if fm.brand == "" then fm.title else fm.brand
      t1 = strReplace template "{{title}}" (strEscape fm.title)
      t2 = strReplace t1 "{{date}}" (strEscape fm.date)
      t3 = strReplace t2 "{{description}}" (strEscape fm.description)
      t4 = strReplace t3 "{{brand}}" (strEscape brand)
      tc = strReplace t4 "{{canonical}}" (strEscape canonical)
      t5 = strReplace tc "{{toc}}" tocHtml
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

-- Recursively gather all files under `root` matching predicate, returning
-- paths relative to `root`.
walkFiles : HasIO io => (root : String) -> (rel : String) -> io (List String)
walkFiles root rel = do
  let dir = joinPath root rel
  r <- listDir dir
  case r of
    Left _ => pure []
    Right entries => concatMap' entries
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

-- Load template by layout name; fall back to built-in.
loadTemplate : HasIO io => (src : String) -> (layout : String) -> io String
loadTemplate src layout = do
  let name = if layout == "" then "default" else layout
  let name2 = if strHasSuffix ".html" name then name else name ++ ".html"
  let path = joinPath src ("templates/" ++ name2)
  r <- readFile path
  case r of
    Right c => resolvePartials src c
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

-- Build one markdown file. Returns Maybe Page (Nothing if draft skipped).
-- Build one markdown file. Returns the Page plus its O3 certification status
-- (certified?, violations). Nothing only when the file is a draft or unreadable.
buildOne : HasIO io => (src : String) -> (out : String) -> (base : String) -> (rel : String) -> io (Maybe (Page, Bool, List String))
buildOne src out base rel = do
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
           tpl <- loadTemplate src fm.template
           let title = if fm.title == "" then rel else fm.title
           let fm2 = { title := title } fm
           let relHtml = toHtmlPath rel
           let canonical = absUrl base ("/" ++ relHtml)
           let html = applyTemplate tpl fm2 canonical md.body toc
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
               pure (Just (MkPage ("/" ++ relHtml) fm2, certified, viols))

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

-- Current UTC date as "YYYY-MM-DD" (the feed <updated> fallback when no page
-- carries a date).
currentUtcDate : HasIO io => io String
currentUtcDate = do
  c <- liftIO (clockTime UTC)
  let (y, m, d) = civilFromDays (seconds c `div` 86400)
  pure (show y ++ "-" ++ pad2 m ++ "-" ++ pad2 d)
  where
    pad2 : Integer -> String
    pad2 n = if n < 10 then "0" ++ show n else show n

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
genFeed : HasIO io => (base : String) -> (out : String) -> List Page -> io ()
genFeed base out pages = do
  now <- currentUtcDate
  let dated = filter (/= "") (map (\pg => pg.fm.date) pages)
  let feedUpdated = rfc3339 (case dated of
                               [] => now
                               _  => foldl (\a, b => if a >= b then a else b) "" dated)
  let siteName = case filter (/= "") (map (\pg => pg.fm.brand) pages) of
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
-- marked `certified: true` is so because `certify` produced the proof.
writeAttestation : HasIO io => (base : String) -> (out : String) -> (now : String)
                -> List (Page, Bool, List String) -> io ()
writeAttestation base out now results = do
  let entries = concat (intersperse ",\n" (map entryJson results))
  let json = "{\n"
          ++ "  \"generator\": \"Ddraig SSG " ++ ddraigVersion ++ "\",\n"
          ++ "  \"generated\": \"" ++ now ++ "T00:00:00Z\",\n"
          ++ "  \"scope\": \"decidable WCAG subset (content tree)\",\n"
          ++ "  \"predicates\": [\"one-h1\", \"heading-no-skip\", \"alt-present-by-construction\"],\n"
          ++ "  \"pages\": [\n" ++ entries ++ "\n  ]\n"
          ++ "}\n"
  let dst = joinPath out ".well-known/accessibility-attestation.json"
  _ <- mkDirP (dirOf dst)
  ignore (writeFile dst json)
  putStrLn "  + .well-known/accessibility-attestation.json"
  where
    entryJson : (Page, Bool, List String) -> String
    entryJson (p, certified, viols) =
      "    {\"page\": \"" ++ jsonEsc (absUrl base p.url)
        ++ "\", \"certified\": " ++ (if certified then "true" else "false")
        ++ ", \"violations\": ["
        ++ concat (intersperse ", " (map (\v => "\"" ++ jsonEsc v ++ "\"") viols))
        ++ "]}"

-- Full build command.
buildSite : HasIO io => (src : String) -> (out : String) -> (base : String) -> io ()
buildSite src out base = do
  putStrLn ("Ddraig build: " ++ src ++ " -> " ++ out)
  ok <- isDir src
  if not ok
     then putStrLn ("ERROR: source dir not found: " ++ src)
     else do
       _ <- mkDirP out
       all <- walkFiles src ""
       -- skip files under templates/, public/, and the asset dirs (handled separately)
       let mdFiles = filter (\p => isMarkdown p && not (underSpecial p)) all
       putStrLn ("Found " ++ show (length mdFiles) ++ " markdown file(s).")
       results <- buildEach mdFiles
       let pages = map (\(p, _, _) => p) results
       copyAssets src out
       writeDefaultStyle src out
       copyPublic src out
       genSitemap base out pages
       genFeed base out pages
       now <- currentUtcDate
       writeAttestation base out now results
       putStrLn ("Done. " ++ show (length pages) ++ " page(s) built.")
       let failed = filter (\(_, c, _) => not c) results
       when (not (null failed)) $ do
         putStrLn ("ACCESSIBILITY: " ++ show (length failed) ++ " page(s) failed certification:")
         traverse_ (\(p, _, vs) => do
                      putStrLn ("  " ++ p.url)
                      traverse_ (\v => putStrLn ("    - " ++ v)) vs) failed
         exitFailure
  where
    underSpecial : String -> Bool
    underSpecial p =
      any (\d => strHasPrefix (d ++ "/") p)
          ["templates","public","assets","static","css","js","images"]
    buildEach : List String -> io (List (Page, Bool, List String))
    buildEach [] = pure []
    buildEach (f :: fs) = do
      mp <- buildOne src out base f
      rest <- buildEach fs
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
  let output = applyTemplate defTemplate fm "/welcome.html" md.body (buildToc md.toc)
  putStrLn output

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

-- ============================================================================
-- Main
-- ============================================================================

usage : IO ()
usage = do
  putStrLn "Ddraig SSG - Idris 2 powered (\"types that breathe fire\")"
  putStrLn ""
  putStrLn "Usage:"
  putStrLn "  ddraig build <src> <out> [base-url]  Build a site"
  putStrLn "        base-url (e.g. https://example.com) makes sitemap.xml and"
  putStrLn "        feed.xml URLs absolute (recommended; required for a valid sitemap)"
  putStrLn "  ddraig clean <out>         Remove built files under <out>"
  putStrLn "  ddraig validate-state <file.a2ml>  Validate an a2ml STATE descriptile"
  putStrLn "  ddraig --version           Print version"
  putStrLn "  ddraig --help              This help"
  putStrLn ""
  putStrLn "Test subcommands:"
  putStrLn "  ddraig test-markdown | test-frontmatter | test-full | test-state | test-attest"

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "test-markdown"] => testMarkdown
    [_, "test-frontmatter"] => testFrontmatter
    [_, "test-full"] => testFull
    [_, "test-state"] => testState
    [_, "test-attest"] => testAttest
    [_, "--version"] => putStrLn ("ddraig " ++ ddraigVersion)
    [_, "-v"] => putStrLn ("ddraig " ++ ddraigVersion)
    [_, "--help"] => usage
    [_, "-h"] => usage
    [_, "help"] => usage
    [_, "build", src, out] => buildSite src out ""
    [_, "build", src, out, base] => buildSite src out base
    [_, "clean", out] => cleanOut out
    [_, "validate-state", path] => validateStateFile path
    _ => usage
