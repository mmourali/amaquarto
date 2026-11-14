# amaquarto: Quarto Extension for AMA Journals

A [Quarto](https://quarto.org/) extension that formats manuscripts for the journals of the American Marketing Association: *Journal of Marketing*, *Journal of Marketing Research*, *Journal of Public Policy & Marketing*, *Journal of International Marketing*, and *Journal of Interactive Marketing*. One `.qmd` file renders to three outputs:

| Format | Output | Use |
| --- | --- | --- |
| `amaquarto-docx` | Word file | The format AMA asks for |
| `amaquarto-pdf` | PDF typeset with pdfLaTeX | AMA asks authors who write in LaTeX to upload a PDF |
| `amaquarto-latex` | `.tex` source of the PDF | After acceptance, AMA asks LaTeX authors for all LaTeX files. Compile with pdfLaTeX (two runs, or latexmk). Rendering the PDF also keeps this file. |

Version 1.0.0. The formatting follows AMA's [submission guidelines](https://www.ama.org/submission-guidelines-american-marketing-association-journals/), the Word templates and sample documents linked from that page, and AMA's [reference style examples](https://www.ama.org/american-marketing-association-journals-reference-style-examples/).

## Installation

Start a new manuscript from the template:

```bash
quarto use template mmourali/amaquarto
```

Or add the extension to an existing project:

```bash
quarto add mmourali/amaquarto
```

## The files AMA asks for

AMA uses double-anonymized review and asks for at least two files, with an optional third.

| File | Template | Mode |
| --- | --- | --- |
| 1. Title page | `title-page.qmd`, with author details in `_title-page.yml` | `ama-mode: title-page` |
| 2. Main document | `template.qmd` | `ama-mode: manuscript` (the default) |
| 3. Web appendix (optional, a single PDF) | `web-appendix.qmd` | `ama-mode: web-appendix` |

```bash
quarto render template.qmd      # main document: Word, PDF, and .tex
quarto render title-page.qmd    # title page
quarto render web-appendix.qmd  # web appendix
```

**Main document.** US letter, 1-inch margins, Times New Roman 12 point, double spaced, left justified, with no page numbers, headers, or footers. Page 1 holds the title, the abstract, and the keywords; the text begins on page 2; the references begin on a new page; and each appendix begins on a new page after the references. The main document names no authors.

**Title page.** The title; one line for each author with name, position, institution, address, telephone, and e-mail address; the corresponding author; author notes; acknowledgments; and the statements and declarations (ethical considerations, consent to participate, declaration of conflicting interest, funding, and data availability). All of it is entered in `_title-page.yml`.

**Web appendix.** The first page shows the words "Web Appendix," the title, a table of contents with page numbers (when there are several sections), and AMA's disclosure sentence. Each section ("Web Appendix A: ...") begins on a new page; tables, figures, and equations are numbered W1, W2, and so on; and pages are numbered from 1. In Word, the table of contents is a field: right-click it and choose Update Field.

**After acceptance.** AMA asks for a main document that includes the title page. Add two lines to `template.qmd`:

```yaml
anonymous: false
metadata-files: [_title-page.yml]
```

**Article mode** (`ama-mode: article`, PDF and `.tex` only) is a publication-style preview for sharing drafts: 11-point type, 1.15 line spacing, and page numbers. It is not a submission format.

## Options

| Field | What the extension does |
| --- | --- |
| `title` | Printed centered and bold. Warns above 25 words. |
| `abstract` | Printed under "Abstract." Warns above 200 words. AMA asks for the third person. |
| `keywords` | Printed after the abstract with an italic *Keywords* label. Warns above 8. |
| `ama-mode` | `manuscript` (default), `title-page`, `web-appendix`, or `article` |
| `policy-contribution-statement` | *Journal of Public Policy & Marketing* only. Printed on the first page under the title; the abstract and keywords follow on the next page, as in the journal's template. Warns above 300 words. |
| `anonymous` | `true` (default). `false` prints the title page before the main document, and the authors on the first page of a web appendix. |
| `ama-floats` | `inline` (default) leaves tables and figures in the text, as AMA asks. `end` moves each to a separate page after the references and marks its place in the text. |
| `ama-footnotes` | `page` (default) or `end` (a "Footnotes" page after the references) |
| `ama-reference-spacing` | `double` (default) or `single`, in the PDF and `.tex` outputs. AMA allows single-spaced references. |
| `ama-note-label` | Replaces the "Notes:" label of table and figure notes |
| `ama-toc` | `false` leaves out the table of contents of a web appendix |

The older option `pdf-format`, which chose the PDF layout, still works.

## Text

**Headings.** AMA uses up to three levels and does not number headings. `#` is a primary heading (centered, bold, with an extra return before and after), `##` a secondary heading (flush left, bold italic), and `###` a tertiary heading (flush left, italic, on its own line). Type primary and secondary headings in title case and tertiary headings in sentence case. The render warns about a fourth level, about a section with a single secondary or tertiary heading, and about an opening "Introduction" heading, which AMA's sample document does not use.

**Hypotheses.** Write each hypothesis in a `hypothesis` div. It is indented, with space above and below, and its label (the words up to the first colon) is set in bold.

```markdown
::: {.hypothesis}
H~1~: Trust in an influencer increases loyalty to the brands that the
influencer endorses.
:::
```

**Equations.** Display equations are centered, with the number in parentheses at the right margin. In the text, `@eq-model` prints "Equation 1."

**Footnotes.** AMA asks authors to use footnotes sparingly: no more than 10, each of 40 words or fewer. The render warns about both. Footnotes are set in the 12-point type of the text, single spaced, as in AMA's Word template.

## Tables and figures

Type each title in title case, without a number, and give the table or figure a label. The extension prints "Table 1: Title." and "Figure 1: Title." centered above the table or figure, as in AMA's sample document, and adds the period if you leave it out. In the text, `@tbl-descriptives` prints "Table 1" and `@fig-loyalty` prints "Figure 1."

```markdown
| Variable         | M    | SD   |
|:-----------------|-----:|-----:|
| Brand loyalty^a^ | 4.21 | 1.02 |
| Influencer trust | 4.56 |  .89 |

: Loyalty and Trust Are Above the Scale Midpoint {#tbl-descriptives}

::: {.notes}
^a^Average of four items.

All variables were measured on seven-point scales.
:::
```

Write notes in a `notes` div directly after the table or figure (the older `table-notes` class also works). The extension adds the italic "Notes:" label to the first paragraph that is not a lettered note and sets notes single spaced and flush left. Tables are single spaced, with rules above and below the column heads and below the table, and their column heads are set in bold, as in AMA's Word template.

An image path written without an extension uses the `.pdf` file in the PDF and `.tex` outputs and the `.png` file in Word. The template's figure is drawn with R (ggplot2); delete that chunk if you do not use R.

**Word output.** Each table is a native Word table, centered, with column widths that fit its contents and its column heads in bold, as in AMA's Word template. The alignment is written into the table itself, so it does not depend on the program that opens the file. (A table that holds citations, footnotes, images, or web links is written by pandoc in the ordinary way and takes its alignment from the table style of the reference document.) A numbered equation and its number are placed in a table without borders, the equation in the middle cell and the number in the right cell, so that the number stands at the right margin. An equation without a number is centered in a paragraph of its own. A table or figure without a note is followed by 12 points of space, because Word otherwise sets the next paragraph directly against it.

**Labels and column widths.** A table or figure that has a title but no label is printed without a number, in every output, and the render warns; a table without a title takes no number either. In a pipe table whose lines are long, the number of dashes under each column head sets that column's share of the width. If a share is too small for the longest word of its column, the extension sets the widths from the contents instead, so that no word is broken in the middle.

**Figures and tables with panels.** Quarto's layout options set several pictures in one figure. Give the figure a label; give each panel a caption and, if the text cites single panels, a label of its own:

```markdown
::: {#fig-studies layout-ncol=2}
![Study 1](study1.png){#fig-study1}

![Study 2](study2.png){#fig-study2}

Purchase intention by condition
:::
```

All three outputs set the panels side by side, each with its caption, "(a) Study 1," centered above it, and `@fig-study1` prints "Figure 1a." In Word the panels stand in a table without borders. A table with several parts (a `#tbl-` div with a layout option that holds one table for each part) is set the same way, and so are the plots of a code chunk with `layout-ncol` and `fig-subcap`.

**Page breaks and tables from code.** A table that fits on a page is kept on one page with its title and its note, and a note stays on the page of its figure. Tables that a code chunk writes (with `knitr::kable()`, for example) are treated like tables typed in Markdown, bold column heads included. If a chunk writes its table as a LaTeX `table` environment, as `kableExtra` and `modelsummary` can, the extension sets it where it is written and formats its title and note; the layout inside the table is the package's own.

## Appendixes, citations, and references

**Appendixes.** Give each appendix heading the `appendix` class. Appendixes follow the references, each on a new page, and their tables, figures, and equations are numbered A1, A2 (B1, B2 in Appendix B). Label a single appendix "Appendix."

```markdown
# Appendix A: Survey Items {.appendix}
```

**Citations.** `[@lafreniere2022]` prints (Lafreniere, Moore, and Fisher 2022); works with four or more authors are cited with "et al."; a page is cited as `[@thorelli1960, p. 112]`; and several citations are listed alphabetically and separated by semicolons.

**References.** End the main document with the reference list, which begins on a new page. If you leave it out, the extension adds it.

```markdown
# References

::: {#refs}
:::
```

`american-marketing-association.csl` is the Zotero AMA style, edited to match AMA's current reference examples (the edits are listed at the top of the file): titles in headline-style capitals, up to 20 authors, abbreviated page ranges (908–25), books without a place of publication, chapters with the editors after the book title, and "(published online Month Day)" with the DOI for articles in advance. Five practical points: wrap a word in braces in the `.bib` file to protect its capitalization (`{Twitter}`); wrap an institution that contains "and" in double braces; give a dissertation its type (`type = {doctoral dissertation}`); give a forthcoming article `year = {forthcoming}` and no volume, and, once it is published online, its `date` and `doi` instead; and enter a working paper as `@unpublished` with `note = {working paper, University}`.

## Checks during rendering

The render warns when the title exceeds 25 words; the abstract exceeds 200 words; there are more than 8 keywords; there are more than 10 footnotes, or a footnote exceeds 40 words; there are more than three levels of headings; a section has a single secondary or tertiary heading; the text opens with an "Introduction" heading; the policy contribution statement exceeds 300 words; or an appendix comes before the references. It cannot check the 50-page limit or the anonymity of the main document.

## Files

| File | Role |
| --- | --- |
| `_extensions/amaquarto/_extension.yml` | The three formats and their settings |
| `_extensions/amaquarto/amaquarto.lua` | Front matter, title page, web appendix, notes, hypotheses, appendixes, page breaks, and the checks |
| `_extensions/amaquarto/amaquarto-post.lua` | Captions, Word tables, and the W and A numbers in Word (it runs after Quarto has numbered tables and figures) |
| `_extensions/amaquarto/ama-header.tex` | LaTeX preamble: fonts, spacing, headings, captions, notes |
| `_extensions/amaquarto/ama-reference.docx` | Word styles |
| `_extensions/amaquarto/american-marketing-association.csl` | Reference style |
| `_extensions/amaquarto/tools/build_reference_docx.py` | Rebuilds the Word reference document (requires Python and python-docx) |
| `template.qmd`, `bibliography.bib` | Main document template and its references |
| `title-page.qmd`, `_title-page.yml` | Title page template and the author details |
| `web-appendix.qmd` | Web appendix template |

## Requirements

Quarto 1.4 or later (tested with Quarto 1.4.557, 1.5.57, and 1.11.9; the Word output was checked in Microsoft Word for Mac) and a TeX distribution with pdfLaTeX. The PDF and `.tex` outputs use the `mathptmx` (Times) and `helvet` packages, which come with TeX Live and TinyTeX; the Word output takes Times New Roman from `ama-reference.docx`.

Greek letters and common mathematical signs can be typed as characters (α, χ², ≤, ≠, −, ×, →, ✓). In the PDF and `.tex` outputs, which pdfLaTeX typesets, Greek letters stand upright in the text, as they do in the Word file. pdfLaTeX has no type for other scripts (Cyrillic, Chinese, Arabic) or for a letter with a combining accent (a mean typed as an x followed by a combining macron); write such symbols as math, `$\bar{x}$`. The Word output takes any character.

## Resources

- [AMA submission guidelines](https://www.ama.org/submission-guidelines-american-marketing-association-journals/) (the Word and LaTeX templates are linked there)
- [AMA reference style examples](https://www.ama.org/american-marketing-association-journals-reference-style-examples/)

## License

The CSL file is derived from the [American Marketing Association](https://www.zotero.org/styles/american-marketing-association) style, licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). All other files are available under the [MIT License](LICENSE).
