-- amaquarto.lua  (amaquarto 1.0.0)
-- American Marketing Association journals: Journal of Marketing, Journal of
-- Marketing Research, Journal of Public Policy & Marketing, Journal of
-- International Marketing, and Journal of Interactive Marketing.
-- Quarto/Pandoc filter, run before Quarto's own filters. amaquarto-post.lua runs
-- after them and formats captions and Word tables.
-- Modes (ama-mode): "manuscript" (default, the main document for review) |
-- "title-page" | "web-appendix" | "article" (a publication-style preview)
--
-- Rules follow AMA's submission guidelines, Word templates, and sample files:
--   https://www.ama.org/submission-guidelines-american-marketing-association-journals/

-- =========================================================================
-- Journal settings
-- =========================================================================
local J = {
  id = "ama",       -- prefix of the options (ama-mode) and of the LaTeX commands
  label = "AMA",    -- used in messages
  modes = { manuscript = true, article = true, ["title-page"] = true, ["web-appendix"] = true },
  default_mode = "manuscript",
  -- AMA submission guidelines: limits checked during rendering
  limits = {
    title_words = 25,
    abstract_words = 200,
    keywords_max = 8,
    footnotes = 10,
    footnotes_text = "most articles contain no more than 10 footnotes",
    footnote_words = 40,
    heading_levels = 3,
  },
  check_single_secondary = true,
  check_single_tertiary = true,
  warn_introduction = "AMA's sample document begins the text without an \"Introduction\" heading.",
  -- Column heads in bold, as in AMA's Word template
  table_header_bold = true,
  -- Notes under tables and figures: "Notes: ..." with the label in italics
  note = { label = "Notes", after = ":", italic = true },
  -- Appendixes follow the references, each on a new page; their tables,
  -- figures, and equations are numbered A1, A2, ... (B1, B2, ...)
  appendix = { position = "after-references", page_break = true, numbering = true,
    float_sep = "", eq_sep = "", single_letter = "A" },
  refs_heading = "References",
  floats = { default = "inline", order = { "Table", "Figure" }, callout = "[Insert %s about here]" },
  footnotes = { default = "page", heading = "Footnotes" },
}

-- =========================================================================
-- Shared code (the same in every extension of this family)
-- =========================================================================
local has_quarto = (quarto ~= nil)

local is_docx, is_latex
if has_quarto then
  is_docx = quarto.doc.is_format("docx")
  is_latex = quarto.doc.is_format("latex") or quarto.doc.is_format("pdf")
else
  is_docx = (FORMAT == "docx")
  is_latex = (FORMAT == "latex") or (FORMAT == "pdf")
end

local ID = J.id
local mode = "manuscript"   -- set in Meta
local O = {}                -- options read from the document
local M = {}                -- front matter saved from the metadata
local footnote_count = 0
local floats_by_cid = {}    -- Quarto's float nodes: internal id -> { id, type }

local function log_warning(msg)
  if has_quarto then quarto.log.warning(msg)
  else io.stderr:write("WARNING: " .. msg .. "\n") end
end

local function log_info(msg)
  if has_quarto then quarto.log.output(msg)
  else io.stderr:write(msg .. "\n") end
end

local function count_words(text)
  local n = 0
  for _ in text:gmatch("%S+") do n = n + 1 end
  return n
end

local function stringify(val)
  if val == nil then return "" end
  if type(val) == "boolean" then return val and "true" or "false" end
  return pandoc.utils.stringify(val)
end

local function to_blocks(val)
  if val == nil then return nil end
  local t = pandoc.utils.type(val)
  if t == "Blocks" then
    if #val == 0 then return nil end
    return val
  elseif t == "Inlines" then
    if #val == 0 then return nil end
    return pandoc.Blocks({ pandoc.Para(val) })
  elseif t == "table" and val[1] then return pandoc.Blocks(val)
  end
  local s = stringify(val)
  if s ~= "" then return pandoc.Blocks({ pandoc.Para(pandoc.Inlines(s)) }) end
  return nil
end

local function to_inlines(val)
  if val == nil then return nil end
  local t = pandoc.utils.type(val)
  if t == "Inlines" then
    if #val == 0 then return nil end
    return val
  elseif t == "Blocks" then
    if #val == 0 then return nil end
    return pandoc.utils.blocks_to_inlines(val)
  end
  local s = stringify(val)
  if s ~= "" then return pandoc.Inlines(s) end
  return nil
end

local function inlines_to_latex(inl)
  if inl == nil then return "" end
  local s = pandoc.write(pandoc.Pandoc({ pandoc.Plain(inl) }), "latex")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function blocks_to_latex(blocks)
  if blocks == nil then return "" end
  local s = pandoc.write(pandoc.Pandoc(blocks), "latex")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Options are written with the journal's prefix, for example "ama-mode"
local function opt_raw(meta, name) return meta[ID .. "-" .. name] end

local function opt_string(meta, name, default)
  local v = opt_raw(meta, name)
  if v == nil then return default end
  local s = stringify(v)
  if s == "" then return default end
  return s
end

local function as_bool(v, default)
  if v == nil then return default end
  if type(v) == "boolean" then return v end
  local s = stringify(v):lower()
  if s == "true" or s == "yes" then return true end
  if s == "false" or s == "no" then return false end
  return default
end

local function opt_bool(meta, name, default) return as_bool(opt_raw(meta, name), default) end

-- First value that is set among several metadata keys
local function first_meta(meta, keys)
  for _, k in ipairs(keys) do
    if meta[k] ~= nil and stringify(meta[k]) ~= "" then return meta[k] end
  end
  return nil
end

local function latex(s) return pandoc.RawBlock("latex", s) end

-- Word paragraphs with a named style from the reference document
local function styled(style, blocks)
  return pandoc.Div(blocks, pandoc.Attr("", {}, { ["custom-style"] = style }))
end

-- A page break that leaves no empty line at the top of the next page
local function docx_page_break()
  return pandoc.RawBlock("openxml",
    '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr>'
    .. '<w:r><w:br w:type="page"/></w:r></w:p>')
end

local function page_break()
  if is_latex then return latex("\\clearpage") end
  if is_docx then return docx_page_break() end
  return nil
end

local function is_page_break(b)
  if b == nil or b.t ~= "RawBlock" then return false end
  if b.format == "latex" then return b.text == "\\clearpage" or b.text == "\\newpage" end
  if b.format == "openxml" then return b.text:find('w:br w:type="page"', 1, true) ~= nil end
  return false
end

-- A front matter element: a LaTeX environment in the PDF and .tex outputs
-- (defined in the header file) and a paragraph style in Word
local function element(env, style, blocks)
  local out = pandoc.Blocks({})
  if blocks == nil or #blocks == 0 then return out end
  if is_latex then
    out:insert(latex("\\begin{" .. ID .. env .. "}"))
    out:extend(blocks)
    out:insert(latex("\\end{" .. ID .. env .. "}"))
  elseif is_docx then
    out:insert(styled(style, blocks))
  else
    out:extend(blocks)
  end
  return out
end

local function para(...)
  local inl = pandoc.Inlines({})
  for _, x in ipairs({ ... }) do
    if type(x) == "string" then inl:extend(pandoc.Inlines(x))
    elseif pandoc.utils.type(x) == "Inlines" then inl:extend(x)
    elseif x ~= nil then inl:insert(x) end
  end
  return pandoc.Para(inl)
end

local function header_text_of(b) return pandoc.utils.stringify(b.content) end

