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
import System.Directory
import System.File

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
-- ============================================================================

doInline : String -> String
doInline text = go (unpack text)
  where
    -- read until a delimiter substring is found; returns (before, after-delim)
    -- as char lists; Nothing if not found.
    splitOnStr : List Char -> List Char -> Maybe (List Char, List Char)
    splitOnStr delim cs = goS cs []
      where
        goS : List Char -> List Char -> Maybe (List Char, List Char)
        goS [] _ = Nothing
        goS rest@(c :: more) acc =
          if isPrefixOf (pack delim) (pack rest)
             then Just (reverse acc, drop (length delim) rest)
             else goS more (c :: acc)
    -- read a balanced "[..]" then "(..)" for links/images
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
    go : List Char -> String
    go [] = ""
    -- image: ![alt](url)
    go ('!' :: '[' :: rest) =
      case readLink rest of
        Just (alt, url, after) =>
          "<img src=\"" ++ strEscape url ++ "\" alt=\"" ++ strEscape alt ++ "\" />" ++ go after
        Nothing => "!" ++ go ('[' :: rest)
    -- link: [text](url)
    go ('[' :: rest) =
      case readLink rest of
        Just (txt, url, after) =>
          "<a href=\"" ++ strEscape url ++ "\">" ++ go (unpack txt) ++ "</a>" ++ go after
        Nothing => "[" ++ go rest
    -- strikethrough
    go ('~' :: '~' :: rest) =
      case splitOnStr ['~','~'] rest of
        Just (inner, after) => "<del>" ++ go inner ++ "</del>" ++ go after
        Nothing => "~~" ++ go rest
    -- bold
    go ('*' :: '*' :: rest) =
      case splitOnStr ['*','*'] rest of
        Just (inner, after) => "<strong>" ++ go inner ++ "</strong>" ++ go after
        Nothing => "**" ++ go rest
    -- italic
    go ('*' :: rest) =
      case splitOnStr ['*'] rest of
        Just (inner, after) => "<em>" ++ go inner ++ "</em>" ++ go after
        Nothing => "*" ++ go rest
    -- inline code (verbatim, escaped)
    go ('`' :: rest) =
      case splitOnStr ['`'] rest of
        Just (inner, after) => "<code>" ++ strEscape (pack inner) ++ "</code>" ++ go after
        Nothing => "`" ++ go rest
    -- escape stray HTML-significant chars in plain text
    go ('<' :: rest) = "&lt;" ++ go rest
    go ('>' :: rest) = "&gt;" ++ go rest
    go ('&' :: rest) = "&amp;" ++ go rest
    go (c :: rest) = singleton c ++ go rest

-- ============================================================================
-- Block-level Markdown Parser
-- ============================================================================

-- Headings collected for TOC: (level, text, slug)
record Heading where
  constructor MkHeading
  level : Nat
  text  : String
  hslug : String

record ParserState where
  constructor MkState
  html        : String
  inPara      : Bool
  inCode      : Bool
  codeLang    : String
  listStack   : List (Nat, Bool, Bool)  -- (indent, ordered?, nested?) innermost last
  inQuote     : Bool
  headings    : List Heading      -- reverse order of appearance

initState : ParserState
initState = MkState "" False False "" [] False []

closePara : ParserState -> ParserState
closePara st = if st.inPara then { html $= (++ "</p>\n"), inPara := False } st else st

closeQuote : ParserState -> ParserState
closeQuote st = if st.inQuote then { html $= (++ "</blockquote>\n"), inQuote := False } st else st

-- close all open lists
closeLists : ParserState -> ParserState
closeLists st =
  case st.listStack of
    [] => st
    ((_, ordered, nested) :: rest) =>
      let close : String := if ordered then "</ol>\n" else "</ul>\n"
          tag : String := if nested then close ++ "</li>\n" else close
      in closeLists ({ html $= (++ tag), listStack := rest } st)

-- close blocks that cannot contain the next non-list/non-quote line
closeBlocks : ParserState -> ParserState
closeBlocks = closeLists . closeQuote . closePara

isHRule : String -> Bool
isHRule s =
  let t = trim s
  in (t == "---" || t == "***" || t == "___"
      || t == "----" || t == "*****" || t == "___" )
     && length t >= 3
     && allSame (unpack t)
  where allSame : List Char -> Bool
        allSame [] = True
        allSame (c :: cs) = all (== c) cs

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

