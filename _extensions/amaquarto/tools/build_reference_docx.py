# Builds ama-reference.docx for the amaquarto extension from pandoc's default
# reference document, so every style pandoc and Quarto use exists exactly once.
#
# Usage, from the extension folder (requires Python 3 and python-docx):
#   quarto pandoc -o pandoc-default-reference.docx --print-default-data-file reference.docx
#   python3 tools/build_reference_docx.py pandoc-default-reference.docx ama-reference.docx
# A setting can be changed on the command line, for example "line=1.5" for
# 1.5 line spacing.
#
# The settings below follow AMA's submission guidelines and Word templates:
# letter paper, 1-inch margins, Times New Roman 12 pt, double spacing, no page
# numbers, headers, or footers; primary headings centered and bold; secondary
# headings flush left, bold italic; tertiary headings flush left, italic;
# table and figure titles centered; tables and their notes single spaced;
# footnotes in 12-point type; references double spaced with a half-inch
# hanging indent.
import sys
import warnings
import docx
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from docx.shared import Pt, Inches, RGBColor

# Pandoc names its caption style "Caption", which python-docx finds by style
# ID and warns about; the lookup is correct
warnings.filterwarnings("ignore", message="style lookup by style_id")

# ---------------------------------------------------------------------------
# Journal settings
# ---------------------------------------------------------------------------
PROFILE = {'doc_title': 'AMA journals manuscript reference document (amaquarto)',
 'font': 'Times New Roman',
 'size': 12,
 'line': 2.0,
 'indent': 0.5,
 'margins': 1,
 'page_numbers': None,
 'title': {'bold': True, 'align': 'center'},
 'author': {'align': 'center'},
 'abstract_title': {'bold': True, 'align': 'center', 'keep_next': True},
 'abstract': {},
 'keywords': {},
 'headings': {1: {'align': 'center',
                  'bold': True,
                  'before': 27.6,
                  'after': 27.6},
              2: {'bold': True, 'italic': True},
              3: {'italic': True}},
 'captions': {'table': {'align': 'center',
                        'line': 1.0,
                        'before': 12,
                        'after': 6},
              'figure': {'align': 'center',
                         'line': 1.0,
                         'before': 12,
                         'after': 6,
                         'keep_next': True},
              'figure_keep_next': True},
 'table_text': {'size': 12, 'line': 1.0},
 'table_note': {'size': 12, 'line': 1.0, 'before': 4, 'after': 12},
 'table_align': 'center',
 'bibliography': {'left': 0.5, 'hanging': 0.5},
 'footnote': {'size': 'body', 'line': 1.0},
 'statement': {'line': 1.0, 'after': 12}}

# ---------------------------------------------------------------------------
src, out = sys.argv[1], sys.argv[2]
d = docx.Document(src)
S = d.styles
P = PROFILE
for arg in sys.argv[3:]:
    key, _, value = arg.partition("=")
    try:
        value = float(value) if "." in value else int(value)
    except ValueError:
        pass
    # "captions.figure.align=center" changes a nested setting
    target, keys = P, key.split(".")
    for k in keys[:-1]:
        target = target.setdefault(k, {})
    target[keys[-1]] = value

FONT = P.get("font", "Times New Roman")
SIZE = P.get("size", 12)
BODY_LINE = P.get("line", 2.0)
INDENT = P.get("indent", 0.5)
ALIGN = {
    "left": WD_ALIGN_PARAGRAPH.LEFT,
    "center": WD_ALIGN_PARAGRAPH.CENTER,
    "right": WD_ALIGN_PARAGRAPH.RIGHT,
    "justify": WD_ALIGN_PARAGRAPH.JUSTIFY,
}