local function join_strings(list, sep)
  local out = {}
  for _, s in ipairs(list) do if s and s ~= "" then out[#out + 1] = s end end
  return table.concat(out, sep)
end

-- Does a list of blocks contain a kind of element?
local function contains(blocks, kinds)
  local found = {}
  local filter = {}
  for name, key in pairs(kinds) do
    filter[name] = function() found[key] = true end
  end
  pandoc.Pandoc(blocks):walk(filter)
  return found
end

-- -------------------------------------------------------------------------
-- Authors, as Quarto normalizes them (name, email, affiliations, and so on)
-- -------------------------------------------------------------------------
local function read_authors(meta)
  local authors = {}
  local list = meta["by-author"]
  if list == nil or #list == 0 then
    -- plain Pandoc, or a simple list of names
    local raw = meta.author
    if raw == nil then return authors end
    if pandoc.utils.type(raw) == "Inlines" then
      table.insert(authors, { name = stringify(raw), affiliations = {} })
    else
      for _, a in ipairs(raw) do
        local name = (type(a) == "table" and a.name) and stringify(a.name) or stringify(a)
        table.insert(authors, { name = name, affiliations = {} })
      end
    end
    return authors
  end
  for _, a in ipairs(list) do
    local name = ""
    if a.name then
      if a.name.literal then name = stringify(a.name.literal)
      else name = join_strings({ stringify(a.name.given), stringify(a.name.family) }, " ") end
    end
    local extra = a.metadata or {}
    local function field(key)
      if a[key] ~= nil and stringify(a[key]) ~= "" then return stringify(a[key]) end
      if extra[key] ~= nil and stringify(extra[key]) ~= "" then return stringify(extra[key]) end
      return ""
    end
    local entry = {
      name = name,
      email = field("email"),
      phone = field("phone"),
      orcid = field("orcid"),
      position = field("position"),
      address = field("address"),
      degrees = field("degrees"),
      present = field("present-address"),
      permanent = field("permanent-address"),
      biography = field("biography"),
      corresponding = a.attributes and as_bool(a.attributes.corresponding, false) or false,
      affiliations = {},
    }
    if a.affiliations then
      for _, f in ipairs(a.affiliations) do
        local aff = {
          name = stringify(f.name),
          department = stringify(f.department),
          address = stringify(f.address),
          city = stringify(f.city),
          region = stringify(f.region),
          country = stringify(f.country),
          postal = stringify(f["postal-code"]),
        }
        aff.text = join_strings({ aff.department, aff.name, aff.address, aff.city,
          join_strings({ aff.region, aff.postal }, " "), aff.country }, ", ")
        table.insert(entry.affiliations, aff)
      end
    end
    table.insert(authors, entry)
  end
  return authors
end

local function author_names(authors)
  local names = {}
  for _, a in ipairs(authors) do if a.name ~= "" then names[#names + 1] = a.name end end
  return names
end

-- "A", "A and B", "A, B, and C"
local function join_names(names)
  if #names == 0 then return "" end
  if #names == 1 then return names[1] end
  if #names == 2 then return names[1] .. " and " .. names[2] end
  return table.concat(names, ", ", 1, #names - 1) .. ", and " .. names[#names]
end

local function corresponding_author(authors)
  for _, a in ipairs(authors) do if a.corresponding then return a end end
  return authors[1]
end

-- Unique affiliations in order of appearance, with a letter for each
local function affiliation_index(authors)
  local list, index = {}, {}
  for _, a in ipairs(authors) do
    a.letters = {}
    for _, f in ipairs(a.affiliations) do
      if f.text ~= "" then
        if not index[f.text] then
          list[#list + 1] = f.text
          index[f.text] = string.char(96 + #list)
        end
        table.insert(a.letters, index[f.text])
      end
    end
  end
  return list, index
end

-- -------------------------------------------------------------------------
-- Statements and declarations, written in the metadata as
--   declarations:
--     funding: ...
--     conflict-of-interest: ...
-- -------------------------------------------------------------------------
local DECLARATION_KEYS = {
  ethics = { "ethics", "ethical-considerations", "ethics-approval", "ethical-approval", "ethics-statement" },
  consent = { "consent", "consent-to-participate", "informed-consent" },
  conflict = { "conflict", "conflicting-interest", "conflicting-interests", "conflict-of-interest",
    "conflicts-of-interest", "competing-interests", "competing-interest", "declaration-of-interest" },
  funding = { "funding", "funding-statement" },
  data = { "data", "data-availability", "data-availability-statement" },
  contributions = { "contributions", "author-contributions", "credit" },
  ai = { "ai", "generative-ai", "ai-use", "ai-declaration" },
}

local function read_declarations(meta)
  local known, extras = {}, {}
  local d = meta.declarations
  if d == nil or type(d) ~= "table" then return known, extras end
  local used = {}
  for canon, names in pairs(DECLARATION_KEYS) do
    for _, n in ipairs(names) do
      if d[n] ~= nil then
        if known[canon] == nil then known[canon] = to_blocks(d[n]) end
        used[n] = true
      end
    end
  end
  for k, v in pairs(d) do
    if not used[k] then table.insert(extras, { key = k, blocks = to_blocks(v) }) end
  end
  table.sort(extras, function(a, b) return a.key < b.key end)
  return known, extras
end

-- Statements written in a metadata file (_title-page.yml) and statements
-- written in the document must both be kept. Newer versions of Quarto merge
-- the two "declarations" maps; Quarto 1.5 lets the document's map replace
-- the file's. Quarto does not pass "metadata-files" on to filters, so the
-- list is read from the top of the document, the files are read again, and
-- the statements that are missing are added.
local function declarations_from_files()
  local input = has_quarto and quarto.doc and quarto.doc.input_file or nil
  if not input then return nil end
  local fh = io.open(input, "r")
  if not fh then return nil end
  local source = fh:read("a") .. "\n"
  fh:close()
  local yaml = source:match("^\239?\187?\191?%-%-%-[ \t]*\r?\n(.-)\r?\n%-%-%-[ \t]*\r?\n")
  if not yaml then return nil end
  local ok, front = pcall(pandoc.read, "---\n" .. yaml .. "\n---\n", "markdown")
  if not ok or not front then return nil end
  local list = front.meta["metadata-files"]
  if list == nil then return nil end
  local names = {}
  if pandoc.utils.type(list) == "List" or (type(list) == "table" and list[1]) then
    for _, x in ipairs(list) do names[#names + 1] = stringify(x) end
  else
    names[1] = stringify(list)
  end
  local base = pandoc.path.directory(input)
  local found = {}
  for _, name in ipairs(names) do
    local path = name
    if not pandoc.path.is_absolute(path) then path = pandoc.path.join({ base, path }) end
    local mf = io.open(path, "r")
    if mf then
      local text = mf:read("a")
      mf:close()
      local parsed_ok, parsed = pcall(pandoc.read, "---\n" .. text .. "\n---\n", "markdown")
      if parsed_ok and parsed and type(parsed.meta.declarations) == "table" then
        for k, v in pairs(parsed.meta.declarations) do
          if found[k] == nil then found[k] = v end
        end
      end
    end
  end
  return found
end

local function title_from_key(key)
  local s = key:gsub("[-_]", " ")
  return (s:gsub("^%l", string.upper))
end

-- Headings and texts of the statements the journal asks for, in its order;
-- statements under other names follow
local function declaration_blocks(specs, level)
  local out = pandoc.Blocks({})
  local function add(title, blocks)
    if blocks then
      out:insert(pandoc.Header(level, pandoc.Inlines(title), pandoc.Attr("", { "unnumbered" })))
      out:extend(blocks)
    end
  end
  for _, spec in ipairs(specs) do add(spec[2], M.declarations[spec[1]]) end
  for _, e in ipairs(M.declaration_extras) do add(title_from_key(e.key), e.blocks) end
  return out
end

-- =========================================================================
-- Meta: options, front matter, checks
-- =========================================================================
local Journal = {}   -- filled in by the journal's own section below

local function check_limits()
  local L = J.limits or {}
  if M.title_plain ~= "" and L.title_words then
    local wc = count_words(M.title_plain)
    if wc > L.title_words then
      log_warning(J.label .. ": the title is limited to " .. L.title_words .. " words. Current: " .. wc)
    end
  end
  if M.abstract_plain ~= "" then
    local wc = count_words(M.abstract_plain)
    if L.abstract_words and wc > L.abstract_words then
      local rule = L.abstract_text or ("the abstract is limited to " .. L.abstract_words .. " words")
      log_warning(J.label .. ": " .. rule .. ". Current: about " .. wc)
    end
    if L.abstract_plain_only and M.abstract_blocks then
      local bad = contains(M.abstract_blocks,
        { Cite = "citations", Link = "links", Image = "figures", Table = "tables" })
      local names = {}
      for _, k in ipairs({ "citations", "links", "tables", "figures" }) do
        if bad[k] then names[#names + 1] = k end
      end
      if #names > 0 then
        log_warning(J.label .. ": the abstract may not contain " .. table.concat(names, ", ") .. ".")
      end
    end
  end
  local n = #M.keywords
  if n > 0 or L.keywords_min then
    if (L.keywords_min and n < L.keywords_min) or (L.keywords_max and n > L.keywords_max) then
      local range
      if L.keywords_min and L.keywords_max then range = L.keywords_min .. " to " .. L.keywords_max
      elseif L.keywords_max then range = "up to " .. L.keywords_max
      else range = "at least " .. L.keywords_min end
      log_warning(J.label .. ": include " .. range .. " keywords. Current: " .. n)
    end
  end
end

function Meta(meta)
  -- Rendering mode
  mode = opt_string(meta, "mode", J.default_mode or "manuscript"):lower()
  if Journal.resolve_mode then mode = Journal.resolve_mode(meta, mode) end
  if J.mode_aliases and J.mode_aliases[mode] then mode = J.mode_aliases[mode] end
  if not J.modes[mode] then
    local names = {}
    for k, _ in pairs(J.modes) do names[#names + 1] = k end
    table.sort(names)
    log_warning(J.label .. ": unknown " .. ID .. "-mode \"" .. mode .. "\"; using \"manuscript\". Available: "
      .. table.concat(names, ", "))
    mode = "manuscript"
  end
  -- The article layout exists only in the PDF and .tex outputs
  O.article = (mode == "article") and is_latex
  O.anonymous = as_bool(meta.anonymous, J.anonymous_default ~= false)
  O.floats = opt_string(meta, "floats", (J.floats and J.floats.default) or "inline"):lower()
  O.footnotes = opt_string(meta, "footnotes", (J.footnotes and J.footnotes.default) or "page"):lower()
  -- Figures as separate files, for journals that ask for them: "embedded"
  -- (in the manuscript only), "files" (in the manuscript and as files), or
  -- "separate" (as files; the manuscript prints their captions)
  O.figures = "embedded"
  if J.figure_files then
    O.figures = opt_string(meta, "figures", "embedded"):lower()
    if O.figures ~= "embedded" and O.figures ~= "files" and O.figures ~= "separate" then
      log_warning(J.label .. ": unknown " .. ID .. "-figures \"" .. O.figures
        .. "\"; using \"embedded\". Available: embedded, files, separate")
      O.figures = "embedded"
    end
  end
  O.note_label = opt_string(meta, "note-label", nil)
  O.has_bibliography = (meta.bibliography ~= nil) or (meta.references ~= nil)
  O.has_nocite = (meta.nocite ~= nil)

  -- Extension resources (Quarto also resolves these; kept for plain Pandoc use)
  local ext_dir = pandoc.path.directory(PANDOC_SCRIPT_FILE)
  if meta.csl then
    local csl_full = pandoc.path.join({ ext_dir, stringify(meta.csl) })
    local fh = io.open(csl_full, "r")
    if fh then fh:close(); meta.csl = pandoc.MetaInlines({ pandoc.Str(csl_full) }) end
  end
  if is_docx and meta["reference-doc"] then
    local ref_full = pandoc.path.join({ ext_dir, stringify(meta["reference-doc"]) })
    local fh = io.open(ref_full, "r")
    if fh then fh:close(); meta["reference-doc"] = pandoc.MetaInlines({ pandoc.Str(ref_full) }) end
  end

  -- Save the front matter before it is removed from the metadata
  M.title = to_inlines(meta.title)
  M.title_plain = stringify(meta.title)
  M.subtitle = to_inlines(meta.subtitle)
  M.abstract_blocks = to_blocks(meta.abstract)
  M.abstract_plain = stringify(meta.abstract)
  M.keywords = {}
  if meta.keywords then
    if pandoc.utils.type(meta.keywords) == "List" or (type(meta.keywords) == "table" and meta.keywords[1]) then
      for _, k in ipairs(meta.keywords) do table.insert(M.keywords, stringify(k)) end
    else
      for k in stringify(meta.keywords):gmatch("[^,;]+") do
        table.insert(M.keywords, (k:gsub("^%s+", ""):gsub("%s+$", "")))
      end
    end
  end
  M.authors = read_authors(meta)
  M.author_note = to_blocks(first_meta(meta, { "author-note", ID .. "-author-note", "authornote" }))
  M.acknowledgments = to_blocks(first_meta(meta, { "acknowledgments", "acknowledgements" }))
  M.funding = to_blocks(first_meta(meta, { "funding-statement", "funding" }))
  M.data_statement = to_blocks(first_meta(meta, { "data-availability-statement", "data-availability" }))
  local from_files = declarations_from_files()
  if from_files and next(from_files) ~= nil then
    local d = meta.declarations
    if d == nil or type(d) ~= "table" then d = {} end
    for k, v in pairs(from_files) do
      if d[k] == nil then d[k] = v end
    end
    meta.declarations = d
  end
  M.declarations, M.declaration_extras = read_declarations(meta)
  -- Highlights (journals that take them): a list of short bullet points
  M.highlights = {}
  if meta.highlights ~= nil and type(meta.highlights) == "table" then
    for _, item in ipairs(meta.highlights) do
      local text = stringify(item)
      if text ~= "" then table.insert(M.highlights, { text = text, inlines = to_inlines(item) }) end
    end
    meta.highlights = nil
  end
  if M.declarations.funding == nil then M.declarations.funding = M.funding end
  if M.declarations.data == nil then M.declarations.data = M.data_statement end
  meta.declarations = nil
  if Journal.read_meta then Journal.read_meta(meta) end

  -- Article layout: a publication-style preview, not a submission format
  if O.article then
    meta.fontsize = pandoc.MetaInlines({ pandoc.Str("11pt") })
    meta.linestretch = pandoc.MetaInlines({ pandoc.Str("1.15") })
    meta.geometry = pandoc.MetaList({
      pandoc.MetaInlines({ pandoc.Str("top=1in") }),
      pandoc.MetaInlines({ pandoc.Str("bottom=1in") }),
      pandoc.MetaInlines({ pandoc.Str("left=1.25in") }),
      pandoc.MetaInlines({ pandoc.Str("right=1.25in") }),
    })
    meta.classoption = pandoc.MetaList({})
    meta["number-sections"] = false
  elseif Journal.layout then
    Journal.layout(meta)
  end

  -- The filter writes the front matter itself. Removing the authors also
  -- keeps their names out of the properties of the Word and PDF files.
  if is_latex or is_docx then
    meta.title = nil
    meta.subtitle = nil
    meta.abstract = nil
    meta.author = nil
    meta.authors = nil
    meta["by-author"] = nil
    meta.affiliations = nil
    meta.institute = nil
    meta.date = nil
    if O.anonymous then meta["author-meta"] = nil end
  end

  if mode == "manuscript" or mode == "article" then check_limits() end
  return meta
end

-- -------------------------------------------------------------------------
-- Highlights: 3 to 5 bullet points of at most 85 characters each, in a
-- separate file with "highlights" in its name
-- -------------------------------------------------------------------------
local function check_highlights(items)
  local n = #items
  if n < 3 or n > 5 then
    log_warning(J.label .. ": highlights consist of 3 to 5 bullet points. Current: " .. n)
  end
  for i, text in ipairs(items) do
    local len = utf8.len(text) or #text
    if len > 85 then
      log_warning(J.label .. ": a highlight has at most 85 characters, including spaces. Highlight " .. i
        .. " has " .. len .. ".")
    end
  end
end

local function highlights_page()
  local out = pandoc.Blocks({})
  out:extend(element("title", "Title", { pandoc.Para(pandoc.Inlines("Highlights")) }))
  if #M.highlights > 0 then
    local items, texts = {}, {}
    for _, hl in ipairs(M.highlights) do
      table.insert(items, { pandoc.Plain(hl.inlines) })
      table.insert(texts, hl.text)
    end
    check_highlights(texts)
    out:insert(pandoc.BulletList(items))
  end
  return out
end

-- Highlights typed as a list in the body of the highlights file
local function check_highlights_body(body)
  if #M.highlights > 0 then return end
  for _, b in ipairs(body) do
    if b.t == "BulletList" then
      local texts = {}
      for _, item in ipairs(b.content) do
        table.insert(texts, pandoc.utils.stringify(pandoc.Div(item)))
      end
      check_highlights(texts)
      return
    end
  end
  log_warning(J.label .. ": no highlights found. List 3 to 5 under \"highlights:\" in the document options.")
end

-- =========================================================================
-- Journal front matter
-- =========================================================================
local DISCLOSURE = "These materials have been supplied by the authors to aid in the understanding "
  .. "of their paper. The AMA is sharing these materials at the request of the authors."

-- Documents written for amaquarto 0.3 chose the PDF layout with "pdf-format"
function Journal.resolve_mode(meta, m)
  if opt_raw(meta, "mode") == nil and meta["pdf-format"] ~= nil then
    local pf = stringify(meta["pdf-format"]):lower()
    if pf == "article" or pf == "manuscript" then return pf end
  end
  return m
end

function Journal.read_meta(meta)
  -- Journal of Public Policy & Marketing: policy contribution statement
  M.pcs = to_blocks(meta["policy-contribution-statement"])
  if M.pcs then
    local wc = count_words(stringify(meta["policy-contribution-statement"]))
    if wc > 300 then
      log_warning("JPP&M: the policy contribution statement should not exceed 300 words. Current: about " .. wc)
    end
  end
  O.reference_spacing = opt_string(meta, "reference-spacing", "double"):lower()
  O.toc = opt_bool(meta, "toc", true)
end

-- Every number in a web appendix carries a "W": Table W1, Figure W1, (W1)
function Journal.fixed_prefix()
  if mode == "web-appendix" then return "W" end
  return nil
end

local function author_line(a)
  local aff = a.affiliations[1]
  local parts = { a.name, a.position }
  if aff then
    table.insert(parts, join_strings({ aff.department, aff.name }, ", "))
    table.insert(parts, join_strings({ aff.address, aff.city, aff.region, aff.country }, ", "))
  end
  table.insert(parts, a.phone)
  table.insert(parts, a.email)
  return join_strings(parts, ", ")
end

local function labeled(label, blocks)
  -- "Label: text", with the label joined to the first paragraph
  local out = blocks:clone()
  local lead = pandoc.Inlines({ pandoc.Strong(pandoc.Inlines(label .. ":")), pandoc.Space() })
  if out[1] and (out[1].t == "Para" or out[1].t == "Plain") then
    lead:extend(out[1].content)
    out[1] = pandoc.Para(lead)
  else
    out:insert(1, pandoc.Para(lead))
  end
  return out
end

local function author_block()
  local out = pandoc.Blocks({})
  if #M.authors > 0 then
    local lines = pandoc.Blocks({})
    for _, a in ipairs(M.authors) do
      local s = author_line(a)
      if s ~= "" then lines:insert(pandoc.Para(pandoc.Inlines(s))) end
    end
    out:extend(element("authors", "Author", lines))
  end
  return out
end

-- The statements AMA asks for on the title page, in the order of its template
local STATEMENTS = {
  { "ethics", "Ethical Considerations" },
  { "consent", "Consent to Participate" },
  { "conflict", "Declaration of Conflicting Interest" },
  { "funding", "Funding" },
  { "data", "Data Availability" },
}

-- File 1: the title page
local function title_page()
  local out = pandoc.Blocks({})
  if M.title then out:extend(element("title", "Title", { pandoc.Para(M.title) })) end
  out:extend(author_block())
  local details = pandoc.Blocks({})
  local c = corresponding_author(M.authors)
  if c and c.name ~= "" then
    local aff = c.affiliations[1]
    local where = c.address
    if where == "" and aff then where = aff.text end
    details:extend(labeled("Corresponding author",
      pandoc.Blocks({ pandoc.Para(pandoc.Inlines(join_strings({ c.name, where, c.phone, c.email }, ", "))) })))
  end
  if M.author_note then details:extend(labeled("Author notes", M.author_note)) end
  if M.acknowledgments then details:extend(labeled("Acknowledgments", M.acknowledgments)) end
  out:extend(element("frontlines", "Front Text", details))
  local statements = declaration_blocks(STATEMENTS, 2)
  if #statements > 0 then
    out:insert(pandoc.Header(1, pandoc.Inlines("Statements and Declarations"),
      pandoc.Attr("statements-and-declarations", { "unnumbered" })))
    if is_latex then
      out:insert(latex("\\begin{amastatements}"))
      out:extend(statements)
      out:insert(latex("\\end{amastatements}"))
    else
      out:extend(statements:map(function(b)
        if b.t == "Para" and is_docx then return styled("Statement", { b }) end
        return b
      end))
    end
  end
  return out
end

-- File 3: the first page of the web appendix
local function web_appendix_front(doc)
  local out = pandoc.Blocks({})
  if is_latex then out:insert(latex("\\amasetupwebappendix")) end
  local head = pandoc.Blocks({ pandoc.Para(pandoc.Inlines("Web Appendix")) })
  if M.title then head:insert(pandoc.Para(M.title)) end
  out:extend(element("title", "Title", head))
  if not O.anonymous then out:extend(author_block()) end
  -- Table of contents with page numbers, if there are several sections
  local sections = 0
  for _, b in ipairs(doc.blocks) do
    if b.t == "Header" and b.level == 1 then sections = sections + 1 end
  end
  if O.toc and sections > 1 then
    if is_latex then
      out:insert(latex("\\amatableofcontents"))
    elseif is_docx then
      -- A Word field: Word fills in the entries and page numbers when the
      -- file is opened (or with "Update Field")
      out:insert(pandoc.RawBlock("openxml",
        '<w:p><w:pPr><w:pStyle w:val="FrontText"/></w:pPr>'
        .. '<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>'
        .. '<w:r><w:instrText xml:space="preserve"> TOC \\o "1-1" \\h \\z \\u </w:instrText></w:r>'
        .. '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        .. '<w:r><w:t>Table of contents: right-click and choose Update Field.</w:t></w:r>'
        .. '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'))
    end
  end
  out:extend(element("disclosure", "Front Text", { pandoc.Para(pandoc.Inlines(DISCLOSURE)) }))
  local br = page_break()
  if br then out:insert(br) end
  return out
end

-- File 2: the first page of the main document
function Journal.front(doc)
  if mode == "title-page" then return title_page() end
  if mode == "web-appendix" then return web_appendix_front(doc) end
  local out = pandoc.Blocks({})
  if not O.anonymous then
    -- Accepted manuscripts: the title page comes first
    out:extend(title_page())
    local br0 = page_break()
    if br0 then out:insert(br0) end
  end
  if M.title then out:extend(element("title", "Title", { pandoc.Para(M.title) })) end
  if M.pcs then
    -- JPP&M: the statement shares the first page with the title; the
    -- abstract follows on the next page, as in the journal's template
    out:extend(element("fronthead", "Abstract Title",
      { pandoc.Para(pandoc.Inlines("Policy Contribution Statement")) }))
    out:extend(element("abstract", "Abstract", M.pcs))
    local br1 = page_break()
    if br1 then out:insert(br1) end
  end
  if M.abstract_blocks then
    out:extend(element("fronthead", "Abstract Title", { pandoc.Para(pandoc.Inlines("Abstract")) }))
    out:extend(element("abstract", "Abstract", M.abstract_blocks))
  end
  if #M.keywords > 0 then
    out:extend(element("keywords", "Keywords",
      { para(pandoc.Emph(pandoc.Inlines("Keywords")), pandoc.Str(":"), pandoc.Space(),
          table.concat(M.keywords, ", ")) }))
  end
  local br = page_break()
  if br then out:insert(br) end
  return out
end

function Journal.body(blocks)
  if mode == "web-appendix" then
    -- Each section ("Web Appendix A: ...") begins on a new page
    return blocks:map(function(b)
      if b.t == "Header" and b.level == 1 and header_text_of(b):match("^Web Appendix")
         and not b.classes:includes("appendix") then
        b.classes:insert("appendix")
      end
      return b
    end)
  elseif mode == "title-page" then
    -- Text typed in the body of the title page file is set like the
    -- statements: single spaced, without indentation
    if is_latex and #blocks > 0 then
      local out = pandoc.Blocks({ latex("\\begin{amastatements}") })
      out:extend(blocks)
      out:insert(latex("\\end{amastatements}"))
      return out
    elseif is_docx then
      return blocks:map(function(b)
        if b.t == "Para" then return styled("Statement", { b }) end
        return b
      end)
    end
  end
  return blocks
end

-- References may be single spaced (PDF and .tex)
function Journal.references_open()
  if is_latex and O.reference_spacing == "single" then
    return latex("\\setstretch{1}\\setlength{\\parskip}{0.5\\baselineskip}")
  end
  return nil
end

-- =========================================================================
-- Shared code, continued
-- =========================================================================

-- Article layout (PDF and .tex only): title, authors, abstract, keywords,
-- and the author note as a footnote on the first page
local function article_front()
  local out = pandoc.Blocks({ latex("\\" .. ID .. "setuparticle") })
  if M.title then out:extend(element("arttitle", "Title", { pandoc.Plain(M.title) })) end
  local names = author_names(M.authors)
  if #names > 0 and not O.anonymous then
    local lines = pandoc.Blocks({})
    for _, n in ipairs(names) do lines:insert(pandoc.Para(pandoc.Inlines(n))) end
    out:extend(element("artauthors", "Author", lines))
  end
  if M.abstract_blocks then
    out:extend(element("artabstract", "Abstract", M.abstract_blocks))
  end
  if #M.keywords > 0 then
    out:extend(element("artkeywords", "Abstract",
      { para(pandoc.Strong(pandoc.Inlines("Keywords:")), pandoc.Space(), table.concat(M.keywords, ", ")) }))
  end
  out:insert(latex("\\" .. ID .. "artrule"))
  if M.author_note and not O.anonymous then
    out:insert(latex("\\" .. ID .. "authornote{" .. blocks_to_latex(M.author_note) .. "}"))
  end
  return out
end

-- -------------------------------------------------------------------------
-- Notes under tables and figures: a div with the class "notes"
-- -------------------------------------------------------------------------
local note_classes = { "notes", "note", "table-notes", "figure-notes", "table-note", "figure-note",
  ID .. "-note", ID .. "-notes", "jcr-note" }

local function is_note_div(el)
  for _, c in ipairs(note_classes) do
    if el.classes:includes(c) then return true end
  end
  return false
end

local function first_text(inlines)
  local first = inlines[1]
  if first == nil then return "" end
  if first.t == "Str" then return first.text end
  if (first.t == "Strong" or first.t == "Emph") and #first.content > 0 then
    return pandoc.utils.stringify(first)
  end
  return ""
end

local function has_note_label(inlines)
  local s = first_text(inlines):upper()
  return s:match("^NOTES?[%.:%-\u{2014}]") ~= nil or s:match("^NOTES?$") ~= nil
    or s:match("^SOURCES?[%.:]") ~= nil
end

local function note_label()
  local N = J.note
  local text = O.note_label or N.label
  local label
  -- A label given in the document is used as typed
  if O.note_label then
    return pandoc.Inlines({ pandoc.Str(text), pandoc.Space() })
  end
  if N.italic then label = pandoc.Inlines({ pandoc.Emph(pandoc.Inlines(text)) })
  else label = pandoc.Inlines(text) end
  if N.after and N.after ~= "" then label:insert(pandoc.Str(N.after)) end
  if N.dash then label:insert(pandoc.Str("\u{2014}")) else label:insert(pandoc.Space()) end
  return label
end

-- The label goes on the first paragraph that is not a lettered note
-- (a paragraph that begins with a superscript letter)
local function make_note(el)
  local blocks = el.content:clone()
  for i, b in ipairs(blocks) do
    if b.t == "Para" or b.t == "Plain" then
      local first = b.content[1]
      local lettered = first and first.t == "Superscript"
      if not lettered then
        if (O.note_label or (J.note and J.note.label and J.note.label ~= ""))
           and not has_note_label(b.content) then
          local inl = note_label()
          inl:extend(b.content)
          blocks[i] = pandoc.Para(inl)
        end
        break
      end
    end
  end
  local out
  if is_latex then
    out = pandoc.Blocks({ latex("\\begin{" .. ID .. "notes}") })
    out:extend(blocks)
    out:insert(latex("\\end{" .. ID .. "notes}"))
  elseif is_docx then
    out = pandoc.Blocks({ styled("Table Note", blocks) })
  else
    out = blocks
  end
  -- One block, so that a note can be moved together with its table or figure
  return pandoc.Div(out, pandoc.Attr("", { "mq-note" }))
end

-- -------------------------------------------------------------------------
-- Hypotheses: the words up to the first colon ("H1:") are set in bold,
-- unless the label is already marked up
-- -------------------------------------------------------------------------
local function bold_hypothesis_label(blocks)
  local first = blocks[1]
  if first == nil or (first.t ~= "Para" and first.t ~= "Plain") then return blocks end
  local inl = first.content
  if #inl == 0 or inl[1].t == "Strong" then return blocks end
  for i = 1, math.min(#inl, 4) do
    local x = inl[i]
    if x.t == "Str" and x.text:sub(-1) == ":" then
      local label = pandoc.Inlines({})
      for j = 1, i do label:insert(inl[j]) end
      local out = pandoc.Inlines({ pandoc.Strong(label) })
      for j = i + 1, #inl do out:insert(inl[j]) end
      first.content = out
      blocks[1] = first
      return blocks
    end
  end
  return blocks
end

-- -------------------------------------------------------------------------
-- Element filters
-- -------------------------------------------------------------------------
function Note(el)
  footnote_count = footnote_count + 1
  local L = J.limits or {}
  if L.footnotes and footnote_count == L.footnotes + 1 then
    log_warning(J.label .. ": " .. (L.footnotes_text or ("no more than " .. L.footnotes .. " footnotes")) .. ".")
  end
  if L.footnote_words then
    -- (stringify skips footnotes, so the note's blocks are passed)
    local wc = count_words(pandoc.utils.stringify(el.content))
    if wc > L.footnote_words then
      log_warning(J.label .. ": a footnote should not exceed " .. L.footnote_words .. " words. Footnote "
        .. footnote_count .. " has about " .. wc .. ".")
    end
  end
  return el
end

function Div(el)
  if is_note_div(el) then
    -- false: do not process the note's paragraphs again
    return make_note(el), false
  end
  if el.classes:includes("hypothesis") then
    local content = bold_hypothesis_label(el.content:clone())
    if is_latex then
      local blocks = pandoc.Blocks({ latex("\\begin{" .. ID .. "hypothesis}") })
      blocks:extend(content)
      blocks:insert(latex("\\end{" .. ID .. "hypothesis}"))
      return blocks
    elseif is_docx then
      return styled("Hypothesis", content)
    end
    el.content = content
    return el
  end
  -- Centered and unindented text
  if el.classes:includes("center") then
    if is_latex then
      local blocks = pandoc.Blocks({ latex("\\begin{" .. ID .. "centered}") })
      blocks:extend(el.content)
      blocks:insert(latex("\\end{" .. ID .. "centered}"))
      return blocks
    elseif is_docx then
      return styled("Centered", el.content)
    end
  end
  if el.classes:includes("noindent") or el.classes:includes("flushleft") then
    if is_latex then
      local blocks = pandoc.Blocks({ latex("\\begin{" .. ID .. "flush}") })
      blocks:extend(el.content)
      blocks:insert(latex("\\end{" .. ID .. "flush}"))
      return blocks
    elseif is_docx then
      return styled("Front Text", el.content)
    end
  end
  if Journal.div then return Journal.div(el) end
  return el
end

-- Images that stand alone in a paragraph of the text are centered. Images
-- inside a numbered figure or table, or inside a panel (layout-ncol and the
-- like), are placed by Quarto: they are marked first and left alone.
local function is_custom_float(b)
  return b.t == "Div" and b.attributes["__quarto_custom_type"] == "FloatRefTarget"
end

local function placed_by_quarto(div)
  local a = div.attributes
  return a["__quarto_custom_type"] ~= nil or a["layout-ncol"] ~= nil
    or a["layout-nrow"] ~= nil or a["layout"] ~= nil
end

-- Word: Quarto separates two tables or figures that follow each other with
-- an empty paragraph, also inside a figure with panels, where the paragraph
-- becomes an empty panel and the panels end up below each other. Each panel
-- goes into a block of its own, the way the plots of a code chunk arrive.
local function separate_panels(float)
  local changed = false
  for i, slot in ipairs(float.content) do
    if slot.t == "Div" and slot.attributes["__quarto_custom_scaffold"] then
      local n = 0
      for _, b in ipairs(slot.content) do if is_custom_float(b) then n = n + 1 end end
      if n >= 2 then
        slot.content = slot.content:map(function(b)
          if is_custom_float(b) then
            return pandoc.Div({ b }, pandoc.Attr("", { "cell-output-display" }))
          end
          return b
        end)
        float.content[i] = slot
        changed = true
      end
    end
  end
  return changed
end

local function prepare_floats(doc)
  if not (is_latex or is_docx) then return nil end
  return doc:walk({
    Div = function(div)
      local changed = false
      if is_docx and is_custom_float(div) then changed = separate_panels(div) end
      if is_latex and placed_by_quarto(div) then
        div = div:walk({
          Image = function(img) img.attributes["mq-placed"] = "1"; return img end,
        })
        changed = true
      end
      if changed then return div end
      return nil
    end,
  })
end

function Para(el)
  if #el.content == 1 and el.content[1].t == "Image" and is_latex
     and not el.content[1].attributes["mq-placed"] then
    return pandoc.Blocks({ latex("\\begin{center}"), el, latex("\\end{center}") })
  end
  return el
end

local function clear_marks(doc)
  if not is_latex then return nil end
  return doc:walk({
    Image = function(img)
      if img.attributes["mq-placed"] then
        img.attributes["mq-placed"] = nil
        return img
      end
      return nil
    end,
  })
end

-- Quarto's nodes for cross-referenced tables and figures
local function collect_float(float, node)
  if node and node.attributes then
    local cid = node.attributes["__quarto_custom_id"]
    if cid then
      floats_by_cid[cid] = { id = float.identifier, type = float.type, caption = float.caption_long }
    end
  end
  return nil
end

-- =========================================================================
-- Document-level passes
-- =========================================================================
local function header_text(b) return pandoc.utils.stringify(b.content) end

local function is_refs_header(b)
  if b.t ~= "Header" or b.level ~= 1 then return false end
  local s = header_text(b):lower()
  return b.identifier == "references" or b.classes:includes("references")
    or s == "references" or s == "reference list"
end

local function is_refs_div(b) return b.t == "Div" and b.identifier == "refs" end

local function is_appendix(b)
  return b.t == "Header" and b.level == 1 and b.classes:includes("appendix")
end

-- The letter of an appendix heading: "Appendix B: Title" gives "B"
local function appendix_letter(b)
  local s = header_text(b)
  local letter = s:match("[Aa][Pp][Pp][Ee][Nn][Dd][Ii][Xx]%s+(%u)%f[%A]")
  return letter
end

-- The outermost cross-referenced table or figure inside a block, if any
local function find_float(block)
  local found = nil
  local function visit(b)
    if found ~= nil then return end
    if b.t == "Div" then
      if b.attributes["__quarto_custom_type"] == "FloatRefTarget" then
        local rec = floats_by_cid[b.attributes["__quarto_custom_id"]]
        if rec == nil and has_quarto then
          local ok, data = pcall(function() return quarto._quarto.ast.resolve_custom_data(b) end)
          if ok and data then
            rec = { id = data.identifier, type = data.type, caption = data.caption_long }
          end
        end
        found = rec or false
        return
      end
      for _, c in ipairs(b.content) do visit(c) end
    end
  end
  visit(block)
  return found or nil
end

local function is_note_block(b) return b.t == "Div" and b.classes:includes("mq-note") end

-- Headings that Word cannot set in the same paragraph as the text become a
-- run-in phrase at the start of the next paragraph
local function runin_headings(blocks)
  local R = J.runin
  if not R then return blocks end
  local out = pandoc.Blocks({})
  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    local nxt = blocks[i + 1]
    local spec = (b.t == "Header") and R[b.level] or nil
    if spec and nxt and nxt.t == "Para" then
      local head = b.content:clone()
      -- Section numbers are not available yet; run-in headings are unnumbered
      if spec.period then
        local last = head[#head]
        if not (last and last.t == "Str" and last.text:match("[%.%?!:]$")) then
          head:insert(pandoc.Str("."))
        end
      end
      local lead
      if spec.bold and spec.italic then lead = pandoc.Strong({ pandoc.Emph(head) })
      elseif spec.bold then lead = pandoc.Strong(head)
      elseif spec.italic then lead = pandoc.Emph(head)
      else lead = pandoc.Span(head) end
      local inl = pandoc.Inlines({ lead, pandoc.Space() })
      inl:extend(nxt.content)
      local p = pandoc.Para(inl)
      if spec.indent == false then out:insert(styled("Run-in Paragraph", { p }))
      else out:insert(p) end
      i = i + 2
    else
      out:insert(b)
      i = i + 1
    end
  end
  return out
end

local function check_headings(blocks)
  local L = J.limits or {}
  local section, sub = nil, nil
  local n2, n3 = 0, 0
  local warned_level = false
  local function flush3()
    if J.check_single_tertiary and sub and n3 == 1 then
      log_warning(J.label .. ": subsection \"" .. sub .. "\" has a single tertiary heading; use none or at least two.")
    end
  end
  local function flush2()
    if J.check_single_secondary and section and n2 == 1 then
      log_warning(J.label .. ": section \"" .. section .. "\" has a single secondary heading; use none or at least two.")
    end
  end
  local first_h1 = true
  for _, b in ipairs(blocks) do
    if b.t == "Header" then
      if b.level == 1 then
        flush3(); flush2()
        section = header_text(b); sub = nil; n2 = 0; n3 = 0
        if first_h1 then
          first_h1 = false
          if J.warn_introduction and section:lower() == "introduction" then
            log_warning(J.label .. ": " .. J.warn_introduction)
          end
        end
      elseif b.level == 2 then
        flush3()
        sub = header_text(b); n2 = n2 + 1; n3 = 0
      elseif b.level == 3 then
        n3 = n3 + 1
      end
      if L.heading_levels and b.level > L.heading_levels and not warned_level then
        warned_level = true
        log_warning(J.label .. ": use no more than " .. L.heading_levels .. " levels of headings.")
      end
    end
  end
  flush3(); flush2()
end

-- A table or a picture that has a title but no label is not numbered, in
-- either output, and cannot be cited; the author most likely forgot the label
local function check_unlabeled(blocks)
  local tables, figures = 0, 0
  local ok = pcall(function()
    pandoc.Blocks(blocks):walk({
      traverse = "topdown",
      Div = function(d)
        -- (the parts of a labeled table or figure may have captions of their own)
        if d.attributes["__quarto_custom_type"] ~= nil or d.attributes["layout-ncol"] ~= nil
           or d.attributes["layout-nrow"] ~= nil or d.attributes["layout"] ~= nil then
          return d, false
        end
        return nil
      end,
      Table = function(t)
        if t.caption and t.caption.long and pandoc.utils.stringify(t.caption.long) ~= "" then
          tables = tables + 1
        end
        return nil
      end,
      Figure = function(f)
        if f.caption and f.caption.long and pandoc.utils.stringify(f.caption.long) ~= "" then
          figures = figures + 1
        end
        return nil
      end,
    })
  end)
  if not ok then return end
  if tables > 0 then
    log_warning(J.label .. ": " .. tables .. (tables == 1 and " table has" or " tables have")
      .. " a title but no label, so " .. (tables == 1 and "it is" or "they are")
      .. " not numbered. Give it a label: {#tbl-results} after the title, or \"#| label: tbl-results\" in a code chunk.")
  end
  if figures > 0 then
    log_warning(J.label .. ": " .. figures .. (figures == 1 and " figure has" or " figures have")
      .. " a caption but no label, so " .. (figures == 1 and "it is" or "they are")
      .. " not numbered. Give it a label: {#fig-results} after the image, or \"#| label: fig-results\" in a code chunk.")
  end
end

-- Words in the text, without tables, figures, their notes, and code.
-- Footnotes are counted when with_footnotes is set (stringify skips them).
local function count_body_words(blocks, with_footnotes)
  local n = 0
  local function visit(list)
    for _, b in ipairs(list) do
      if b.t == "Para" or b.t == "Plain" or b.t == "Header" then
        n = n + count_words(pandoc.utils.stringify(b))
        if with_footnotes then
          b:walk({ Note = function(note)
            for _, nb in ipairs(note.content) do n = n + count_words(pandoc.utils.stringify(nb)) end
          end })
        end
      elseif b.t == "Div" then
        local skip = is_note_block(b) or b.attributes["__quarto_custom_type"] == "FloatRefTarget"
          or b.classes:includes("cell") or b.identifier == "refs"
        if not skip then visit(b.content) end
      elseif b.t == "BlockQuote" then
        visit(b.content)
      elseif b.t == "BulletList" or b.t == "OrderedList" then
        for _, item in ipairs(b.content) do visit(item) end
      end
    end
  end
  visit(blocks)
  return n
end

-- Every word of the manuscript: the text with its footnotes, tables,
-- captions, and notes (for journals whose limit is "all inclusive")
local function count_all_words(blocks)
  local n = 0
  local function add(el)
    -- (the alternative text of a picture repeats its caption)
    if #el.content == 1 and el.content[1].t == "Image" then return nil end
    n = n + count_words(pandoc.utils.stringify(el))
    return nil
  end
  blocks:walk({ Para = add, Plain = add, Header = add })
  return n
end

-- Cross-references ("@fig-x") look like citations until Quarto resolves them
local crossref_prefixes = { fig = true, tbl = true, eq = true, sec = true, lst = true, thm = true,
  lem = true, cor = true, prp = true, cnj = true, def = true, exm = true, exr = true, sol = true,
  rem = true, alg = true }

local function is_crossref_id(id)
  local prefix = id:lower():match("^(%a+)%-")
  return prefix ~= nil and crossref_prefixes[prefix] == true
end

local function is_crossref_cite(cite)
  for _, c in ipairs(cite.citations) do
    if not is_crossref_id(c.id) then return false end
  end
  return true
end

local function count_reference_words(doc)
  if not O.has_bibliography then return 0 end
  local ok, cited = pcall(function()
    local blocks = doc.blocks:walk({
      Cite = function(c)
        local keep = c.citations:filter(function(x) return not is_crossref_id(x.id) end)
        if #keep == 0 then return pandoc.Str("") end
        if #keep < #c.citations then c.citations = keep; return c end
      end,
    })
    return pandoc.utils.citeproc(pandoc.Pandoc(blocks, doc.meta))
  end)
  if not ok or cited == nil then return nil end
  -- (entry by entry: stringify joins the last word of one entry to the first
  -- word of the next)
  local n = 0
  local function add(el) n = n + count_words(pandoc.utils.stringify(el)) end
  cited:walk({
    Div = function(d)
      if d.identifier == "refs" then d:walk({ Para = add, Plain = add }) end
    end,
  })
  return n
end

-- Figures as separate files: a copy of each figure's image file, named
-- Figure_1, Figure_2, ... (Figure_A1 in Appendix A; Figure_3a and Figure_3b
-- for a figure with two images), in the folder "<document>-figures" next to
-- the document. The type of file is that of the output being rendered: the
-- PDF and .tex outputs use the vector versions of figures drawn by code.
local function copy_file(source, target)
  local fh = io.open(source, "rb")
  if not fh then return false end
  local data = fh:read("a")
  fh:close()
  local out = io.open(target, "wb")
  if not out then return false end
  out:write(data)
  out:close()
  return true
end

local function export_figures(blocks, fixed_prefix)
  local input = has_quarto and quarto.doc and quarto.doc.input_file or nil
  if not input then return end
  local A = J.appendix or {}
  local base = pandoc.path.directory(input)
  local stem = pandoc.path.split_extension(pandoc.path.filename(input))
  local folder = stem .. "-figures"
  local dir = pandoc.path.join({ base, folder })
  local written, skipped = {}, {}
  local count, prefix = 0, fixed_prefix
  local made = false
  local function export(block)
    count = count + 1
    local label = (prefix or "") .. count
    local sources = {}
    pandoc.Blocks({ block }):walk({ Image = function(img) sources[#sources + 1] = img.src end })
    for k, src in ipairs(sources) do
      if src:match("^%a[%w+.-]*://") or src:match("^data:") then
        skipped[#skipped + 1] = src
      else
        local path = src:gsub("%%20", " ")
        if not pandoc.path.is_absolute(path) then path = pandoc.path.join({ base, path }) end
        local _, ext = pandoc.path.split_extension(path)
        local name = "Figure_" .. label .. ((#sources > 1) and string.char(96 + k) or "") .. ext:lower()
        local target = pandoc.path.join({ dir, name })
        if pandoc.path.normalize(path) ~= pandoc.path.normalize(target) then
          if not made then pcall(pandoc.system.make_directory, dir, true); made = true end
          if copy_file(path, target) then written[#written + 1] = name
          else skipped[#skipped + 1] = src end
        end
      end
    end
  end
  local function visit(b)
    if b.t == "Header" then
      if b.level == 1 and b.classes:includes("appendix") and not fixed_prefix and A.numbering
         and A.prefix_floats ~= false then
        local s = pandoc.utils.stringify(b.content)
        prefix = s:match("[Aa][Pp][Pp][Ee][Nn][Dd][Ii][Xx]%s+(%u)%f[%A]") or A.single_letter
        count = 0
      end
    elseif b.t == "Div" then
      if b.attributes["__quarto_custom_type"] == "FloatRefTarget" then
        local rec = floats_by_cid[b.attributes["__quarto_custom_id"]]
        if rec == nil and has_quarto then
          local ok, data = pcall(function() return quarto._quarto.ast.resolve_custom_data(b) end)
          if ok and data then rec = { id = data.identifier, type = data.type } end
        end
        if rec and rec.type == "Figure" then export(b) end
        return
      end
      for _, c in ipairs(b.content) do visit(c) end
    end
  end
  for _, b in ipairs(blocks) do visit(b) end
  if #written > 0 then
    log_info(J.label .. ": wrote " .. #written .. " figure file" .. (#written == 1 and "" or "s") .. " to "
      .. folder .. "/ (" .. table.concat(written, ", ") .. ")")
  end
  if #skipped > 0 then
    log_warning(J.label .. ": could not copy " .. table.concat(skipped, ", ") .. " to " .. folder .. "/")
  end
end

-- A paragraph that tells where a table or figure belongs
local function float_callout(rec)
  local id = rec.id
  -- A capitalized identifier asks Quarto for a capitalized label ("Table 1")
  local cap_id = id:sub(1, 1):upper() .. id:sub(2)
  local cite = pandoc.Cite(pandoc.Inlines({ pandoc.Str("@" .. cap_id) }),
    { pandoc.Citation(cap_id, "AuthorInText") })
  local before, after = (J.floats.callout or "[Insert %s about here]"):match("^(.-)%s*%%s%s*(.*)$")
  local inl = pandoc.Inlines({})
  if before ~= "" then
    inl:extend(pandoc.Inlines(before)); inl:insert(pandoc.Space())
  end
  inl:insert(cite)
  if after ~= "" then
    inl:insert(pandoc.Space()); inl:extend(pandoc.Inlines(after))
  end
  local out = element("callout", "Float Callout", { pandoc.Para(inl) })
  return pandoc.Div(out, pandoc.Attr("", { "mq-callout" }))
end

-- Counters for the tables, figures, and equations of an appendix
local function counters_latex(prefix, fsep, esep, floats, equations)
  local lines = {}
  -- (\theH...: the name of the link target in the PDF, which must differ from
  -- that of "Table 1" in the text)
  local function counter(name, sep)
    local number = prefix .. sep .. "\\arabic{" .. name .. "}"
    table.insert(lines, "\\setcounter{" .. name .. "}{0}\\renewcommand{\\the" .. name .. "}{" .. number .. "}"
      .. "\\providecommand{\\theH" .. name .. "}{}\\renewcommand{\\theH" .. name .. "}{" .. number .. "}")
  end
  if floats ~= false then counter("table", fsep); counter("figure", fsep) end
  if equations ~= false then counter("equation", esep) end
  return table.concat(lines, "%\n")
end

-- The numbering of the text again, for tables and figures that are printed
-- after an appendix (those moved to the end of the manuscript)
local function main_counters_latex(tables, figures)
  local lines = {}
  for name, value in pairs({ table = tables, figure = figures }) do
    local number = "\\arabic{" .. name .. "}"
    table.insert(lines, "\\setcounter{" .. name .. "}{" .. value .. "}\\renewcommand{\\the" .. name .. "}{"
      .. number .. "}\\providecommand{\\theH" .. name .. "}{}\\renewcommand{\\theH" .. name .. "}{"
      .. number .. "}")
  end
  table.sort(lines)
  return table.concat(lines, "%\n")
end

-- APA style writes "and" between two authors named in the sentence, "Bagozzi
-- and Yi (1988)", and "&" inside parentheses. A CSL style cannot tell the two
-- apart and prints "&" in both places, so a citation in the sentence
-- (@bagozzi1988) to a work by two authors is rewritten as the two names and
-- a citation without the authors.
local function narrative_citations(doc)
  local ok, refs = pcall(pandoc.utils.references, doc)
  if not ok or refs == nil then return doc end
  local by_id = {}
  for _, r in ipairs(refs) do by_id[r.id] = r end
  local function family(n)
    if n.literal then return stringify(n.literal) end
    local name = stringify(n.family)
    local particle = n["non-dropping-particle"] and stringify(n["non-dropping-particle"]) or ""
    if particle ~= "" then name = particle .. " " .. name end
    return name
  end
  -- APA also adds the initials of a first author who shares a surname with
  -- the first author of another work, "(J. A. Smith & Jones, 2020)". The
  -- style file does that inside the parentheses, and the names written here
  -- follow the same rule: the initials when they tell the two authors
  -- apart; when they do not, nothing (7th edition) or the given name as
  -- the entry has it (6th edition).
  local function initials(given)
    local out = ""
    for part, sep in given:gmatch("([^%s%.%-]+)([%s%.%-]*)") do
      local letter = pandoc.text.sub(part, 1, 1)
      if letter and letter ~= "" then
        out = out .. letter .. "."
        if sep:find("-", 1, true) then out = out .. "-" else out = out .. " " end
      end
    end
    return (out:gsub("[%s%-]+$", ""))
  end
  local function given_name(n)
    return n.given and stringify(n.given) or ""
  end
  local first_authors = {}   -- surname -> { [given name] = initials }
  for _, r in ipairs(refs) do
    local n = r.author and r.author[1]
    if n and not n.literal then
      local key = family(n)
      first_authors[key] = first_authors[key] or {}
      first_authors[key][given_name(n)] = initials(given_name(n))
    end
  end
  local function name_prefix(n)
    if n.literal then return "" end
    local given = given_name(n)
    if given == "" then return "" end
    local mine = initials(given)
    local others, tie = 0, false
    for g, i in pairs(first_authors[family(n)] or {}) do
      if g ~= given then
        others = others + 1
        if i == mine then tie = true end
      end
    end
    if others == 0 then return "" end
    if not tie then return mine end
    if O.apa6 then return given end
    return ""
  end
  local function rewrite(c)
    local first = c.citations[1]
    if first == nil or first.mode ~= "AuthorInText" then return nil end
    local r = by_id[first.id]
    if r == nil or r.author == nil or #r.author ~= 2 then return nil end
    local a, b = family(r.author[1]), family(r.author[2])
    if a == "" or b == "" then return nil end
    local prefix = name_prefix(r.author[1])
    if prefix ~= "" then
      -- (a particle that the short form drops returns with the initials:
      -- "J. de Vries")
      local dropped = r.author[1]["dropping-particle"]
      dropped = dropped and stringify(dropped) or ""
      a = prefix .. " " .. (dropped ~= "" and (dropped .. " ") or "") .. a
    end
    local citations = c.citations
    first.mode = "SuppressAuthor"
    citations[1] = first
    c.citations = citations
    local out = pandoc.Inlines(a .. " and " .. b)
    out:insert(pandoc.Space())
    out:insert(c)
    return out
  end
  doc.blocks = doc.blocks:walk({ Cite = rewrite })
  return doc
end

function Pandoc(doc)
  if O.narrative_and and O.has_bibliography then doc = narrative_citations(doc) end
  local body = doc.blocks
  local A = J.appendix or {}
  local manuscript = (mode == "manuscript")
  -- Modes that print front matter only (a title page, for example)
  local front_only = (J.front_modes or { ["title-page"] = true })[mode] == true
  -- A prefix for every number in the document (the "W" of a web appendix)
  local fixed_prefix = Journal.fixed_prefix and Journal.fixed_prefix() or nil

  if manuscript or mode == "article" then check_headings(body) end
  if is_latex or is_docx then check_unlabeled(body) end
  if manuscript and O.figures ~= "embedded" and not O.article and (is_latex or is_docx) then
    export_figures(body, fixed_prefix)
  end
  if Journal.check_body then Journal.check_body(body, doc) end
  if mode == "highlights" then check_highlights_body(body) end

  -- ---- Word count (journals with a word limit) ----
  local W = Journal.word_limit and Journal.word_limit() or nil
  -- (W.modes: other files with a limit, an online appendix for example)
  if W and (manuscript or (W.modes and W.modes[mode])) and (is_latex or is_docx) then
    local counted = body
    if W.stop_at_appendix then
      counted = pandoc.Blocks({})
      for _, b in ipairs(body) do
        if is_appendix(b) then break end
        counted:insert(b)
      end
    end
    local text = W.everything and count_all_words(counted) or count_body_words(counted, W.footnotes)
    local total = text
    local parts = { (W.everything and "text, tables, and notes " or "text ") .. text }
    if W.abstract then
      local n = count_words(M.abstract_plain)
      total = total + n
      table.insert(parts, "abstract " .. n)
    end
    if W.references then
      local refs = count_reference_words(doc)
      if refs then
        total = total + refs
        table.insert(parts, "references " .. refs)
      end
    end
    local msg = J.label .. ": about " .. total .. " words (" .. table.concat(parts, ", ") .. "); "
      .. (W.limit_text or ("the limit is " .. W.max)) .. ". " .. (W.what or "")
    local over = total > W.max
    if W.less_than then over = total >= W.max end
    -- (W.soft: a guide, not a limit; the count is reported without a warning)
    if over and not W.soft then log_warning(msg) else log_info(msg) end
  end

  -- ---- Footnotes collected at the end (optional) ----
  local endnotes = pandoc.Blocks({})
  if O.footnotes == "end" and manuscript then
    local n = 0
    body = body:walk({
      Note = function(note)
        n = n + 1
        local blocks = note.content:clone()
        local mark = pandoc.Superscript(pandoc.Inlines(tostring(n)))
        if blocks[1] and (blocks[1].t == "Para" or blocks[1].t == "Plain") then
          local inl = pandoc.Inlines({ mark })
          inl:extend(blocks[1].content)
          blocks[1] = pandoc.Para(inl)
        else
          blocks:insert(1, pandoc.Para({ mark }))
        end
        endnotes:extend(blocks)
        return pandoc.Superscript(pandoc.Inlines(tostring(n)))
      end,
    })
  end

  if is_docx then
    body = runin_headings(body)
  elseif is_latex and (J.runin or J.runin_latex) and not O.article then
    -- The LaTeX heading format adds the period; a typed one is removed
    local R = J.runin or J.runin_latex
    body = body:map(function(b)
      local spec = (b.t == "Header") and R[b.level] or nil
      if spec and spec.period then
        local content = b.content
        local last = content[#content]
        if last and last.t == "Str" and last.text:match("[^%.]%.$") then
          content[#content] = pandoc.Str(last.text:sub(1, -2))
          b.content = content
        end
      end
      return b
    end)
  end
  if Journal.body then body = Journal.body(body) end

  -- ---- Tables and figures moved to the end (optional) ----
  local moved = { Table = pandoc.Blocks({}), Figure = pandoc.Blocks({}) }
  local moved_records = { Table = {}, Figure = {} }
  if O.floats == "end" and manuscript then
    local kept = pandoc.Blocks({})
    local i = 1
    local in_back = false   -- in the reference list or in an appendix
    while i <= #body do
      local b = body[i]
      if is_refs_header(b) or is_refs_div(b) or is_appendix(b) then in_back = true end
      local rec = (not in_back) and b.t == "Div" and find_float(b) or nil
      if rec and (rec.type == "Table" or rec.type == "Figure") and rec.id and rec.id ~= "" then
        local group = pandoc.Blocks({ b })
        while body[i + 1] and is_note_block(body[i + 1]) do
          group:insert(body[i + 1]); i = i + 1
        end
        local br = page_break()
        local captions_only = (rec.type == "Figure" and O.figures == "separate")
        if br and not captions_only then moved[rec.type]:insert(br) end
        moved[rec.type]:extend(group)
        table.insert(moved_records[rec.type], rec)
        kept:insert(float_callout(rec))
      else
        kept:insert(b)
      end
      i = i + 1
    end
    body = kept
  end

  -- ---- A reference list where the document has none ----
  -- Without citations there is nothing to list, and an empty list stops
  -- LaTeX: the heading and the list are left out
  local has_citations = O.has_nocite
  if not has_citations then
    local function look(blocks)
      if blocks == nil then return end
      blocks:walk({
        Cite = function(c) if not is_crossref_cite(c) then has_citations = true end end,
      })
    end
    look(doc.blocks)
    look(M.abstract_blocks)
  end
  if not has_citations then
    body = body:filter(function(b) return not (is_refs_div(b) or is_refs_header(b)) end)
  end
  local has_refs_div = false
  for _, b in ipairs(body) do if is_refs_div(b) then has_refs_div = true end end
  if not has_refs_div and O.has_bibliography and not front_only and has_citations then
    local refs = pandoc.Blocks({})
    local has_header = false
    for _, b in ipairs(body) do if is_refs_header(b) then has_header = true end end
    if not has_header then
      refs:insert(pandoc.Header(1, pandoc.Inlines(J.refs_heading or "References"),
        pandoc.Attr("references", { "unnumbered" })))
    end
    refs:insert(pandoc.Div({}, pandoc.Attr("refs")))
    local at = nil
    if has_header then
      for i, b in ipairs(body) do if is_refs_header(b) then at = i + 1; break end end
    elseif A.position == "after-references" then
      for i, b in ipairs(body) do if is_appendix(b) then at = i; break end end
    end
    if at and at <= #body then
      local nb = pandoc.Blocks({})
      for i, b in ipairs(body) do
        if i == at then nb:extend(refs) end
        nb:insert(b)
      end
      body = nb
    else
      body:extend(refs)
    end
  end

  -- ---- References, appendixes, and what belongs around them ----
  local out = pandoc.Blocks({})
  local seen_refs, seen_appendix = false, false
  local appendix_before_refs, appendix_after_refs = false, false
  -- Tables and figures moved to the end keep the numbers of the text, also
  -- when an appendix is printed before them
  local n_moved = { Table = #moved_records.Table, Figure = #moved_records.Figure }
  local appendix_before_moved, continued = false, false
  local appendix_floats = { Table = 0, Figure = 0 }
  local function moved_pending() return #moved.Table + #moved.Figure > 0 end
  -- True while the last blocks written are tables and figures moved to the
  -- end: each is on a page of its own, so a section that follows them
  -- begins on a new page
  local after_floats = false
  local statements_done = false
  local function statements()
    -- What the journal prints before the references (or the appendixes)
    if not statements_done and Journal.before_references and manuscript then
      local blocks = Journal.before_references()
      if blocks then out:extend(blocks) end
    end
    statements_done = true
  end
  local function break_page()
    if not O.article then
      local br = page_break()
      if br then out:insert(br) end
    end
  end
  local function after_references()
    if #endnotes > 0 then
      break_page()
      out:insert(pandoc.Header(1, pandoc.Inlines((J.footnotes and J.footnotes.heading) or "Footnotes"),
        pandoc.Attr("footnotes", { "unnumbered" })))
      out:extend(endnotes)
      endnotes = pandoc.Blocks({})
    end
    local numbered_again = false
    if moved_pending() and appendix_before_moved and is_latex and not fixed_prefix then
      out:insert(latex(main_counters_latex(0, 0)))
      numbered_again = true
    end
    for _, kind in ipairs((J.floats and J.floats.order) or { "Table", "Figure" }) do
      if #moved[kind] > 0 and Journal.before_moved then
        -- (a page of figure captions, for example)
        local extra = Journal.before_moved(kind, moved_records[kind])
        if extra and #extra > 0 then
          break_page()
          out:extend(extra)
        end
      end
      if kind == "Figure" and O.figures == "separate" and #moved[kind] > 0 then
        break_page()
        out:insert(pandoc.Header(1, pandoc.Inlines("Figure captions"),
          pandoc.Attr("figure-captions", { "unnumbered" })))
      end
      if #moved[kind] > 0 then after_floats = true end
      out:extend(moved[kind]); moved[kind] = pandoc.Blocks({})
    end
    -- (numbers that continue through the appendixes go on from the highest one)
    if numbered_again and continued then
      out:insert(latex("\\setcounter{table}{" .. (n_moved.Table + appendix_floats.Table) .. "}"
        .. "\\setcounter{figure}{" .. (n_moved.Figure + appendix_floats.Figure) .. "}"))
    end
  end

  -- Journals with numbered sections: the headings inside an appendix do not
  -- continue the numbers of the text ("1.2" after section 1). They are
  -- numbered after the appendix (A.1, A.1.1), or carry no number where
  -- appendixes have no letters.
  local appendix_now, appendix_counts = nil, {}
  local function appendix_subheading(b)
    if b.classes:includes("unnumbered") then return b end
    b.classes:insert("unnumbered")
    local letter = (appendix_now ~= true) and appendix_now or nil
    if letter and A.subsections ~= "none" then
      local level = b.level
      appendix_counts[level] = (appendix_counts[level] or 0) + 1
      for k = level + 1, 6 do appendix_counts[k] = nil end
      local parts = { letter }
      for k = 2, level do parts[#parts + 1] = tostring(appendix_counts[k] or 1) end
      local content = pandoc.Inlines({
        pandoc.Str(table.concat(parts, ".") .. (J.heading_number_period and "." or "")), pandoc.Space() })
      content:extend(b.content)
      b.content = content
    end
    return b
  end

  for _, b in ipairs(body) do
    if is_refs_header(b) then
      appendix_now = nil
      if not seen_refs then
        statements()
        if seen_appendix then appendix_before_refs = true end
        if J.refs_page_break ~= false then break_page() end
        seen_refs = true
      end
      if not b.classes:includes("unnumbered") then b.classes:insert("unnumbered") end
      out:insert(b)
    elseif is_refs_div(b) then
      if not seen_refs then
        statements()
        if seen_appendix then appendix_before_refs = true end
        if J.refs_page_break ~= false then break_page() end
        seen_refs = true
      end
      if is_latex then out:insert(latex("\\begin{" .. ID .. "references}")) end
      local opening = Journal.references_open and Journal.references_open() or nil
      if opening then out:insert(opening) end
      out:insert(b)
      if is_latex then out:insert(latex("\\end{" .. ID .. "references}")) end
      after_references()
    elseif is_appendix(b) then
      if A.position ~= "after-references" and J.statements_before ~= "references" then statements() end
      if seen_refs then appendix_after_refs = true end
      seen_appendix = true
      -- (no break when the document begins with the appendix)
      if (A.page_break ~= false or after_floats) and #out > 0 then break_page() end
      after_floats = false
      if not b.classes:includes("unnumbered") then b.classes:insert("unnumbered") end
      -- Numbers of tables, figures, and equations restart in each appendix
      local letter = appendix_letter(b) or A.single_letter
      if letter and A.numbering and is_latex and not fixed_prefix then
        out:insert(latex(counters_latex(letter, A.float_sep or "", A.eq_sep or "",
          A.prefix_floats, A.prefix_equations)))
      end
      if moved_pending() then
        appendix_before_moved = true
        -- Without appendix letters, the numbers of an appendix follow those
        -- of the tables and figures that are printed after it
        local lettered = letter and A.numbering and A.prefix_floats ~= false
        if not lettered and not continued and not fixed_prefix then
          continued = true
          if is_latex then
            out:insert(latex("\\setcounter{table}{" .. n_moved.Table .. "}\\setcounter{figure}{"
              .. n_moved.Figure .. "}"))
          end
        end
      end
      appendix_now = (A.numbering and letter) or true
      appendix_counts = {}
      if Journal.appendix_header then b = Journal.appendix_header(b) end
      out:insert(b)
    else
      if b.t == "Header" then
        if b.level == 1 then
          appendix_now = nil
          if after_floats then break_page() end
        elseif appendix_now and J.number_sections and not O.article then
          b = appendix_subheading(b)
        end
        after_floats = false
      elseif b.t == "Para" or b.t == "Div" or b.t == "Table" or b.t == "BulletList"
             or b.t == "OrderedList" or b.t == "BlockQuote" then
        after_floats = false
      end
      if seen_appendix and moved_pending() and b.t == "Div" then
        local rec = find_float(b)
        if rec and appendix_floats[rec.type] ~= nil then
          appendix_floats[rec.type] = appendix_floats[rec.type] + 1
        end
      end
      out:insert(b)
    end
  end
  statements()
  after_references()

  if manuscript then
    if A.position == "after-references" and appendix_before_refs then
      log_warning(J.label .. ": appendixes follow the references; move the appendix after the reference list.")
    elseif A.position == "before-references" and appendix_after_refs then
      log_warning(J.label .. ": appendixes come before the references; move the appendix before the reference list.")
    elseif A.position == "none" and seen_appendix and A.none_text then
      log_warning(J.label .. ": " .. A.none_text)
    end
  end

  -- ---- Numbers with a prefix in Word (appendix letters, "W") ----
  -- LaTeX numbers by itself; for Word, the post-render filter rewrites the
  -- numbers from this list (label of the table, figure, or equation: number)
  local has_moved = (n_moved.Table + n_moved.Figure) > 0
  if is_docx and (A.numbering or fixed_prefix or has_moved) then
    local map = {}
    local current = fixed_prefix
    local fsep = fixed_prefix and "" or (A.float_sep or "")
    local esep = fixed_prefix and "" or (A.eq_sep or "")
    local counts = { Table = 0, Figure = 0, Equation = 0 }
    -- Tables and figures moved to the end keep the numbers of the text;
    -- Quarto would number them after those of an appendix printed earlier
    local moved_number = {}
    for _, records in pairs(moved_records) do
      for k, rec in ipairs(records) do moved_number[rec.id] = k end
    end
    local in_appendix = false
    local after = { Table = 0, Figure = 0 }
    local function scan_equations(b)
      -- Quarto has not read "{#eq-label}" yet: it follows the display math
      pandoc.Blocks({ b }):walk({
        Para = function(p)
          for k, x in ipairs(p.content) do
            if x.t == "Math" and x.mathtype == "DisplayMath" then
              local rest = ""
              for m = k + 1, math.min(#p.content, k + 3) do
                rest = rest .. pandoc.utils.stringify(p.content[m])
              end
              local id = rest:match("{#(eq%-[^}%s]+)")
              if id then
                counts.Equation = counts.Equation + 1
                if current and (fixed_prefix or A.prefix_equations ~= false) then
                  map[id] = current .. esep .. counts.Equation
                end
              end
            end
          end
        end,
      })
    end
    for _, b in ipairs(out) do
      if is_appendix(b) and not fixed_prefix then
        in_appendix = true
        local letter = A.numbering and (appendix_letter(b) or A.single_letter) or nil
        if letter then
          current = letter
          counts = { Table = 0, Figure = 0, Equation = 0 }
        end
      elseif b.t == "Div" then
        local rec = find_float(b)
        if rec and counts[rec.type] ~= nil and rec.id and rec.id ~= "" then
          if moved_number[rec.id] then
            map[rec.id] = tostring(moved_number[rec.id])
          else
            counts[rec.type] = counts[rec.type] + 1
            if current and (fixed_prefix or A.prefix_floats ~= false) then
              map[rec.id] = current .. fsep .. counts[rec.type]
            elseif has_moved and in_appendix and after[rec.type] ~= nil then
              -- (no appendix letters: the numbers follow those of the text)
              after[rec.type] = after[rec.type] + 1
              map[rec.id] = tostring(n_moved[rec.type] + after[rec.type])
            end
          end
        elseif A.numbering or fixed_prefix then
          scan_equations(b)
        end
      elseif A.numbering or fixed_prefix then
        scan_equations(b)
      end
    end
    local entries = {}
    for id, label in pairs(map) do entries[id] = pandoc.MetaString(label) end
    if next(entries) ~= nil then doc.meta["mq-number-map"] = pandoc.MetaMap(entries) end
  end

  -- ---- Settings for the post-render filter that depend on the document ----
  local post = {}
  if Journal.post_options then
    for k, v in pairs(Journal.post_options() or {}) do post[k] = pandoc.MetaString(tostring(v)) end
  end
  -- (figures supplied as separate files: the manuscript prints their captions)
  if O.figures == "separate" and manuscript and not O.article then
    post["figures_separate"] = pandoc.MetaString("true")
  end
  if next(post) ~= nil then doc.meta["mq-post"] = pandoc.MetaMap(post) end

  -- ---- Front matter ----
  local front = pandoc.Blocks({})
  if is_latex or is_docx then
    if O.article then
      front = article_front()
    else
      if is_latex then
        front:insert(latex("\\" .. ID .. "setupmanuscript"))
        if fixed_prefix then front:insert(latex(counters_latex(fixed_prefix, "", "", true, true))) end
      end
      local jf = Journal.front and Journal.front(doc) or nil
      if jf then front:extend(jf) end
    end
  end
  front:extend(out)
  if Journal.back and (is_latex or is_docx) and not O.article then
    local jb = Journal.back(doc)
    if jb then front:extend(jb) end
  end
  -- Two page breaks in a row would leave an empty page in Word
  local final = pandoc.Blocks({})
  for _, b in ipairs(front) do
    if not (is_page_break(b) and is_page_break(final[#final])) then final:insert(b) end
  end
  doc.blocks = final
  return doc
end

-- Column heads in bold, for journals whose template prints them so. For the
-- PDF this is done here: Quarto writes the table of a code chunk as LaTeX
-- before the second filter runs. (The second filter does it for Word.)
local function bold_table_head(tbl)
  local function bold(content)
    if #content == 0 or (#content == 1 and content[1].t == "Strong") then return nil end
    return pandoc.Inlines({ pandoc.Strong(content) })
  end
  local head = tbl.head
  local rows = pandoc.List()
  for _, row in ipairs(head.rows) do
    local cells = pandoc.List()
    for _, cell in ipairs(row.cells) do
      cell.contents = cell.contents:walk({
        Plain = function(p)
          local c = bold(p.content)
          if c then return pandoc.Plain(c) end
        end,
        Para = function(p)
          local c = bold(p.content)
          if c then return pandoc.Para(c) end
        end,
      })
      cells:insert(cell)
    end
    row.cells = cells
    rows:insert(row)
  end
  head.rows = rows
  tbl.head = head
  return tbl
end

-- Journals with numbered sections: when the main sections of a document are
-- written with "##" and no heading has one "#", Quarto promotes every
-- heading by one level in the PDF, but not in Word, and that shift turns the
-- headings this filter adds ("References", the statements of a title page)
-- into paragraphs. The formats of the extension switch Quarto's shift off
-- (shift-heading-level-by: 0), and the promotion is made here, for both
-- outputs.
local function promote_headings(doc)
  if not J.number_sections then return nil end
  local top = false
  doc:walk({ Header = function(h) if h.level == 1 then top = true end end })
  if top then return nil end
  return doc:walk({
    Header = function(h)
      if h.level > 1 then
        h.level = h.level - 1
        return h
      end
      return nil
    end,
  })
end

local filters = {
  { Pandoc = promote_headings },
  { Meta = Meta },
}
if has_quarto then table.insert(filters, { FloatRefTarget = collect_float }) end
table.insert(filters, { Note = Note })
if is_latex and J.table_header_bold then table.insert(filters, { Table = bold_table_head }) end
table.insert(filters, { Pandoc = prepare_floats })
-- Top down, so that a note div is formatted once
table.insert(filters, { traverse = "topdown", Div = Div, Para = Para })
table.insert(filters, { Pandoc = clear_marks })
table.insert(filters, { Pandoc = Pandoc })
return filters
