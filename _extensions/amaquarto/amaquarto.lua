-- amaquarto.lua  (v0.3.0)
-- Lua filter for AMA Journal formatting (JM, JMR, JPPM)
-- Modes: "article" (single-column publication style) | "manuscript" (submission)

local footnote_count = 0
local first_heading_seen = false

local is_docx = quarto.doc.is_format("docx")
local is_latex = quarto.doc.is_format("latex") or quarto.doc.is_format("pdf")

-- PDF format: "article" or "manuscript" (default: "article")
local pdf_format = "article"

-- =========================================================================
-- Utilities
-- =========================================================================

local function count_words(text)
  local n = 0
  for _ in text:gmatch("%S+") do n = n + 1 end
  return n
end

local function meta_to_blocks(val)
  local t = pandoc.utils.type(val)
  if t == "Blocks" then return val
  elseif t == "Inlines" then return pandoc.Blocks({ pandoc.Para(val) })
  elseif t == "table" and val[1] then return pandoc.Blocks(val)
  else
    local s = pandoc.utils.stringify(val)
    if s ~= "" then return pandoc.Blocks({ pandoc.Para({ pandoc.Str(s) }) }) end
  end
  return nil
end

local function meta_to_latex(val)
  if val == nil then return "" end
  local t = pandoc.utils.type(val)
  local doc
  if t == "Inlines" then
    doc = pandoc.Pandoc({ pandoc.Para(val) })
  elseif t == "Blocks" then
    doc = pandoc.Pandoc(val)
  else
    return pandoc.utils.stringify(val)
  end
  local latex = pandoc.write(doc, "latex")
  return latex:gsub("^%s+", ""):gsub("%s+$", "")
end

local function safe_str(val)
  if val == nil then return "" end
  local s = pandoc.utils.stringify(val)
  if s and s ~= "" then return s end
  return ""
end

local function get_author_name(a)
  if a.name then
    if type(a.name) == "table" then
      if a.name.literal then return safe_str(a.name.literal) end
    end
    local n = safe_str(a.name)
    if n ~= "" then return n end
  end
  return safe_str(a)
end

local saved_meta = {}

-- =========================================================================
-- Meta filter: validate, configure PDF format, resolve paths
-- =========================================================================