def set_font(style, name=None, size=None, bold=False, italic=False, caps=False):
    f = style.font
    f.name = name or FONT
    f.size = Pt(size or SIZE)
    f.bold = bold
    f.italic = italic
    f.all_caps = caps
    f.color.rgb = RGBColor(0, 0, 0)
    rpr = style.element.get_or_add_rPr()
    fonts = rpr.find(qn("w:rFonts"))
    if fonts is None:
        fonts = OxmlElement("w:rFonts")
        rpr.insert(0, fonts)
    for attr in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        fonts.set(qn(attr), name or FONT)
    for attr in ("w:asciiTheme", "w:hAnsiTheme", "w:cstheme", "w:eastAsiaTheme"):
        if fonts.get(qn(attr)) is not None:
            del fonts.attrib[qn(attr)]
    # No condensed or kerned type (pandoc's title style has both), and the
    # same size for complex scripts
    for tag in ("w:spacing", "w:kern", "w:w"):
        for el in rpr.findall(qn(tag)):
            rpr.remove(el)
    for el in rpr.findall(qn("w:szCs")):
        el.set(qn("w:val"), str(int((size or SIZE) * 2)))


def set_par(style, align="left", line=None, before=0, after=0, first=None,
            left=None, right=None, hanging=None, keep_next=False, keep_lines=False,
            contextual=False):
    p = style.paragraph_format
    p.alignment = ALIGN[align]
    line = BODY_LINE if line is None else line
    if line == 2.0:
        p.line_spacing_rule = WD_LINE_SPACING.DOUBLE
    elif line == 1.5:
        p.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    else:
        p.line_spacing_rule = WD_LINE_SPACING.SINGLE
    p.space_before = Pt(before)
    p.space_after = Pt(after)
    p.left_indent = Inches(left) if left is not None else Inches(0)
    p.right_indent = Inches(right) if right is not None else Inches(0)
    if hanging is not None:
        p.first_line_indent = Inches(-hanging)
    else:
        p.first_line_indent = Inches(first) if first is not None else Inches(0)
    p.keep_with_next = keep_next
    # pandoc's reference document keeps the lines of an abstract together, which
    # moves a whole abstract to the next page; only headings stay in one piece
    p.keep_together = keep_lines
    p.widow_control = True
    # No space between two paragraphs of this style (the lines of a note)
    ppr = style.element.get_or_add_pPr()
    for el in ppr.findall(qn("w:contextualSpacing")):
        ppr.remove(el)
    if contextual:
        el = OxmlElement("w:contextualSpacing")
        anchor = ppr.find(qn("w:ind"))
        if anchor is None:
            anchor = ppr.find(qn("w:spacing"))
        if anchor is not None:
            anchor.addnext(el)
        elif ppr.find(qn("w:jc")) is not None:
            ppr.find(qn("w:jc")).addprevious(el)
        else:
            ppr.append(el)


def para_style(name, base="Normal"):
    try:
        st = S[name]
    except KeyError:
        st = S.add_style(name, WD_STYLE_TYPE.PARAGRAPH)
        st.base_style = S[base]
        st.quick_style = True
    return st


def apply(style, spec, **defaults):
    """Apply a dict of settings: font keys (font, size, bold, italic, caps) and
    paragraph keys (align, line, before, after, first, left, right, hanging,
    keep_next, keep_lines, contextual)."""
    s = dict(defaults)
    s.update(spec or {})
    # "body" stands for the size or line spacing of the text
    for key in ("size", "line"):
        if s.get(key) == "body":
            s[key] = None
    set_font(style, name=s.get("font"), size=s.get("size"), bold=s.get("bold", False),
             italic=s.get("italic", False), caps=s.get("caps", False))
    set_par(style, align=s.get("align", "left"), line=s.get("line"),
            before=s.get("before", 0), after=s.get("after", 0), first=s.get("first"),
            left=s.get("left"), right=s.get("right"), hanging=s.get("hanging"),
            keep_next=s.get("keep_next", False), keep_lines=s.get("keep_lines", False),
            contextual=s.get("contextual", False))


# Document defaults
rpr_default = d.styles.element.find(qn("w:docDefaults")).find(qn("w:rPrDefault")).find(qn("w:rPr"))
fonts = rpr_default.find(qn("w:rFonts"))
for attr in list(fonts.attrib):
    del fonts.attrib[attr]