-- Remove a single trailing "</li>\n" from a string, if present.  Used when a
-- nested list must be reparented INSIDE the previous <li> (valid HTML: a
-- <ul>/<ol> may not be a direct child of an <ol>/<ul>).
dropTrailingLiClose : String -> String
dropTrailingLiClose s =
  if strHasSuffix "</li>\n" s
     then substr 0 (length s `minus` 6) s
     else s

-- open a list of the given (indent, ordered, nested?) on top of the stack.
-- `nested` means this list was opened inside the previous <li>, so when it is
-- later closed we must also re-close that parent <li>.
openListN : Nat -> Bool -> Bool -> ParserState -> ParserState
openListN ind ordered nested st =
  let tag : String := if ordered then "<ol>\n" else "<ul>\n"
  in { html $= (++ tag), listStack $= ((ind, ordered, nested) ::) } st

openList : Nat -> Bool -> ParserState -> ParserState
openList ind ordered st = openListN ind ordered False st

-- pop lists whose indent is greater than the given indent
popDeeper : Nat -> ParserState -> ParserState
popDeeper ind st =
  case st.listStack of
    ((i, ordered, nested) :: rest) =>
      if i > ind
         then let close : String := if ordered then "</ol>\n" else "</ul>\n"
                  -- if nested, this list lived inside the parent <li>; close it
                  tag : String := if nested then close ++ "</li>\n" else close
              in popDeeper ind ({ html $= (++ tag), listStack := rest } st)
         else st
    [] => st

-- Handle a list item line at indent `ind`, ordered or not, with content `item`.
doListItem : Nat -> Bool -> String -> ParserState -> ParserState
doListItem ind ordered item st0 =
  let st1 = closeQuote (closePara st0)
      st2 = popDeeper ind st1
  in case st2.listStack of
       [] => addItem (openList ind ordered st2)
       ((i, ord, _) :: _) =>
         if i == ind
            then if ord == ordered
                    then addItem st2
                    else addItem (openList ind ordered (closeTop st2))
            else -- i < ind : nest a new list INSIDE the previous <li>
                 let st3 = { html $= dropTrailingLiClose } st2
                 in addItem (openListN ind ordered True st3)
  where
    closeTop : ParserState -> ParserState
    closeTop s = case s.listStack of
                   ((_, o, _) :: rest) =>
                     let tag : String := if o then "</ol>\n" else "</ul>\n"
                     in { html $= (++ tag), listStack := rest } s
                   [] => s
    addItem : ParserState -> ParserState
    addItem s = { html $= (++ "<li>" ++ doInline item ++ "</li>\n") } s

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

renderTable : List String -> ParserState -> (ParserState, List String)
renderTable (hdr :: sep :: rest) st =
  let headers = splitRow hdr
      st1 = { html $= (++ "<table>\n<thead>\n<tr>") } (closeBlocks st)
      st2 = foldl (\s, h => { html $= (++ "<th scope=\"col\">" ++ doInline h ++ "</th>") } s) st1 headers
      st3 = { html $= (++ "</tr>\n</thead>\n<tbody>\n") } st2
      (st4, remaining) = body rest st3
      st5 = { html $= (++ "</tbody>\n</table>\n") } st4
  in (st5, remaining)
  where
    body : List String -> ParserState -> (ParserState, List String)
    body ls s =
      case ls of
        (l :: more) =>
          if isTableRow l
             then let cells = splitRow l
                      s1 = { html $= (++ "<tr>") } s
                      s2 = foldl (\x, c => { html $= (++ "<td>" ++ doInline c ++ "</td>") } x) s1 cells
                      s3 = { html $= (++ "</tr>\n") } s2
                  in body more s3
             else (s, ls)
        [] => (s, [])
renderTable other st = (st, other)