function Meta(meta)
  -- ---- Resolve extension resource paths ----
  local ext_dir = pandoc.path.directory(PANDOC_SCRIPT_FILE)
  if meta.csl then
    local csl_name = pandoc.utils.stringify(meta.csl)
    local csl_full = pandoc.path.join({ ext_dir, csl_name })
    local fh = io.open(csl_full, "r")
    if fh then
      fh:close()
      meta.csl = pandoc.MetaInlines({ pandoc.Str(csl_full) })
    end
  end
  if is_docx and meta["reference-doc"] then
    local ref_name = pandoc.utils.stringify(meta["reference-doc"])
    local ref_full = pandoc.path.join({ ext_dir, ref_name })
    local fh = io.open(ref_full, "r")
    if fh then
      fh:close()
      meta["reference-doc"] = pandoc.MetaInlines({ pandoc.Str(ref_full) })
    end
  end

  -- ---- Validation warnings ----
  if meta.abstract then
    local wc = count_words(pandoc.utils.stringify(meta.abstract))
    if wc > 200 then
      quarto.log.warning("AMA style: Abstract limited to 200 words. Current: ~" .. wc)
    end
  end
  if meta.title then
    local wc = count_words(pandoc.utils.stringify(meta.title))
    if wc > 25 then
      quarto.log.warning("AMA style: Title should not exceed 25 words. Current: ~" .. wc)
    end
  end
  if meta.keywords and #meta.keywords > 8 then
    quarto.log.warning("AMA style: Include up to 8 keywords. Current: " .. #meta.keywords)
  end
  if meta["policy-contribution-statement"] then
    local wc = count_words(pandoc.utils.stringify(meta["policy-contribution-statement"]))
    if wc > 300 then
      quarto.log.warning("JPPM: Policy Contribution Statement max 300 words. Current: ~" .. wc)
    end
  end

  -- ---- Save fields for front matter ----
  saved_meta.title = meta.title and meta_to_latex(meta.title) or ""
  saved_meta.abstract = meta.abstract and meta_to_latex(meta.abstract) or ""
  saved_meta.abstract_plain = meta.abstract and pandoc.utils.stringify(meta.abstract) or ""
  saved_meta.keywords = {}
  if meta.keywords then
    for _, k in ipairs(meta.keywords) do
      table.insert(saved_meta.keywords, pandoc.utils.stringify(k))
    end
  end
  saved_meta.authors = {}
  if meta.author then
    local author_list = meta.author
    if pandoc.utils.type(author_list) == "Inlines" then
      table.insert(saved_meta.authors, { name = pandoc.utils.stringify(author_list) })
    else
      for _, a in ipairs(author_list) do
        table.insert(saved_meta.authors, { name = get_author_name(a) })
      end
    end
  end
  saved_meta.author_note = meta["author-note"] and meta_to_latex(meta["author-note"]) or ""
  saved_meta.anonymous = meta.anonymous and pandoc.utils.stringify(meta.anonymous) == "true"
  saved_meta.pcs = meta["policy-contribution-statement"] and meta_to_latex(meta["policy-contribution-statement"]) or ""
  saved_meta.pcs_plain = meta["policy-contribution-statement"] and pandoc.utils.stringify(meta["policy-contribution-statement"]) or ""

  -- ---- PDF format configuration ----
  if is_latex then
    if meta["pdf-format"] then
      pdf_format = pandoc.utils.stringify(meta["pdf-format"]):lower()
    end

    if pdf_format == "manuscript" then
      -- Manuscript: single-column, double-spaced, 12pt, 1-inch margins
      meta.fontsize = pandoc.MetaInlines({ pandoc.Str("12pt") })
      meta.linestretch = pandoc.MetaInlines({ pandoc.Str("2") })
      meta.geometry = pandoc.MetaList({
        pandoc.MetaInlines({ pandoc.Str("top=1in") }),
        pandoc.MetaInlines({ pandoc.Str("bottom=1in") }),
        pandoc.MetaInlines({ pandoc.Str("left=1in") }),
        pandoc.MetaInlines({ pandoc.Str("right=1in") })
      })
      meta.classoption = pandoc.MetaList({})
      meta["ama-manuscript"] = true
      meta.author = nil
      meta["by-author"] = nil
    else
      -- Article: single-column publication style
      meta.fontsize = pandoc.MetaInlines({ pandoc.Str("11pt") })
      meta.linestretch = pandoc.MetaInlines({ pandoc.Str("1.15") })
      meta.geometry = pandoc.MetaList({
        pandoc.MetaInlines({ pandoc.Str("top=1in") }),
        pandoc.MetaInlines({ pandoc.Str("bottom=1in") }),
        pandoc.MetaInlines({ pandoc.Str("left=1.25in") }),
        pandoc.MetaInlines({ pandoc.Str("right=1.25in") })
      })
      meta.classoption = pandoc.MetaList({})
      meta["ama-article"] = true
    end

    -- Clear title/author/abstract so Pandoc's default template doesn't render them
    meta.title = nil
    meta.abstract = nil
    meta.author = nil
    meta["by-author"] = nil
  end

  return meta
end

-- =========================================================================
-- Build article-mode LaTeX title block (single-column publication style)
-- =========================================================================
local function build_article_header()
  local lines = {}

  table.insert(lines, "\\amasetuparticle")
  table.insert(lines, "")

  -- Title: 16pt bold
  table.insert(lines, "{\\fontsize{16}{19}\\selectfont\\bfseries\\raggedright "
    .. saved_meta.title .. "\\par}%")
  table.insert(lines, "\\vskip 10pt")

  -- Authors (centered, bold) -- shown unless anonymous
  if not saved_meta.anonymous and #saved_meta.authors > 0 then
    table.insert(lines, "\\begin{center}")
    for _, a in ipairs(saved_meta.authors) do
      if a.name ~= "" then
        table.insert(lines, "{\\normalsize\\bfseries " .. a.name .. "\\par}%")
      end
    end
    table.insert(lines, "\\end{center}")
    table.insert(lines, "\\vskip 6pt")
  end

  -- Abstract
  if saved_meta.abstract ~= "" then
    table.insert(lines, "{\\noindent\\textbf{Abstract}\\par}")
    table.insert(lines, "\\vskip 4pt")
    table.insert(lines, "{\\noindent\\small " .. saved_meta.abstract .. "\\par}")
    table.insert(lines, "\\vskip 8pt")
    if #saved_meta.keywords > 0 then
      table.insert(lines, "{\\noindent\\textbf{Keywords}: \\small "
        .. table.concat(saved_meta.keywords, ", ") .. "\\par}")
      table.insert(lines, "\\vskip 8pt")
    end
  end

  -- Policy Contribution Statement (JPPM)
  if saved_meta.pcs ~= "" then
    table.insert(lines, "{\\noindent\\textbf{Policy Contribution Statement}\\par}")
    table.insert(lines, "\\vskip 4pt")
    table.insert(lines, "{\\noindent\\small " .. saved_meta.pcs .. "\\par}")
    table.insert(lines, "\\vskip 8pt")
  end

  table.insert(lines, "\\vskip 0.8\\baselineskip")
  table.insert(lines, "\\noindent\\rule{\\textwidth}{0.4pt}")
  table.insert(lines, "\\vskip 0.8\\baselineskip")

  -- Author note as first-page footnote
  if not saved_meta.anonymous and saved_meta.author_note ~= "" then
    table.insert(lines, "\\makeatletter")
    table.insert(lines, "\\def\\@makefnmark{}%")
    table.insert(lines, "\\footnotetext{\\fontsize{8}{10}\\selectfont\\raggedright")
    table.insert(lines, saved_meta.author_note)
    table.insert(lines, "}%")
    table.insert(lines, "\\makeatother")
  end

  return table.concat(lines, "\n")
end

-- =========================================================================
-- Header filter: validate heading levels and "Introduction" label
-- =========================================================================
function Header(el)
  if not first_heading_seen and el.level == 1 then
    first_heading_seen = true
    if pandoc.utils.stringify(el):lower() == "introduction" then
      quarto.log.warning("AMA style: Do not label opening commentary as 'Introduction'.")
    end
  end
  if el.level > 3 then
    quarto.log.warning("AMA style: Do not use more than three heading levels. Found level " .. el.level)
  end
  -- Appendix headers: auto-insert page break
  if el.level == 1 and el.classes:includes("appendix") then
    if is_latex then
      return pandoc.Blocks({
        pandoc.RawBlock("latex", "\\newpage"),
        el,
      })
    elseif is_docx then
      return pandoc.Blocks({
        pandoc.RawBlock("openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'),
        el,
      })
    end
  end
  return el
end

-- =========================================================================
-- Note filter: validate footnote count and word count
-- =========================================================================
function Note(el)
  footnote_count = footnote_count + 1
  if footnote_count > 10 then
    quarto.log.warning("AMA style: No more than 10 footnotes. Count: " .. footnote_count)
  end
  local wc = count_words(pandoc.utils.stringify(el))
  if wc > 40 then
    quarto.log.warning("AMA style: Footnotes max 40 words. Footnote " .. footnote_count .. " has ~" .. wc)
  end
  return el
end

-- =========================================================================
-- Div filter: .center, .noindent, .table-notes classes
-- =========================================================================
function Div(el)
  -- Table/figure notes: renders as small indented text below table
  if el.classes:includes("table-notes") then
    if is_latex then
      return pandoc.Blocks({
        pandoc.RawBlock("latex", "\\begin{amanotes}"),
        table.unpack(el.content),
        pandoc.RawBlock("latex", "\\end{amanotes}"),
      })
    elseif is_docx then
      local blocks = pandoc.Blocks({})
      for _, b in ipairs(el.content) do
        if b.t == "Para" then
          blocks:insert(pandoc.Para(b.content))
        else
          blocks:insert(b)
        end
      end
      return blocks
    end
  end

  -- Handle .center class
  if el.classes:includes("center") then
    if is_latex then
      local blocks = pandoc.List({})
      blocks:insert(pandoc.RawBlock("latex",
        "{\\setlength{\\parindent}{0pt}\\begin{center}"))
      blocks:extend(el.content)
      blocks:insert(pandoc.RawBlock("latex", "\\end{center}}"))
      return blocks
    elseif is_docx then
      local blocks = pandoc.List({})
      for _, block in ipairs(el.content) do
        if block.t == "Para" or block.t == "Plain" then
          local centered = pandoc.List({})
          centered:insert(pandoc.RawInline("openxml",
            '<w:pPr><w:ind w:firstLine="0"/><w:jc w:val="center"/></w:pPr>'))
          centered:extend(block.content)
          blocks:insert(pandoc.Para(centered))
        else
          blocks:insert(block)
        end
      end
      return blocks
    end
  end

  -- Handle .noindent class
  if el.classes:includes("noindent") then
    if is_latex then
      local blocks = pandoc.List({})
      blocks:insert(pandoc.RawBlock("latex", "{\\setlength{\\parindent}{0pt}"))
      blocks:extend(el.content)
      blocks:insert(pandoc.RawBlock("latex", "}"))
      return blocks
    elseif is_docx then
      local blocks = pandoc.List({})
      for _, block in ipairs(el.content) do
        if block.t == "Para" or block.t == "Plain" then
          local noind = pandoc.List({})
          noind:insert(pandoc.RawInline("openxml",
            '<w:pPr><w:ind w:firstLine="0"/></w:pPr>'))
          noind:extend(block.content)
          blocks:insert(pandoc.Para(noind))
        else
          blocks:insert(block)
        end
      end
      return blocks
    end
  end

  return el
end

-- =========================================================================
-- Pandoc filter: front matter + references page break
-- =========================================================================
function Pandoc(doc)
  local new_blocks = pandoc.Blocks({})

  if is_latex then
    if pdf_format == "article" then
      new_blocks:insert(pandoc.RawBlock("latex", build_article_header()))
    else
      -- Manuscript mode: build front matter
      local ms = {}
      table.insert(ms, "\\amasetupmanuscript")
      if saved_meta.title ~= "" then
        table.insert(ms, "\\begin{center}")
        table.insert(ms, "{\\large\\bfseries " .. saved_meta.title .. "}")
        table.insert(ms, "\\end{center}")
        table.insert(ms, "\\vspace{24pt}")
      end
      if saved_meta.abstract ~= "" then
        table.insert(ms, "\\begin{center}")
        table.insert(ms, "\\textbf{Abstract}")
        table.insert(ms, "\\end{center}")
        table.insert(ms, "\\vspace{6pt}")
        table.insert(ms, "\\noindent " .. saved_meta.abstract)
      end
      if #saved_meta.keywords > 0 then
        table.insert(ms, "\\vspace{12pt}")
        table.insert(ms, "\\noindent \\textit{Keywords}: "
          .. table.concat(saved_meta.keywords, ", "))
      end
      if saved_meta.pcs ~= "" then
        table.insert(ms, "\\vspace{12pt}")
        table.insert(ms, "\\begin{center}")
        table.insert(ms, "\\textbf{Policy Contribution Statement}")
        table.insert(ms, "\\end{center}")
        table.insert(ms, "\\vspace{6pt}")
        table.insert(ms, "\\noindent " .. saved_meta.pcs)
      end
      table.insert(ms, "\\newpage")
      new_blocks:insert(pandoc.RawBlock("latex", table.concat(ms, "\n")))
    end
  end

  -- DOCX front matter
  if is_docx then
    local front = pandoc.List({})
    doc.meta.author = nil
    doc.meta["by-author"] = nil

    if doc.meta.abstract then
      front:insert(pandoc.Header(1, { pandoc.Str("Abstract") }))
      local abs = meta_to_blocks(doc.meta.abstract)
      if abs then front:extend(abs) end
      doc.meta.abstract = nil
    end
    if doc.meta.keywords and #doc.meta.keywords > 0 then
      local kw = pandoc.List({})
      kw:insert(pandoc.Emph({ pandoc.Str("Keywords") }))
      kw:insert(pandoc.Str(":"))
      kw:insert(pandoc.Space())
      for i, k in ipairs(doc.meta.keywords) do
        if i > 1 then kw:insert(pandoc.Str(",")) kw:insert(pandoc.Space()) end
        kw:insert(pandoc.Str(pandoc.utils.stringify(k)))
      end
      front:insert(pandoc.Para(kw))
    end
    local pcs = doc.meta["policy-contribution-statement"]
    if pcs and pandoc.utils.stringify(pcs) ~= "" then
      front:insert(pandoc.Header(1, {
        pandoc.Str("Policy"), pandoc.Space(),
        pandoc.Str("Contribution"), pandoc.Space(),
        pandoc.Str("Statement")
      }))
      local pcs_blocks = meta_to_blocks(pcs)
      if pcs_blocks then front:extend(pcs_blocks) end
    end
    if #front > 0 then
      front:insert(pandoc.RawBlock("openxml",
        '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
    end
    local with_front = pandoc.List({})
    with_front:extend(front)
    with_front:extend(doc.blocks)
    doc.blocks = with_front
  end

  -- Page break before References heading
  new_blocks:extend(doc.blocks)
  local final = pandoc.List({})
  for i, block in ipairs(new_blocks) do
    if block.t == "Header" then
      local text = pandoc.utils.stringify(block):lower()
      if text == "references" then
        local has_refs = false
        for j = i + 1, math.min(i + 3, #new_blocks) do
          local b = new_blocks[j]
          if b and b.t == "Div" and b.identifier == "refs" then
            has_refs = true
            break
          end
        end
        if has_refs then
          if is_docx then
            final:insert(pandoc.RawBlock("openxml",
              '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
          elseif is_latex then
            final:insert(pandoc.RawBlock("latex", "\\clearpage"))
          end
        end
      end
    end
    final:insert(block)
  end

  doc.blocks = final
  return doc
end

-- =========================================================================
-- Filter chain
-- =========================================================================

return {
  { Meta = Meta },
  { Header = Header },
  { Note = Note },
  { Div = Div },
  { Pandoc = Pandoc }
}