for attr in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
    fonts.set(qn(attr), FONT)

# Body text
set_font(S["Normal"]); set_par(S["Normal"])
set_font(S["Body Text"]); set_par(S["Body Text"], first=INDENT, align=P.get("align", "left"))
# (the paragraph that follows a heading)
set_font(S["First Paragraph"])
set_par(S["First Paragraph"], first=P.get("first_paragraph_indent", INDENT), align=P.get("align", "left"))
set_font(S["Compact"]); set_par(S["Compact"])

# Front matter
apply(S["Title"], P.get("title"), align="center")
for name in ("Subtitle", "Author", "Date"):
    apply(S[name], P.get("author"), align="center")
apply(S["Abstract Title"], P.get("abstract_title"), align="center", bold=True, keep_next=True,
      keep_lines=True)
apply(S["Abstract"], P.get("abstract"))
apply(para_style("Keywords"), P.get("keywords"))
apply(para_style("Centered"), P.get("centered"), align="center")
apply(para_style("Front Text"), P.get("front_text"))
apply(para_style("Statement"), P.get("statement"), line=1.0, after=12)
apply(para_style("Float Callout"), P.get("callout"), align="center", before=12, after=12)
apply(para_style("Run-in Paragraph"), P.get("runin"), align=P.get("align", "left"))

# References
apply(S["Bibliography"], P.get("bibliography"), left=0.5, hanging=0.5)

# Headings
H = P["headings"]
for level in range(1, 10):
    spec = H.get(level) or H.get(min(level, max(H)))
    apply(S["Heading %d" % level], spec, keep_next=True, keep_lines=True)

# Quoted text
set_font(S["Block Text"]); set_par(S["Block Text"], left=0.5, right=0.5)

# Hypotheses: indented, with 12 pt above and below; the filter sets the
# label ("H1:") in bold
apply(para_style("Hypothesis"), P.get("hypothesis"), left=0.5, before=12, after=12)

# Display equations: centered, without indentation. (The filter places a
# numbered equation and its number, flush right, in a table without borders.)
# Word puts the extra space of a double-spaced line below the line, so less
# space before the equation than after it gives the same distance on both
# sides.
apply(para_style("Equation"), P.get("equation"), align="center", line=1.0, before=8, after=18)

# Captions
C = P["captions"]
apply(S["Table Caption"], C["table"], keep_next=True)
apply(S["Image Caption"], C["figure"])
apply(S["Caption"], C["table"], keep_next=True)
for name in ("Figure", "Captioned Figure"):
    set_par(S[name], align=C.get("figure_align", "center"), line=1.0,
            before=C.get("figure_before", 0), after=C.get("figure_after", 0),
            keep_next=C.get("figure_keep_next", True))

# The caption of one panel of a figure, "(a) Text", centered below the panel
apply(para_style("Panel Caption"), C.get("panel"), align="center", line=1.0, before=2, after=6,
      keep_next=C.get("figure_keep_next", True))

# Footnotes
apply(S["Footnote Text"], P.get("footnote"), size=10, line=1.0)
fn_size = (P.get("footnote") or {}).get("size", 10)
set_font(S["Footnote Block Text"], size=None if fn_size == "body" else fn_size)
set_par(S["Footnote Block Text"], line=1.0, left=0.5)

# Tables and their notes
# (keep_next holds the rows of a table together on one page)
apply(para_style("Table Text"), P.get("table_text"), size=11, line=1.0, keep_next=True)
# (the paragraphs of one note follow each other without extra space)
apply(para_style("Table Note"), P.get("table_note"), size=10, line=1.0, before=4, after=12,
      contextual=True)

# Links in black without underlining
hl = S["Hyperlink"]
hl.font.color.rgb = RGBColor(0, 0, 0)
hl.font.underline = False