-- Process one logical line; returns updated state and the remaining lines.
step : List String -> ParserState -> (ParserState, List String)
step [] st = (st, [])
step (line :: rest) st =
  let tr = trim line
  in
  -- inside fenced code: only ``` closes it
  if st.inCode
     then if strHasPrefix "```" tr
             then ({ html $= (++ "</code></pre>\n"), inCode := False, codeLang := "" } st, rest)
             else ({ html $= (++ strEscape line ++ "\n") } st, rest)
  -- open fenced code (with optional language)
  else if strHasPrefix "```" tr
     then let lang = trim (strDropPrefix "```" tr)
              st1 = closeBlocks st
              opener = if lang == ""
                          then "<pre><code>"
                          else "<pre><code class=\"language-" ++ strEscape lang ++ "\">"
          in ({ html $= (++ opener), inCode := True, codeLang := lang } st1, rest)
  -- blank line: close paragraph/quote (keep lists open for loose handling? close them)
  else if tr == ""
     then (closeBlocks st, rest)
  -- horizontal rule
  else if isHRule line
     then ({ html $= (++ "<hr />\n") } (closeBlocks st), rest)
  -- pipe table (needs a separator on the next line)
  else if isTableRow line
     then case rest of
            (sep :: more) =>
              if isTableSep sep
                 then renderTable (line :: sep :: more) st
                 else fallthroughPara line tr st rest
            _ => fallthroughPara line tr st rest
  -- raw HTML passthrough (verbatim)
  else if isRawHtml line
     then ({ html $= (++ line ++ "\n") } (closeBlocks st), rest)
  -- heading
  else case headingLevel line of
         Just (lvl, htext) =>
           let sl = slugify htext
               tag = "h" ++ show lvl
               h = MkHeading lvl htext sl
               st1 = closeBlocks st
           in ({ html $= (++ "<" ++ tag ++ " id=\"" ++ sl ++ "\">"
                              ++ doInline htext ++ "</" ++ tag ++ ">\n")
               , headings $= (h ::) } st1, rest)
         Nothing =>
  -- ordered list
           case orderedItem line of
             Just item => (doListItem (leadingIndent line) True item st, rest)
             Nothing =>
  -- unordered list
               case unorderedItem line of
                 Just item => (doListItem (leadingIndent line) False item st, rest)
                 Nothing =>
  -- blockquote
                   if strHasPrefix ">" tr
                      then let inner = trim (strDropPrefix ">" tr)
                               st1 = closeLists (closePara st)
                               st2 = if st1.inQuote then st1
                                     else { html $= (++ "<blockquote>\n"), inQuote := True } st1
                               -- support one level of nesting: >> text
                               body = if strHasPrefix ">" inner
                                         then "<blockquote>" ++ doInline (trim (strDropPrefix ">" inner)) ++ "</blockquote>"
                                         else doInline inner
                           in ({ html $= (++ "<p>" ++ body ++ "</p>\n") } st2, rest)
                      else fallthroughPara line tr st rest
  where
    fallthroughPara : String -> String -> ParserState -> List String -> (ParserState, List String)
    fallthroughPara _ trimmed s remaining =
      let s0 = closeLists (closeQuote s)
          s1 = if not s0.inPara
                  then { html $= (++ "<p>"), inPara := True } s0
                  else { html $= (++ " ") } s0
      in ({ html $= (++ doInline trimmed) } s1, remaining)

