-- amaquarto-post.lua  (amaquarto 1.0.0)
-- Runs after Quarto has rendered cross-referenced tables and figures (filter
-- entry point "post-render"). It sets captions as in AMA's sample document
-- ("Table 1: Title." centered above the table or figure), sets the text of Word
-- tables in the single-spaced "Table Text" style, and writes the "W" numbers of
-- a web appendix into the Word output.

-- =========================================================================
-- Journal settings
-- =========================================================================
local P = {
  id = "ama",
  -- AMA's sample document: "Table 1: Title." and "Figure 1: Title.",
  -- centered above the table or figure, with a period after the title
  caption = {
    Table = { sep = ": ", period = true, style = "Table Caption" },
    Figure = { sep = ": ", period = true, style = "Image Caption" },
  },
  -- AMA's Word template: the table centered, its column heads in bold
  table_align = "center",
  table_header_bold = true,
}

-- =========================================================================
-- Shared code (the same in every extension of this family)
-- =========================================================================
local is_docx = quarto.doc.is_format("docx")
local is_latex = quarto.doc.is_format("latex") or quarto.doc.is_format("pdf")

-- Numbers that carry a prefix (appendix letter, "W"), prepared by the first
-- filter: label of the table, figure, or equation -> number to print
local number_map = {}