# Table style: rules above and below the header row and below the table.
# (The post-render filter takes single tables and figures out of Quarto's
# layout tables, so these rules fall on data tables.)
tbl = S["Table"].element
for old in tbl.findall(qn("w:tblStylePr")):
    tbl.remove(old)
tblpr = tbl.find(qn("w:tblPr"))
if tblpr is None:
    tblpr = OxmlElement("w:tblPr")
    tbl.append(tblpr)
for tag in ("w:tblBorders", "w:jc"):
    for b in tblpr.findall(qn(tag)):
        tblpr.remove(b)
tbl_borders = OxmlElement("w:tblBorders")
bottom = OxmlElement("w:bottom")
bottom.set(qn("w:val"), "single"); bottom.set(qn("w:sz"), "6"); bottom.set(qn("w:space"), "0"); bottom.set(qn("w:color"), "000000")
tbl_borders.append(bottom)
# CT_TblPrBase order: tblStyle, ..., jc, tblCellSpacing, tblInd, tblBorders, shd, ...
anchor = None
for tag in ("w:shd", "w:tblLayout", "w:tblCellMar", "w:tblLook", "w:tblCaption", "w:tblDescription"):
    anchor = tblpr.find(qn(tag))
    if anchor is not None:
        break
if anchor is not None:
    anchor.addprevious(tbl_borders)
else:
    tblpr.append(tbl_borders)
if P.get("table_align") in ("center", "right"):
    jc = OxmlElement("w:jc")
    jc.set(qn("w:val"), P["table_align"])
    before = None
    for tag in ("w:tblCellSpacing", "w:tblInd", "w:tblBorders"):
        before = tblpr.find(qn(tag))
        if before is not None:
            break
    before.addprevious(jc)
first = OxmlElement("w:tblStylePr"); first.set(qn("w:type"), "firstRow")
tcpr = OxmlElement("w:tcPr"); borders = OxmlElement("w:tcBorders")
for edge in ("top", "bottom"):
    e = OxmlElement(f"w:{edge}")
    e.set(qn("w:val"), "single"); e.set(qn("w:sz"), "6"); e.set(qn("w:space"), "0"); e.set(qn("w:color"), "000000")
    borders.append(e)
tcpr.append(borders); first.append(tcpr)
tbl.append(first)


def add_page_number(paragraph, align):
    """A PAGE field in a header or footer paragraph."""
    paragraph.alignment = ALIGN[align]
    for kind, text in (("begin", None), (None, " PAGE "), ("separate", None), (None, "1"), ("end", None)):
        run = paragraph.add_run()
        run.font.name = FONT
        run.font.size = Pt(SIZE)
        if kind:
            fld = OxmlElement("w:fldChar")
            fld.set(qn("w:fldCharType"), kind)
            run._r.append(fld)
        elif text.strip() == "PAGE":
            instr = OxmlElement("w:instrText")
            instr.set(qn("xml:space"), "preserve")
            instr.text = text
            run._r.append(instr)
        else:
            t = OxmlElement("w:t")
            t.text = text
            run._r.append(t)


# Page: US letter, margins, and page numbers where the journal asks for them
numbers = P.get("page_numbers")
for sec in d.sections:
    sec.page_width, sec.page_height = Inches(8.5), Inches(11)
    for side in ("left_margin", "right_margin", "top_margin", "bottom_margin"):
        setattr(sec, side, Inches(P.get("margins", 1)))
    sec.header_distance = Inches(0.5)
    sec.footer_distance = Inches(0.5)
    if numbers:
        where, align = numbers.split("-")
        part = sec.header if where == "top" else sec.footer
        part.is_linked_to_previous = False
        add_page_number(part.paragraphs[0], align)

# Remove the sample body text so the reference document holds only styles
body = d.element.body
for child in list(body):
    if child.tag != qn("w:sectPr"):
        body.remove(child)
d.core_properties.title = P["doc_title"]
d.core_properties.author = ""
d.save(out)
print("saved", out)