-- Drive the parser over all lines.
parseAll : List String -> ParserState -> ParserState
parseAll ls st =
  case step ls st of
    (st', []) => st'
    (st', rest@(_ :: _)) =>
      if length rest >= length ls
         then st'  -- safety: no progress, stop (should not happen)
         else parseAll rest st'

-- Result of parsing: HTML body + collected headings (in order).
record MdResult where
  constructor MkMdResult
  body     : String
  toc      : List Heading

parseMarkdownFull : String -> MdResult
parseMarkdownFull content =
  let allLines = lines content
      final = parseAll allLines initState
      st1 = closeBlocks final
      st2 = if st1.inCode then { html $= (++ "</code></pre>\n") } st1 else st1
  in MkMdResult st2.html (reverse st2.headings)

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
applyTemplate : String -> Frontmatter -> String -> String -> String
applyTemplate template fm htmlContent tocHtml =
  let brand = if fm.brand == "" then fm.title else fm.brand
      t1 = strReplace template "{{title}}" (strEscape fm.title)
      t2 = strReplace t1 "{{date}}" (strEscape fm.date)
      t3 = strReplace t2 "{{description}}" (strEscape fm.description)
      t4 = strReplace t3 "{{brand}}" (strEscape brand)
      t5 = strReplace t4 "{{toc}}" tocHtml
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

-- Build one markdown file. Returns Maybe Page (Nothing if draft skipped).
buildOne : HasIO io => (src : String) -> (out : String) -> (rel : String) -> io (Maybe Page)
buildOne src out rel = do
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
           let html = applyTemplate tpl fm2 md.body toc
           let relHtml = toHtmlPath rel
           let outPath = joinPath out relHtml
           _ <- mkDirP (dirOf outPath)
           w <- writeFile outPath html
           case w of
             Left e => do putStrLn ("  ! write error: " ++ outPath); pure Nothing
             Right () => do
               putStrLn ("  + " ++ rel ++ " -> " ++ relHtml)
               pure (Just (MkPage ("/" ++ relHtml) fm2))

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

-- sitemap.xml
genSitemap : HasIO io => (out : String) -> List Page -> io ()
genSitemap out pages = do
  let urls = concatMap entry pages
  let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            ++ "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
            ++ urls
            ++ "</urlset>\n"
  ignore (writeFile (joinPath out "sitemap.xml") xml)
  putStrLn "  + sitemap.xml"
  where
    entry : Page -> String
    entry pg = "  <url><loc>" ++ strEscape pg.url ++ "</loc>"
               ++ (if pg.fm.date == "" then "" else "<lastmod>" ++ strEscape pg.fm.date ++ "</lastmod>")
               ++ "</url>\n"

-- feed.xml (Atom)
genFeed : HasIO io => (out : String) -> List Page -> io ()
genFeed out pages = do
  let entries = concatMap entry pages
  let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            ++ "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            ++ "  <title>Ddraig Site</title>\n"
            ++ "  <generator>Ddraig SSG " ++ ddraigVersion ++ "</generator>\n"
            ++ entries
            ++ "</feed>\n"
  ignore (writeFile (joinPath out "feed.xml") xml)
  putStrLn "  + feed.xml"
  where
    entry : Page -> String
    entry pg = "  <entry>\n"
               ++ "    <title>" ++ strEscape pg.fm.title ++ "</title>\n"
               ++ "    <link href=\"" ++ strEscape pg.url ++ "\"/>\n"
               ++ (if pg.fm.date == "" then "" else "    <updated>" ++ strEscape pg.fm.date ++ "</updated>\n")
               ++ "    <summary>" ++ strEscape pg.fm.description ++ "</summary>\n"
               ++ "  </entry>\n"

-- Full build command.
buildSite : HasIO io => (src : String) -> (out : String) -> io ()
buildSite src out = do
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
       pages <- buildEach mdFiles
       copyAssets src out
       writeDefaultStyle src out
       copyPublic src out
       genSitemap out pages
       genFeed out pages
       putStrLn ("Done. " ++ show (length pages) ++ " page(s) built.")
  where
    underSpecial : String -> Bool
    underSpecial p =
      any (\d => strHasPrefix (d ++ "/") p)
          ["templates","public","assets","static","css","js","images"]
    buildEach : List String -> io (List Page)
    buildEach [] = pure []
    buildEach (f :: fs) = do
      mp <- buildOne src out f
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
  let content = "<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->\n---\ntitle: My Post\ndate: 2024-01-15\ntags: [idris, ssg]\ndraft: false\ndescription: hi\nsite: Ddraig\n---\n\nContent here\n"
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
  let output = applyTemplate defTemplate fm md.body (buildToc md.toc)
  putStrLn output

-- ============================================================================
-- Main
-- ============================================================================

usage : IO ()
usage = do
  putStrLn "Ddraig SSG - Idris 2 powered (\"types that breathe fire\")"
  putStrLn ""
  putStrLn "Usage:"
  putStrLn "  ddraig build <src> <out>   Build a site"
  putStrLn "  ddraig clean <out>         Remove built files under <out>"
  putStrLn "  ddraig --version           Print version"
  putStrLn "  ddraig --help              This help"
  putStrLn ""
  putStrLn "Test subcommands:"
  putStrLn "  ddraig test-markdown | test-frontmatter | test-full"

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "test-markdown"] => testMarkdown
    [_, "test-frontmatter"] => testFrontmatter
    [_, "test-full"] => testFull
    [_, "--version"] => putStrLn ("ddraig " ++ ddraigVersion)
    [_, "-v"] => putStrLn ("ddraig " ++ ddraigVersion)
    [_, "--help"] => usage
    [_, "-h"] => usage
    [_, "help"] => usage
    [_, "build", src, out] => buildSite src out
    [_, "clean", out] => cleanOut out
    _ => usage