-- Settings that depend on the document arrive from the first filter as
-- "caption.Table.bold_label" = "false", for example
local function apply_option(path, value)
  local target = P
  local keys = {}
  for key in path:gmatch("[^%.]+") do keys[#keys + 1] = key end
  for i = 1, #keys - 1 do
    if type(target[keys[i]]) ~= "table" then target[keys[i]] = {} end
    target = target[keys[i]]
  end
  if value == "true" then value = true elseif value == "false" then value = false end
  target[keys[#keys]] = value
end

local function read_meta(meta)
  local changed = false
  local m = meta["mq-number-map"]
  if m then
    for id, label in pairs(m) do number_map[id] = pandoc.utils.stringify(label) end
    meta["mq-number-map"] = nil
    changed = true
  end
  -- Where the titles of figures and tables go (Quarto's fig-cap-location
  -- and tbl-cap-location options)
  local where = meta["fig-cap-location"]
  if where then P.figure_caption_top = (pandoc.utils.stringify(where) == "top") end
  where = meta["tbl-cap-location"]
  if where then P.table_caption_top = (pandoc.utils.stringify(where) == "top") end
  local o = meta["mq-post"]
  if o then
    for path, value in pairs(o) do apply_option(path, pandoc.utils.stringify(value)) end
    meta["mq-post"] = nil
    changed = true
  end
  if changed then return meta end
  return nil
end

-- "[INSERT TABLE 1 HERE]": callouts in capitals, for journals that print them so
local function callout(div)
  if not (P.callout_upper and div.classes:includes("mq-callout")) then return nil end
  return div:walk({ Str = function(s) return pandoc.Str(pandoc.text.upper(s.text)) end })
end

-- Capitalize text, leaving math, code, raw output, and footnotes alone
local function upper_inlines(inlines)
  return inlines:walk({
    traverse = "topdown",
    Note = function(n) return n, false end,
    Str = function(s) return pandoc.Str(pandoc.text.upper(s.text)) end,
  })
end

local function float_kind(id)
  if id == nil then return nil end
  if id:match("^tbl%-") then return "Table" end
  if id:match("^fig%-") then return "Figure" end
  return nil
end

local function ends_with_punctuation(inlines)
  local last = inlines[#inlines]
  while last and (last.t == "Emph" or last.t == "Strong" or last.t == "Span" or last.t == "Quoted") do
    if last.t == "Quoted" then return true end
    last = last.content[#last.content]
  end
  if last == nil then return true end
  if last.t == "Str" then return last.text:match("[%.%?!:]$") ~= nil end
  if last.t == "Math" then return false end
  return true
end

-- The title of a table or figure as the journal prints it
local function format_title(title, C)
  if #title == 0 then return title end
  if C.upper then title = upper_inlines(title) end
  if C.period and not ends_with_punctuation(title) then title:insert(pandoc.Str(".")) end
  return title
end

-- =========================================================================
-- Word
-- =========================================================================

-- Quarto writes a Word caption as one paragraph that starts with raw
-- paragraph properties, then "Table 1: Title". The paragraph is rebuilt as
-- the journal prints it and given the caption style.
local function docx_caption(para, kind, id)
  local C = P.caption[kind]
  local inl = para.content
  if #inl == 0 then return nil end
  local start
  if inl[1].t == "RawInline" and inl[1].text:find("Caption") then
    start = 2
  else
    return nil
  end
  local label, title = pandoc.Inlines({}), pandoc.Inlines({})
  local found = false
  for i = start, #inl do
    local x = inl[i]
    if not found and x.t == "Str" and x.text:sub(-1) == ":" then
      local rest = x.text:sub(1, -2)
      if rest ~= "" then label:insert(pandoc.Str(rest)) end
      found = true
    elseif found then
      title:insert(x)
    else
      label:insert(x)
    end
  end
  -- No delimiter: a caption without a title, or the caption of a panel
  if not found then
    if #label == 0 or not pandoc.utils.stringify(label):match("%d") then return nil end
    title = pandoc.Inlines({})
  end
  while title[1] and (title[1].t == "Space" or title[1].t == "SoftBreak") do
    title:remove(1)
  end
  -- A number with a prefix
  if id and number_map[id] then
    for i = #label, 1, -1 do
      if label[i].t == "Str" and label[i].text:match("^%d+$") then
        label[i] = pandoc.Str(number_map[id]); break
      end
    end
  end
  if C.upper_label then label = upper_inlines(label) end
  title = format_title(title, C)
  if C.italic_title and #title > 0 then title = pandoc.Inlines({ pandoc.Emph(title) }) end
  local out = pandoc.Inlines({})
  if C.bold_label then out:insert(pandoc.Strong(label)) else out:extend(label) end
  if #title > 0 then
    if C.newline then
      out:insert(pandoc.LineBreak())
    else
      local sep = C.sep or ": "
      -- (an em space separates without a punctuation mark)
      local mark = sep:gsub("\u{2003}", ""):gsub("%s+$", "")
      if C.bold_label and mark ~= "" then
        out[#out] = pandoc.Strong(label .. pandoc.Inlines({ pandoc.Str(mark) }))
      elseif mark ~= "" then
        out:insert(pandoc.Str(mark))
      end
      if sep:match("\u{2003}") then out:insert(pandoc.Str("\u{2003}")) else out:insert(pandoc.Space()) end
    end
    out:extend(title)
  elseif C.sep and C.sep:match("^%.") and not C.newline then
    -- "Table 1." without a title
    if C.bold_label then out[#out] = pandoc.Strong(label .. pandoc.Inlines({ pandoc.Str(".") }))
    else out:insert(pandoc.Str(".")) end
  end
  return pandoc.Div({ pandoc.Para(out) },
    pandoc.Attr("", {}, { ["custom-style"] = C.style }))
end

local function has_image(block)
  local found = false
  pandoc.Blocks({ block }):walk({ Image = function() found = true end })
  return found
end

local function styled(style, blocks)
  return pandoc.Div(blocks, pandoc.Attr("", {}, { ["custom-style"] = style }))
end

-- Quarto places each table or figure, with its caption, in the single cell
-- of a layout table. Word then nests the data table inside that table, and
-- the cell's centering overrides the alignment of the data columns. A single
-- float is taken out of its layout table; layouts with several panels stay.
local function single_float(tbl)
  local rows = pandoc.List()
  for _, body in ipairs(tbl.bodies) do rows:extend(body.body) end
  if #tbl.head.rows > 0 or #rows ~= 1 or #rows[1].cells ~= 1 then return nil end
  local blocks = rows[1].cells[1].contents
  if #blocks == 1 and blocks[1].t == "Div" and float_kind(blocks[1].identifier) then
    return blocks[1]
  end
  return nil
end

-- -------------------------------------------------------------------------
-- Figures and tables with panels
-- -------------------------------------------------------------------------
-- Quarto lays the panels of a figure (or the parts of a table) out in
-- tables, one for each row of panels, and pandoc gives every table the
-- "Table" style of the reference document, whose rules are meant for data
-- tables. Each row is written again as a table without rules: its frame as
-- raw OpenXML, the pictures, tables, and captions as ordinary blocks in its
-- cells.

-- Panel with a label of its own -> label of the figure or table it belongs to
local panel_parent = {}

local function openxml(text) return pandoc.RawBlock("openxml", text) end

-- The divs that Quarto places in the cells of a layout table (one row)
local function layout_cells(tbl)
  if #tbl.head.rows > 0 or #tbl.foot.rows > 0 then return nil end
  local rows = pandoc.List()
  for _, body in ipairs(tbl.bodies) do
    if #body.head > 0 then return nil end
    rows:extend(body.body)
  end
  if #rows ~= 1 then return nil end
  local cells = pandoc.List()
  for _, cell in ipairs(rows[1].cells) do
    local blocks = cell.contents
    if not (#blocks == 1 and blocks[1].t == "Div" and blocks[1].attributes["layout-align"]) then
      return nil
    end
    cells:insert(blocks[1])
  end
  if #cells == 0 then return nil end
  return cells
end

-- What one panel holds: its pictures or its table, its caption, and the
-- label that cross-references point to; nil for a cell with other content
local function panel_parts(div)
  local parts = { images = pandoc.List(), tables = pandoc.List() }
  local ok = true
  local function take(blocks)
    for _, b in ipairs(blocks) do
      if not ok then return end
      if b.t == "Table" then
        local float = single_float(b)
        if float then
          take(pandoc.Blocks({ float }))
        elseif layout_cells(b) then
          ok = false
        else
          parts.tables:insert(b)
        end
      elseif b.t == "Div" then
        if float_kind(b.identifier) then parts.id = parts.id or b.identifier end
        take(b.content)
      elseif b.t == "Figure" then
        take(b.content)
        local caption = pandoc.utils.blocks_to_inlines(b.caption.long)
        if #caption > 0 then parts.caption = caption end
      elseif b.t == "Para" or b.t == "Plain" then
        local images, rest, is_caption = pandoc.List(), pandoc.Inlines({}), false
        for i, x in ipairs(b.content) do
          if x.t == "Image" then
            images:insert(x)
          elseif x.t == "RawInline" then
            -- Quarto opens a caption with raw paragraph properties
            if i == 1 and x.text:find("Caption", 1, true) then is_caption = true end
          else
            rest:insert(x)
          end
        end
        local text = pandoc.utils.stringify(rest):gsub("\u{a0}", ""):gsub("%s", "")
        if #images > 0 and text == "" then
          parts.images:extend(images)
        elseif #images == 0 and text ~= "" and is_caption then
          parts.caption = rest
        elseif #images > 0 or text ~= "" then
          ok = false
        end
      elseif b.t ~= "RawBlock" then
        ok = false
      end
    end
  end
  take(div.content)
  if not ok then return nil end
  return parts
end

-- One row of panels. Returns nil when the table is not a row of pictures
-- or of tables.
local function panel_row(cells)
  local text_width = P.text_width or 6.5
  local n = #cells
  local parts, share = {}, {}
  local found, total = false, 0
  for i, div in ipairs(cells) do
    parts[i] = panel_parts(div)
    if not parts[i] then return nil end
    if #parts[i].images > 0 or #parts[i].tables > 0 then found = true end
    share[i] = tonumber((div.attributes["width"] or ""):match("^([%d%.]+)%%$")) or (100 / n)
    total = total + share[i]
    if parts[i].id and div.attributes["ref-parent"] then
      panel_parent[parts[i].id] = div.attributes["ref-parent"]
    end
  end
  if not found then return nil end
  if total > 100 then
    for i = 1, n do share[i] = share[i] * 100 / total end
  end
  local content, empty = {}, true
  for i, p in ipairs(parts) do
    local blocks = pandoc.Blocks({})
    local inner = math.max(0.5, text_width * share[i] / 100 - 0.1)
    -- (figures supplied as separate files: the captions of the panels stay)
    if not P.figures_separate then
      for _, img in ipairs(p.images) do
        -- A little narrower than the cell, so that neighbors do not touch
        img.attributes["width"] = string.format("%.2fin", inner)
        img.attributes["height"] = nil
        blocks:insert(styled("Figure", { pandoc.Para({ img }) }))
      end
    end
    for _, tbl in ipairs(p.tables) do
      -- Quarto stretches a table in a panel over the page; its columns get
      -- the widths their text needs, within the width of the panel
      tbl.colspecs = tbl.colspecs:map(function(spec) return { spec[1] } end)
      local attr = tbl.attr
      attr.attributes["mq-width"] = string.format("%.2f", inner)
      tbl.attr = attr
      blocks:insert(tbl)
    end
    -- The caption of a panel stands where the titles of figures or of
    -- tables stand
    if p.caption then
      local top = P.figure_caption_top
      if #p.tables > 0 then top = (P.table_caption_top ~= false) end
      local caption = styled("Panel Caption", { pandoc.Para(p.caption) })
      if top then blocks:insert(1, caption) else blocks:insert(caption) end
    end
    if #blocks > 0 then empty = false end
    -- (a cell holds at least one paragraph, and ends with a paragraph)
    if #blocks == 0 then
      blocks:insert(openxml('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto" /></w:pPr></w:p>'))
    elseif blocks[#blocks].t == "Table" then
      blocks:insert(openxml('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="120" w:lineRule="exact" /></w:pPr></w:p>'))
    end
    -- The label of the panel stays, as the target of cross-references
    if p.id then blocks = pandoc.Blocks({ pandoc.Div(blocks, pandoc.Attr(p.id)) }) end
    content[i] = blocks
  end
  local out = pandoc.Blocks({})
  if empty then return out end
  local grid, width, sum = {}, {}, 0
  for i = 1, n do
    width[i] = math.floor(text_width * share[i] / 100 * 1440 + 0.5)
    sum = sum + width[i]
    grid[i] = string.format('<w:gridCol w:w="%d" />', width[i])
  end
  -- No rules: the "Table" style is the default table style of the reference
  -- document, and Word applies it, with the rules of its first row, to a
  -- table that names no style. The borders are therefore switched off in the
  -- table, in its look, and in every cell.
  -- (CT_TblPr order: tblW, jc, tblBorders, tblLayout, tblCellMar, tblLook)
  local none, cell_none = "", ""
  for _, edge in ipairs({ "top", "left", "bottom", "right", "insideH", "insideV" }) do
    none = none .. '<w:' .. edge .. ' w:val="nil" />'
  end
  for _, edge in ipairs({ "top", "left", "bottom", "right" }) do
    cell_none = cell_none .. '<w:' .. edge .. ' w:val="nil" />'
  end
  local pending = string.format('<w:tbl><w:tblPr><w:tblW w:w="%d" w:type="dxa" /><w:jc w:val="center" />'
    .. '<w:tblBorders>%s</w:tblBorders>'
    .. '<w:tblLayout w:type="fixed" /><w:tblCellMar><w:left w:w="0" w:type="dxa" />'
    .. '<w:right w:w="0" w:type="dxa" /></w:tblCellMar>'
    .. '<w:tblLook w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="0" w:val="0000" />'
    .. '</w:tblPr><w:tblGrid>%s</w:tblGrid>'
    .. '<w:tr><w:trPr><w:cantSplit /></w:trPr>', sum, none, table.concat(grid))
  for i = 1, n do
    out:insert(openxml(pending .. string.format(
      '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa" /><w:tcBorders>%s</w:tcBorders></w:tcPr>', width[i], cell_none)))
    out:extend(content[i])
    pending = "</w:tc>"
  end
  out:insert(openxml(pending .. "</w:tr></w:tbl>"))
  return out
end

-- The rows of one layout follow each other, separated by a raw paragraph
-- that keeps Word from joining the tables
local function docx_panels(blocks)
  local out, changed = pandoc.Blocks({}), false
  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    local cells = (b.t == "Table") and layout_cells(b) or nil
    local row = cells and panel_row(cells) or nil
    if row then
      local panel = pandoc.Blocks({})
      panel:extend(row)
      local j = i + 1
      while true do
        local sep, nxt = blocks[j], blocks[j + 1]
        if not (sep and sep.t == "RawBlock" and sep.text:find("framePr", 1, true)
                and nxt and nxt.t == "Table") then break end
        local more = layout_cells(nxt)
        local nxt_row = more and panel_row(more) or nil
        if not nxt_row then break end
        if #panel > 0 and #nxt_row > 0 then panel:insert(sep) end
        panel:extend(nxt_row)
        j = j + 2
      end
      if #panel > 0 then out:insert(pandoc.Div(panel, pandoc.Attr("", { "mq-panel" }))) end
      i = j
      changed = true
    else
      out:insert(b)
      i = i + 1
    end
  end
  if changed then return out end
  return nil
end

-- Caption in the caption style; a figure's image in the "Figure" style
local function docx_float(div)
  local kind = float_kind(div.identifier)
  if not kind then return nil end
  local content = pandoc.Blocks({})
  local captioned = false
  local caption_at, panel_at
  for _, b in ipairs(div.content) do
    local cap = (not captioned and b.t == "Para") and docx_caption(b, kind, div.identifier) or nil
    if cap then
      content:insert(cap)
      captioned = true
      caption_at = #content
    elseif kind == "Figure" and (b.t == "Plain" or b.t == "Para") and has_image(b) then
      -- (figures supplied as separate files: the caption alone is printed)
      if not P.figures_separate then content:insert(styled("Figure", { b })) end
    else
      content:insert(b)
      if b.t == "Div" and b.classes:includes("mq-panel") and not panel_at then panel_at = #content end
    end
  end
  -- Quarto writes the title of a figure or table with panels below the
  -- panels, also where titles stand above
  local top = P.figure_caption_top
  if kind == "Table" then top = (P.table_caption_top ~= false) end
  if top and caption_at and panel_at and caption_at > panel_at then
    content:insert(panel_at, content:remove(caption_at))
  end
  div.content = content
  return div
end

local function holds_float(tbl)
  local found = false
  pandoc.Blocks({ tbl }):walk({
    Div = function(d) if float_kind(d.identifier) then found = true end end,
  })
  return found
end

-- Pandoc's table fields are copies, so rows are rebuilt and assigned back.
-- Word gives Plain blocks in cells the "Compact" style whatever the
-- enclosing div says, so they become paragraphs first.
local function style_rows(rows)
  local out = pandoc.List()
  for _, row in ipairs(rows) do
    local cells = pandoc.List()
    for _, cell in ipairs(row.cells) do
      local blocks = cell.contents:map(function(b)
        if b.t == "Plain" then return pandoc.Para(b.content) end
        return b
      end)
      -- An empty cell gets an empty paragraph in the same style; otherwise
      -- Word gives it the (double-spaced) default style
      if #blocks == 0 then blocks = pandoc.Blocks({ pandoc.Para({ pandoc.Str("") }) }) end
      cell.contents = pandoc.Blocks({ styled("Table Text", blocks) })
      cells:insert(cell)
    end
    row.cells = cells
    out:insert(row)
  end
  return out
end

-- Column heads in bold, for journals whose sample tables print them so
local function bold_rows(rows)
  local out = pandoc.List()
  for _, row in ipairs(rows) do
    local cells = pandoc.List()
    for _, cell in ipairs(row.cells) do
      -- (a head that is bold already is left alone)
      local function bold(content)
        if #content == 0 or (#content == 1 and content[1].t == "Strong") then return nil end
        return pandoc.Inlines({ pandoc.Strong(content) })
      end
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
    out:insert(row)
  end
  return out
end

-- The longest line and the longest word of each column, in characters, and
-- the number of text lines each row needs at given widths; nil when cells
-- are merged
local function column_scan(tbl)
  local n = #tbl.colspecs
  if n == 0 then return nil end
  local natural, word, rows = {}, {}, {}
  for i = 1, n do natural[i], word[i] = 0, 0 end
  local simple = true
  local function scan(list)
    for _, row in ipairs(list) do
      if #row.cells ~= n then simple = false; return end
      local cells = {}
      for i, cell in ipairs(row.cells) do
        if cell.col_span ~= 1 or cell.row_span ~= 1 then simple = false; return end
        local chars, lines = 0, 0
        for _, block in ipairs(cell.contents) do
          local text = pandoc.utils.stringify(block)
          for line in (text .. "\n"):gmatch("(.-)\n") do
            local len = utf8.len(line) or #line
            natural[i] = math.max(natural[i], len)
            chars = chars + len
            lines = lines + 1
            for w in line:gmatch("[^%s%-/]+") do
              word[i] = math.max(word[i], utf8.len(w) or #w)
            end
          end
        end
        cells[i] = { chars = chars, lines = math.max(1, lines) }
      end
      rows[#rows + 1] = cells
    end
  end
  scan(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do scan(body.head); scan(body.body) end
  scan(tbl.foot.rows)
  if not simple then return nil end
  return natural, word, rows
end

-- About half an em for each character
local function char_width() return (P.table_pt or 12) * 0.5 / 72 end

-- The width of the text that the columns of a table share, in inches: the
-- line (or the panel that holds the table) without the space between columns
local function usable_width(tbl, n)
  local line = tonumber(tbl.attr.attributes["mq-width"]) or P.text_width or 6.5
  if is_docx then return line - 0.16 * n end
  return line - (12 / 72) * (n - 1)
end

-- A pipe table whose lines are long takes the widths of its columns from the
-- dashes under the column heads. When such a width is too small for the
-- longest word of its column (equal dashes under a wide and a narrow
-- column), the word would be broken in the middle. The widths are then set
-- from the contents: columns that need less than an even share keep what
-- they need, and the others divide the rest in proportion to their text.
local function repair_widths(tbl)
  local n = #tbl.colspecs
  local given, sum = {}, 0
  for i, spec in ipairs(tbl.colspecs) do
    if type(spec[2]) ~= "number" then return nil end
    given[i] = spec[2]
    sum = sum + spec[2]
  end
  if n == 0 or sum <= 0 then return nil end
  local natural, word = column_scan(tbl)
  if not natural then return nil end
  local cw, usable = char_width(), usable_width(tbl, n)
  if usable <= 0 then return nil end
  local squeezed = false
  for i = 1, n do
    local room = is_docx and (given[i] / sum * (usable + 0.16 * n) - 0.16) or (given[i] / sum * usable)
    if room < word[i] * cw * 0.9 then squeezed = true end
  end
  if not squeezed then return nil end
  local need, total = {}, 0
  for i = 1, n do
    need[i] = math.max(natural[i] * cw, 0.25)
    total = total + need[i]
  end
  local specs = tbl.colspecs
  if total <= usable then
    -- Everything fits without wrapping: the table is as wide as its contents
    for i = 1, n do specs[i] = { specs[i][1] } end
    tbl.colspecs = specs
    return tbl
  end
  local width, open, count, remaining = {}, {}, n, usable
  for i = 1, n do open[i] = true end
  local changed = true
  while changed and count > 0 do
    changed = false
    local fair = remaining / count
    for i = 1, n do
      if open[i] and need[i] <= fair then
        width[i] = need[i]
        remaining = remaining - need[i]
        open[i] = false
        count = count - 1
        changed = true
      end
    end
  end
  local rest = 0
  for i = 1, n do if open[i] then rest = rest + need[i] end end
  for i = 1, n do
    if open[i] then width[i] = remaining * need[i] / rest end
  end
  -- A column of running text is not made narrower than its longest word.
  -- The space comes from the other columns, whose estimate is generous, up
  -- to a fifth of their width.
  local deficit, settled = 0, 0
  for i = 1, n do
    if open[i] then
      local floor = word[i] * cw
      if width[i] < floor then deficit = deficit + floor - width[i] end
    else
      settled = settled + width[i]
    end
  end
  if deficit > 0 and settled > 0 then
    local scale = math.max(0.8, (settled - deficit) / settled)
    local gained = settled * (1 - scale)
    for i = 1, n do
      if open[i] then
        local floor = word[i] * cw
        if width[i] < floor then width[i] = width[i] + (floor - width[i]) * gained / deficit end
      else
        width[i] = width[i] * scale
      end
    end
  end
  -- The shares that pandoc writes: of the text between the columns in LaTeX,
  -- of the whole table, cell margins included, in Word
  local pad = is_docx and 0.16 or 0
  local wsum = 0
  for i = 1, n do wsum = wsum + width[i] + pad end
  for i = 1, n do specs[i] = { specs[i][1], (width[i] + pad) / wsum * sum } end
  tbl.colspecs = specs
  return tbl
end

-- The number of text lines of a table, for the estimate of its height
local function table_lines(tbl)
  local count = #tbl.head.rows + #tbl.foot.rows
  for _, body in ipairs(tbl.bodies) do count = count + #body.head + #body.body end
  local natural, _, rows = column_scan(tbl)
  if not natural then return count end
  local n = #tbl.colspecs
  local usable, sum, share = usable_width(tbl, n), 0, {}
  for i, spec in ipairs(tbl.colspecs) do
    if type(spec[2]) ~= "number" then share = nil; break end
    share[i] = spec[2]
    sum = sum + spec[2]
  end
  local lines = 0
  for _, cells in ipairs(rows) do
    local most = 1
    for i, cell in ipairs(cells) do
      local need = cell.lines
      if share and sum > 0 then
        local per_line = math.max(1, math.floor(share[i] / sum * usable / char_width()))
        need = math.max(need, math.ceil(cell.chars / per_line))
      end
      most = math.max(most, need)
    end
    lines = lines + most
  end
  return math.max(count, lines)
end

local function docx_table(tbl)
  local float = single_float(tbl)
  if float then return float end
  if holds_float(tbl) then return nil end
  tbl = repair_widths(tbl) or tbl
  local head = tbl.head
  if P.table_header_bold then head.rows = bold_rows(head.rows) end
  head.rows = style_rows(head.rows)
  tbl.head = head
  local bodies = tbl.bodies
  for i, body in ipairs(bodies) do
    body.head = style_rows(body.head)
    body.body = style_rows(body.body)
    bodies[i] = body
  end
  tbl.bodies = bodies
  local foot = tbl.foot
  foot.rows = style_rows(foot.rows)
  tbl.foot = foot
  return tbl
end

-- -------------------------------------------------------------------------
-- Tables and numbered equations as raw OpenXML
-- -------------------------------------------------------------------------
-- Pandoc gives a table no alignment of its own: Word takes it from the table
-- style, and other programs set the table at the left margin with columns of
-- equal width. A table is therefore written the way pandoc writes it, the
-- alignment and an estimate of the column widths are added, and the result
-- is passed on as raw OpenXML. Tables that hold citations, footnotes,
-- images, or web links stay ordinary tables, because those parts are
-- numbered or linked for the document as a whole; they take their alignment
-- from the table style of the reference document.
local bookmark_id = 700000

local function stays_table(block)
  local stays = false
  pandoc.Blocks({ block }):walk({
    Cite = function() stays = true end,
    Note = function() stays = true end,
    Image = function() stays = true end,
    Link = function(l) if not l.target:match("^#") then stays = true end end,
  })
  return stays
end

-- The <w:tbl> element pandoc writes for a table, or nil
local function table_openxml(tbl)
  if not (pandoc.zip and pandoc.write and PANDOC_WRITER_OPTIONS) then return nil end
  local ok, bytes = pcall(pandoc.write, pandoc.Pandoc({ tbl }), "docx", PANDOC_WRITER_OPTIONS)
  if not ok or type(bytes) ~= "string" then return nil end
  local ok2, archive = pcall(pandoc.zip.Archive, bytes)
  if not ok2 or not archive then return nil end
  local xml
  for _, entry in ipairs(archive.entries) do
    if entry.path == "word/document.xml" then xml = entry:contents() end
  end
  if not xml then return nil end
  local first = xml:find("<w:tbl>", 1, true)
  local last, pos = nil, 1
  while true do
    local a, b = xml:find("</w:tbl>", pos, true)
    if not a then break end
    last, pos = b, b + 1
  end
  if not (first and last) then return nil end
  local t = xml:sub(first, last)
  -- Bookmark numbers may not repeat those of the document
  local seen = {}
  t = t:gsub('(<w:bookmark%a+ [^>]-w:id=")(%d+)(")', function(a, id, c)
    if not seen[id] then bookmark_id = bookmark_id + 1; seen[id] = bookmark_id end
    return a .. seen[id] .. c
  end)
  return t
end

-- Column widths in inches, estimated from the longest line of each column,
-- for a table whose widths are not given; nil for tables with merged cells
local function natural_widths(tbl)
  local n = #tbl.colspecs
  for _, spec in ipairs(tbl.colspecs) do
    if type(spec[2]) == "number" then return nil end
  end
  local chars, simple = {}, true
  for i = 1, n do chars[i] = 0 end
  local function scan(rows)
    for _, row in ipairs(rows) do
      if #row.cells ~= n then simple = false; return end
      for i, cell in ipairs(row.cells) do
        if cell.col_span ~= 1 or cell.row_span ~= 1 then simple = false; return end
        for _, block in ipairs(cell.contents) do
          local text = pandoc.utils.stringify(block)
          for line in (text .. "\n"):gmatch("(.-)\n") do
            chars[i] = math.max(chars[i], utf8.len(line) or #line)
          end
        end
      end
    end
  end
  scan(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do scan(body.head); scan(body.body) end
  scan(tbl.foot.rows)
  if not simple or n == 0 then return nil end
  -- About half an em for each character, and the cell margins
  local pt = P.table_pt or 12
  local widths, total = {}, 0
  for i = 1, n do
    widths[i] = math.max(0.45, chars[i] * pt * 0.5 / 72 + 0.25)
    total = total + widths[i]
  end
  -- (a table in a panel: the width of the panel)
  local limit = tonumber(tbl.attr.attributes["mq-width"]) or P.text_width or 6.5
  if total > limit then
    for i = 1, n do widths[i] = widths[i] * limit / total end
  end
  return widths
end

local function raw_table(tbl)
  if holds_float(tbl) or stays_table(tbl) then return nil end
  -- A table with a title but no label is not numbered. Only the table itself
  -- is taken from what pandoc writes, so its title is set here, above it.
  local title = nil
  if tbl.caption and tbl.caption.long and pandoc.utils.stringify(tbl.caption.long) ~= "" then
    title = styled((P.caption.Table and P.caption.Table.style) or "Table Caption",
      tbl.caption.long:map(function(b)
        if b.t == "Plain" then return pandoc.Para(b.content) end
        return b
      end))
  end
  local widths = natural_widths(tbl)
  local xml = table_openxml(tbl)
  if not xml then return nil end
  -- CT_TblPr order: tblStyle, ..., tblW, jc, ..., tblLook
  local jc = '<w:jc w:val="' .. ((P.table_align == "left") and "left" or "center") .. '" />'
  local n
  xml, n = xml:gsub("(<w:tblW [^>]-/>)", function(w) return w .. jc end, 1)
  if n == 0 then return nil end
  if widths then
    local cols = {}
    for _, w in ipairs(widths) do
      cols[#cols + 1] = string.format('<w:gridCol w:w="%d" />', math.floor(w * 1440 + 0.5))
    end
    local grid = "<w:tblGrid>" .. table.concat(cols) .. "</w:tblGrid>"
    xml = xml:gsub("<w:tblGrid>.-</w:tblGrid>", function() return grid end, 1)
  end
  if title then return { title, pandoc.RawBlock("openxml", xml) } end
  return pandoc.RawBlock("openxml", xml)
end

-- A display equation that stands alone in its paragraph. Quarto writes the
-- number of a numbered equation into the math itself, "\qquad(1)", so Word
-- prints it next to the equation. Journals ask for the number flush right:
-- the equation goes in the middle cell of a table without borders and the
-- number in the right cell. An equation without a number is centered in a
-- paragraph without indentation.
local function docx_display_equation(para)
  if #para.content ~= 1 then return nil end
  local x = para.content[1]
  local span, math = nil, nil
  if x.t == "Span" and #x.content == 1 and x.content[1].t == "Math" then
    span, math = x, x.content[1]
  elseif x.t == "Math" then
    math = x
  end
  if not math or math.mathtype ~= "DisplayMath" then return nil end
  local body, digits = math.text:match("^(.-)%s*\\q?quad%s*%((%d+)%)%s*$")
  if not body then
    return styled("Equation", { para })
  end
  local label = (span and number_map[span.identifier]) or digits
  local number = pandoc.Inlines({ pandoc.Str("(" .. label .. ")") })
  if P.equation_bold then number = pandoc.Inlines({ pandoc.Strong(number) }) end
  local equation = pandoc.Math("DisplayMath", body)
  local middle = span and pandoc.Span({ equation }, span.attr) or equation
  local simple = pandoc.SimpleTable(
    {},
    { pandoc.AlignLeft, pandoc.AlignCenter, pandoc.AlignRight },
    { 0.08, 0.84, 0.08 },
    { {}, {}, {} },
    { {
      { styled("Equation", { pandoc.Para({ pandoc.Str("") }) }) },
      { styled("Equation", { pandoc.Para({ middle }) }) },
      { styled("Equation", { pandoc.Para(number) }) },
    } })
  local tbl = pandoc.utils.from_simple_table(simple)
  -- (no header row)
  local head = tbl.head
  head.rows = {}
  tbl.head = head
  local xml = table_openxml(tbl)
  if not xml then return nil end
  local none, cell_none = "", ""
  for _, edge in ipairs({ "top", "left", "bottom", "right", "insideH", "insideV" }) do
    none = none .. '<w:' .. edge .. ' w:val="nil" />'
  end
  for _, edge in ipairs({ "top", "left", "bottom", "right" }) do
    cell_none = cell_none .. '<w:' .. edge .. ' w:val="nil" />'
  end
  local n
  xml, n = xml:gsub("(<w:tblW [^>]-/>)", function(w)
    return w .. '<w:jc w:val="center" /><w:tblBorders>' .. none .. '</w:tblBorders>'
  end, 1)
  if n == 0 then return nil end
  local margins = '<w:tblCellMar><w:left w:w="0" w:type="dxa" /><w:right w:w="0" w:type="dxa" /></w:tblCellMar>'
  xml, n = xml:gsub("(<w:tblLayout [^>]-/>)", function(l) return l .. margins end, 1)
  if n == 0 then
    xml = xml:gsub("(<w:tblLook )", function(l) return margins .. l end, 1)
  end
  -- No rules; the number is centered on the height of the equation
  -- (CT_TcPr order: tcW, ..., tcBorders, ..., vAlign)
  xml = xml:gsub('w:firstRow="1"', 'w:firstRow="0"')
  local cell = '<w:tcBorders>' .. cell_none .. '</w:tcBorders><w:vAlign w:val="center" />'
  xml = xml:gsub("<w:tcPr />", "<w:tcPr></w:tcPr>")
  xml = xml:gsub("</w:tcPr>", function() return cell .. "</w:tcPr>" end)
  return pandoc.RawBlock("openxml", xml)
end

-- Cross-references to numbers with a prefix: "Table 1" becomes "Table W1"
local function docx_xref(link)
  if not link.classes:includes("quarto-xref") then return nil end
  local id = link.target:match("^#(.+)$")
  -- A panel of a figure: Quarto writes "Fig. 1 (a)" in Word and "Fig. 1a" in
  -- LaTeX; the Word output follows the LaTeX output
  local parent = id and panel_parent[id]
  if parent then
    local c = link.content
    local n = #c
    if n >= 5 and c[n].t == "Str" and c[n].text == ")" and c[n - 1].t == "Str"
       and c[n - 2].t == "Str" and c[n - 2].text == "(" and c[n - 3].t == "Space"
       and c[n - 4].t == "Str" and c[n - 4].text:match("%d$") then
      local number = c[n - 4].text
      if number_map[parent] then number = number:gsub("%d+$", function() return number_map[parent] end) end
      local letter = c[n - 1].text
      for _ = 1, 4 do c:remove(#c) end
      c[#c] = pandoc.Str(number .. letter)
      link.content = c
      return link
    end
    return nil
  end
  local label = id and number_map[id]
  -- "Eq. (1)" for journals that cite equations with parentheses
  local parens = P.equation_ref_parens and id ~= nil and id:match("^eq%-") ~= nil
  if not label and not parens then return nil end
  local changed = false
  local content = link.content:walk({
    Str = function(s)
      if changed then return nil end
      local head, digits = s.text:match("^(.-)(%d+)$")
      if digits then
        changed = true
        local number = label or digits
        if parens then number = "(" .. number .. ")" end
        return pandoc.Str(head .. number)
      end
    end,
  })
  if changed then link.content = content; return link end
  return nil
end

-- LaTeX: "Eq. (1)" for journals that cite equations with parentheses
local function latex_equation_ref(raw)
  if not P.equation_ref_parens then return nil end
  if raw.format:match("tex") and raw.text:match("^\\ref{eq%-[^}]+}$") then
    return pandoc.RawInline(raw.format, "(" .. raw.text .. ")")
  end
  return nil
end

-- Numbered equations: Quarto writes the number into the math, "\qquad(1)"
local function docx_equation(span)
  local label = number_map[span.identifier]
  local bold = P.equation_bold and span.identifier:match("^eq%-") ~= nil
  if not label and not bold then return nil end
  return span:walk({
    Math = function(m)
      local text, n = m.text:gsub("%((%d+)%)%s*$", function(digits)
        local number = label and ("\\text{" .. label .. "}") or digits
        -- Some journals print the equation number in bold
        if bold then return "\\mathbf{(" .. number .. ")}" end
        return "(" .. number .. ")"
      end)
      if n > 0 then m.text = text; return m end
    end,
  })
end

-- "1 Title" and "1.1 Title": the journal prints a period after the number
-- (heading_number_period = true) or none at any level (false; Quarto writes
-- one after the number of a first-level heading)
local function docx_header(h)
  if P.heading_number_period == nil then return nil end
  if P.heading_number_period == false then
    if h.classes:includes("unnumbered") then return nil end
    local stripped = false
    h.content = h.content:walk({
      Span = function(s)
        if s.classes:includes("header-section-number") then
          local text = pandoc.utils.stringify(s.content)
          if text:match("^%d[%d%.]*%.$") then
            stripped = true
            s.content = pandoc.Inlines({ pandoc.Str((text:gsub("%.$", ""))) })
            return s
          end
        end
      end,
    })
    if stripped then return h end
    -- Quarto writes the number as plain text: "1", ". ", "Title" at the
    -- first level and "1.1", a space, "Title" below it
    local content = h.content
    local first, second = content[1], content[2]
    if first and first.t == "Str" and first.text:match("^%d[%d%.]*$") and second and second.t == "Str"
       and second.text == ". " then
      content[2] = pandoc.Space()
      h.content = content
      return h
    end
    return nil
  end
  local changed = false
  h.content = h.content:walk({
    Span = function(s)
      if s.classes:includes("header-section-number") then
        local text = pandoc.utils.stringify(s.content)
        if not text:match("%.$") then
          changed = true
          s.content = pandoc.Inlines({ pandoc.Str(text .. ".") })
          return s
        end
      end
    end,
  })
  if changed then return h end
  -- Quarto writes the number as plain text: "1. Title" at the first level
  -- and "1.1 Title" below it
  if h.classes:includes("unnumbered") then return nil end
  local content = h.content
  local first, second = content[1], content[2]
  if first and first.t == "Str" and first.text:match("^%d+%.%d[%d%.]*$")
     and not first.text:match("%.$") and second and second.t == "Space" then
    content[1] = pandoc.Str(first.text .. ".")
    h.content = content
    return h
  end
  return nil
end

-- =========================================================================
-- LaTeX (the caption package formats the labels; see the header file)
-- =========================================================================

-- Tables written in Markdown arrive as pandoc tables with their caption
-- still in place
local function latex_table(tbl)
  local C = P.caption.Table
  tbl = repair_widths(tbl) or tbl
  if P.table_header_bold then
    local head = tbl.head
    head.rows = bold_rows(head.rows)
    tbl.head = head
  end
  if (C.upper or C.period) and tbl.caption and tbl.caption.long and #tbl.caption.long > 0 then
    tbl.caption.long = tbl.caption.long:walk({
      Plain = function(p) p.content = format_title(p.content, C); return p end,
      Para = function(p) p.content = format_title(p.content, C); return p end,
    })
  end
  return tbl
end

-- Figures arrive as raw LaTeX scaffolding: a span that opens with \caption
local function latex_caption_span(span)
  local first = span.content[1]
  if not (first and first.t == "RawInline" and first.text:match("^\\caption")) then return nil end
  -- Quarto 1.4 to 1.11: \caption{ \label{...} title } as raw pieces around the title
  -- (the label may be split into several raw pieces inside a nested span)
  local C = P.caption.Figure
  local raw = {}
  span.content:walk({ RawInline = function(r) raw[#raw + 1] = r.text end })
  if table.concat(raw):find("\\label{tbl-", 1, true) then C = P.caption.Table end
  if not (C.upper or C.period) then return nil end
  local content = span.content
  if C.upper then content = upper_inlines(content) end
  if C.period then
    -- The last piece closes the caption; the title ends just before it
    local last = #content
    while last > 1 and content[last].t == "RawInline" do last = last - 1 end
    if last > 1 then
      local title = pandoc.Inlines({})
      for i = 2, last do
        if content[i].t ~= "RawInline" then title:insert(content[i]) end
      end
      if #title > 0 and not ends_with_punctuation(title) then
        content:insert(last + 1, pandoc.Str("."))
      end
    end
  end
  span.content = content
  return span
end

-- Word sets a paragraph that follows a table or a picture directly against
-- it. A table, and a figure with its title above, that has no note is
-- followed by an empty paragraph of a fixed height (P.float_space, 12 pt
-- unless the journal sets another value).
local function docx_note(b)
  if b == nil or b.t ~= "Div" then return false end
  if b.classes:includes("mq-note") or b.attributes["custom-style"] == "Table Note" then return true end
  return #b.content == 1 and docx_note(b.content[1])
end

local function docx_picture(b)
  return (b.t == "Para" or b.t == "Plain") and #b.content == 1 and b.content[1].t == "Image"
end

-- (a figure whose title stands below it: the title follows the picture)
local function docx_caption_block(b)
  return b.t == "Div" and (b.attributes["custom-style"] or ""):find("Caption", 1, true) ~= nil
end

local function docx_space_after(blocks, following, in_figure)
  local height = P.float_space or 12
  local out = pandoc.Blocks({})
  for i, b in ipairs(blocks) do
    local nxt = blocks[i + 1] or following
    local panel = b.t == "Div" and b.classes:includes("mq-panel")
    if b.t == "Div" and not panel and not docx_note(b) then
      local figure = in_figure or (b.identifier:match("^fig%-") ~= nil)
      b.content = docx_space_after(b.content, nxt, figure)
      out:insert(b)
    else
      out:insert(b)
      if (b.t == "Table" or panel or (in_figure and docx_picture(b))) and nxt ~= nil
         and not docx_note(nxt) and not docx_caption_block(nxt) then
        out:insert(pandoc.RawBlock("openxml", string.format(
          '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="%d" w:lineRule="exact" /></w:pPr></w:p>',
          math.floor(height * 20 + 0.5))))
      end
    end
  end
  return out
end

local function docx_float_space(doc)
  if (P.float_space or 12) <= 0 then return nil end
  doc.blocks = docx_space_after(doc.blocks, nil, false)
  return doc
end

-- A table set as a LaTeX float (the raw LaTeX output of a code chunk): it
-- stays where it is written, like the figures and the other tables, and
-- journals that ask for tables at the left margin get it there (Quarto
-- centers it)
local function latex_table_float(div)
  local content = div.content
  local first = content[1]
  if not (first and first.t == "RawBlock" and first.text:match("^%s*\\begin{table")) then return nil end
  local changed = false
  if first.text:match("^%s*\\begin{table}%s*$") then
    content[1] = pandoc.RawBlock(first.format, "\\begin{table}[H]")
    div.content = content
    changed = true
  end
  if P.table_align == "left" then
    div = div:walk({
      RawInline = function(r)
        if r.text == "\\centering" then return pandoc.RawInline(r.format, "\\raggedright") end
      end,
    })
    changed = true
  end
  if changed then return div end
  return nil
end

-- A panel of pictures without a label of its own: Quarto sets each picture
-- as a figure with a sub-caption, which advances the figure counter although
-- no number is printed, so the next figure skips numbers. The captions are
-- printed without a letter (\<id>panelcaption in the header file), the
-- counter stays as it is, and the panel stays where it is written.
local function latex_plain_panel(div)
  local content = div.content
  local first = content[1]
  if not (first and first.t == "RawBlock" and first.text:match("^%s*\\begin{figure}%s*$")) then return nil end
  local main, sub = false, false
  div:walk({
    RawInline = function(r)
      if r.text:match("^\\caption") then main = true end
      if r.text == "\\subcaption" then sub = true end
    end,
  })
  if main then return nil end
  content[1] = pandoc.RawBlock(first.format, "\\begin{figure}[H]")
  div.content = content
  if sub then
    div = div:walk({
      RawInline = function(r)
        if r.text == "\\subcaption" then return pandoc.RawInline(r.format, "\\" .. P.id .. "panelcaption") end
      end,
    })
  end
  return div
end

-- Figures supplied as separate files: the picture is left out of the figure
-- environment, and its caption stays
local function latex_figure_float(div)
  if not P.figures_separate then return nil end
  local first = div.content[1]
  if not (first and first.t == "RawBlock" and first.text:match("^%s*\\begin{figure")) then return nil end
  local function only_images(el)
    local n = 0
    for _, x in ipairs(el.content) do
      if x.t == "Image" then n = n + 1
      elseif x.t ~= "Space" and x.t ~= "SoftBreak" then return false end
    end
    return n > 0
  end
  return div:walk({
    Plain = function(p) if only_images(p) then return {} end end,
    Para = function(p) if only_images(p) then return {} end end,
  })
end

-- A picture or a table with a caption but no label, set by Quarto in a
-- figure or table environment: LaTeX would number it, and every later
-- number would differ from the Word file, where it carries none. The
-- caption is printed without a number and the counter is put back.
local function latex_unlabeled_float(div)
  local first = div.content[1]
  if not (first and first.t == "RawBlock") then return nil end
  local kind = first.text:match("^%s*\\begin{(figure)%*?}") or first.text:match("^%s*\\begin{(table)%*?}")
  if not kind then return nil end
  -- (Quarto may write a label in several raw pieces)
  local raw = {}
  local function look(r) raw[#raw + 1] = r.text end
  div:walk({ RawInline = look, RawBlock = look })
  local text = table.concat(raw)
  if not text:find("\\caption", 1, true) or text:find("\\label{", 1, true) then return nil end
  return {
    pandoc.RawBlock("latex", "\\" .. P.id .. "plainbegin{" .. kind .. "}"),
    div,
    pandoc.RawBlock("latex", "\\" .. P.id .. "plainend{" .. kind .. "}"),
  }
end

local function is_note(b) return b ~= nil and b.t == "Div" and b.classes:includes("mq-note") end

-- A note that follows a figure, or a table set as a LaTeX float, moves inside
-- the float, so that a page break cannot fall between the two
local function into_float(block, note)
  if block.t ~= "Div" then return nil end
  local content = block.content
  local n = #content
  while n > 0 and content[n].t == "RawBlock" and content[n].text:match("^%s*$") do n = n - 1 end
  if n == 0 then return nil end
  local last = content[n]
  if last.t == "RawBlock" and (last.text:match("^%s*\\end{figure%*?}")
     or last.text:match("^%s*\\end{table%*?}")) then
    for k, b in ipairs(note) do content:insert(n + k - 1, b) end
    block.content = content
    return block
  elseif last.t == "Div" then
    local inner = into_float(last, note)
    if inner then
      content[n] = inner
      block.content = content
      return block
    end
  end
  return nil
end

-- A table that fits on a page is kept on one page with its title and note:
-- the header file's "keep" command starts a new page when the rest of the
-- page is too short. The height is an estimate: the space above the table,
-- its title, the rules, and a note of two lines (about 90 pt in all), then
-- about 15 pt for each row and for each further line of the note.
local function keep_command(rows, note)
  if rows <= 0 then return nil end
  local row = P.row_height or 15
  local lines = 0
  if note then
    for _, b in ipairs(note.content) do
      if b.t == "Para" or b.t == "Plain" then
        lines = lines + math.max(1, math.ceil(#pandoc.utils.stringify(b) / 90))
      end
    end
  end
  local height = (P.keep_base or 90) + rows * row + math.max(0, lines - 2) * row
  if height >= 560 then return nil end
  return pandoc.RawBlock("latex", "\\" .. P.id .. "keep{" .. height .. "pt}")
end

-- Whether a table or a picture carries a label of the given kind ("tbl" or
-- "fig"): as its identifier, or as a \label written into its caption
local function has_label(el, kind)
  if tostring(el.identifier or ""):match("^" .. kind .. "%-") then return true end
  local cap = el.caption and el.caption.long
  if not cap then return false end
  local raw = {}
  cap:walk({ RawInline = function(r) raw[#raw + 1] = r.text end })
  return table.concat(raw):find("\\label{" .. kind .. "-", 1, true) ~= nil
end

local function latex_blocks(blocks)
  local out = pandoc.Blocks({})
  local changed = false
  local ends = {}
  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    if b.t == "Table" then
      local keep = keep_command(table_lines(b), is_note(blocks[i + 1]) and blocks[i + 1] or nil)
      if keep then out:insert(keep); changed = true end
      -- A table without a label takes no number (see the header file)
      if not has_label(b, "tbl") then
        out:insert(pandoc.RawBlock("latex", "\\" .. P.id .. "plainbegin{table}"))
        ends[i] = pandoc.RawBlock("latex", "\\" .. P.id .. "plainend{table}")
        changed = true
      end
    elseif b.t == "Figure" and not has_label(b, "fig") then
      -- A picture with a caption but no label: no number either
      out:insert(pandoc.RawBlock("latex", "\\" .. P.id .. "plainbegin{figure}"))
      ends[i] = pandoc.RawBlock("latex", "\\" .. P.id .. "plainend{figure}")
      changed = true
    elseif b.t == "RawBlock" and b.text:match("^%s*\\begin{longtable}") then
      -- The table of a code chunk, already written as LaTeX: count its rows
      local rows, j, closed, raw = 0, i, false, {}
      while j <= #blocks and not closed do
        local x = blocks[j]
        if x.t == "RawBlock" then
          local _, n = x.text:gsub("\\\\", "")
          rows = rows + n
          closed = x.text:find("\\end{longtable}", 1, true) ~= nil
          raw[#raw + 1] = x.text
        else
          pandoc.Blocks({ x }):walk({ RawInline = function(r) raw[#raw + 1] = r.text end })
        end
        j = j + 1
      end
      local labeled = table.concat(raw):find("\\label{", 1, true) ~= nil
      local keep = closed and keep_command(rows, nil) or nil
      if keep then out:insert(keep); changed = true end
      if closed and not labeled then
        out:insert(pandoc.RawBlock("latex", "\\" .. P.id .. "plainbegin{table}"))
        ends[j - 1] = pandoc.RawBlock("latex", "\\" .. P.id .. "plainend{table}")
        changed = true
      end
    elseif b.t == "Div" then
      while is_note(blocks[i + 1]) do
        local merged = into_float(b, blocks[i + 1].content)
        if not merged then break end
        b = merged
        i = i + 1
        changed = true
      end
    end
    out:insert(b)
    if ends[i] then out:insert(ends[i]) end
    i = i + 1
  end
  if changed then return out end
  return nil
end

-- Pandoc writes every metadata field that holds text into the custom
-- properties of a Word file. The fields of this extension, and the notes and
-- statements that the filter has printed itself, are removed at the end, so
-- that an anonymized manuscript does not carry an author note or the
-- acknowledgments in its file properties.
local OWN_FIELDS = { "author", "authors", "by-author", "by-affiliation", "affiliations", "institute",
  "author-meta", "author-note", "authornote", "acknowledgments", "acknowledgements", "funding",
  "funding-statement", "declarations", "data-availability", "data-availability-statement",
  "consumer-relevance-statement", "highlights", "anonymous" }

local function strip_meta(meta)
  local remove = {}
  for _, k in ipairs(OWN_FIELDS) do remove[#remove + 1] = k end
  local own = P.id .. "-"
  for k, _ in pairs(meta) do
    if type(k) == "string" and (k:sub(1, #own) == own or k:sub(1, 3) == "mq-") then
      remove[#remove + 1] = k
    end
  end
  for _, k in ipairs(remove) do meta[k] = nil end
  return meta
end

-- =========================================================================
if is_docx then
  return {
    { Meta = read_meta },
    { Div = callout },
    { Blocks = docx_panels },
    { Div = docx_float },
    { Table = docx_table },
    { Para = docx_display_equation },
    { Link = docx_xref, Span = docx_equation, Header = docx_header },
    { Pandoc = docx_float_space },
    { Table = raw_table },
    { Meta = strip_meta },
  }
elseif is_latex then
  return {
    { Meta = read_meta },
    { Div = callout },
    { Table = latex_table, Span = latex_caption_span, RawInline = latex_equation_ref },
    { Div = latex_table_float },
    { Div = latex_plain_panel },
    { Div = latex_figure_float },
    { Div = latex_unlabeled_float },
    { Blocks = latex_blocks },
  }
end
return {}
