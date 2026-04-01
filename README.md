# amaquarto: A Quarto Extension for AMA Journal Submissions

A [Quarto](https://quarto.org/) extension for formatting manuscripts for submission to journals published by the [American Marketing Association](https://www.ama.org/ama-academic-journals/) (AMA), including the *Journal of Marketing* (JM), *Journal of Marketing Research* (JMR), and *Journal of Public Policy & Marketing* (JPPM).

This extension produces DOCX and PDF output from the same Quarto source files. The DOCX format conforms to the [AMA Submission Guidelines](https://www.ama.org/submission-guidelines-american-marketing-association-journals/) for peer review. The PDF format offers two layout options controlled by the `pdf-format` YAML option: `article` (single-column publication style) and `manuscript` (single-column submission style matching the DOCX format).

## Features

- **DOCX output** for submission: 12pt Times New Roman, double-spaced, 1-inch margins, no page numbers (per AMA guidelines)
- **Two PDF layout options** controlled by `pdf-format`:
  - `article` (default): Single-column publication-style layout (11pt body, centered page numbers, bold italic headings, author footnote)
  - `manuscript`: Single-column submission-style layout matching the DOCX format (12pt, double-spaced, 1-inch margins, no running headers)
- AMA-style heading hierarchy (three levels, no section numbering)
  - DOCX and manuscript PDF: H1 centered bold; H2 flush left, bold italic; H3 left, italic
  - Article PDF: H1 large bold italic; H2 bold italic; H3 italic
- Table titles above, figure titles below (AMA standard placement)
- Table/figure notes via `.table-notes` div
- Appendix page breaks via `.appendix` class on headers
- AMA citation style via the official CSL file (author-date format)
- References hanging indent (0.5 inch)
- Custom DOCX reference document with all AMA paragraph styles pre-configured
- Lua filter with automated checks for AMA compliance:
  - Abstract word count (200-word limit)
  - Title word count (25-word limit)
  - Keyword count (8-keyword limit)
  - Footnote count (10-footnote limit) and word count (40-word limit per footnote)
  - Warning if the opening section is labeled "Introduction"
  - Warning if more than three heading levels are used
  - Automatic page break before references (all formats)
- Optional JPPM Policy Contribution Statement (validated to 300-word limit)
- Separate templates for the three required submission files:
  1. Title page (with author info, declarations, and acknowledgments)
  2. Main document (anonymized for double-blind review)
  3. Web appendix (optional, with W-prefixed tables/figures/equations)

## Installation

### Using the Template (Recommended for New Projects)

```bash
quarto use template mmourali/amaquarto
```

This will create a new directory with the template files and the extension.

### Using R

```r
quarto::quarto_use_template("mmourali/amaquarto")
```

### Adding to an Existing Project

```bash
quarto add mmourali/amaquarto
```

Then add the format to your document's YAML header:
```yaml
format:
  amaquarto-docx: default
  amaquarto-pdf: default
```

## Usage

The extension provides three template files corresponding to the three files required for AMA journal submissions.

### File 1: Title Page (`title-page.qmd`)

Contains author names, affiliations, contact information, acknowledgments, and statements/declarations (ethics, conflicts of interest, funding, data availability). This file is **not anonymized**.

### File 2: Main Document (`template.qmd`)

Contains the title, abstract, keywords, main text, references, and appendices. This file is **anonymized** for double-blind peer review; no author-identifying information should appear here.

### File 3: Web Appendix (`web-appendix.qmd`)

Optional. Contains supplementary materials (e.g., robustness checks, additional analyses, stimuli). Tables, figures, and equations use the "W" prefix (Table W1, Figure W1, Equation W1). The web appendix does not count toward the 50-page limit and is uploaded as a separate PDF.

### Rendering

```bash
quarto render template.qmd
quarto render title-page.qmd
quarto render web-appendix.qmd
```

### YAML Options

```yaml
---
title: "Your Manuscript Title"
author:
  - name: First Author
    email: first@university.edu
    affiliations:
      - name: University Name
    attributes:
      corresponding: true
  - name: Second Author
    affiliations:
      - name: Another University
author-note: >
  First Author is Professor of Marketing, Department Name, University Name
  (email: first@university.edu). Corresponding author.
anonymous: true          # Set to false to show authors in the article PDF
abstract: |
  Your abstract text here, written in third person.
keywords:
  - keyword one
  - keyword two
format:
  amaquarto-docx: default
  amaquarto-pdf:
    pdf-format: article  # "article" or "manuscript"
bibliography: bibliography.bib
---
```

The DOCX output conforms to AMA submission guidelines (12pt Times New Roman, double-spaced, 1-inch margins, no page numbers). Author information is automatically suppressed in DOCX output (it belongs on the separate title page file).

The PDF output supports two layout options via `pdf-format`:

- **`article`** (default): Single-column publication-style layout (11pt body, centered page numbers, bold italic headings). By default anonymous (`anonymous: true`); set `anonymous: false` to render author names and the author-note footnote.
- **`manuscript`**: Single-column submission-style layout matching the DOCX output (12pt, double-spaced, 1-inch margins). Useful when a PDF version of the submission is needed.

### JPPM: Policy Contribution Statement

Submissions to the *Journal of Public Policy & Marketing* must include a Policy Contribution Statement. Add the `policy-contribution-statement` field to the YAML header:

```yaml
policy-contribution-statement: |
  Succinctly articulate (1) the policy conversation, (2) how the manuscript
  moves understanding beyond existing literature, and (3) what specific
  policy stakeholders might be impacted. Max 300 words.
```

## AMA Formatting Quick Reference

### Headings

```markdown
# Primary Heading
## Secondary Heading
### Tertiary heading
```

Use title-style capitalization for H1 and H2; sentence-style for H3. Do not use more than three levels. Do not label the opening section as "Introduction."

### Tables and Figures

Place tables and figures within the text (not at the end). Number them consecutively. Use descriptive titles that reflect the takeaway. Table titles appear above the table; figure titles appear below the figure.

Report actual *p*-values (three digits) rather than asterisk thresholds. Include standard errors in tables. Use Arial font in figures where possible. Label axes and include error bars.

Use the `.table-notes` div for notes below tables or figures:

```markdown
| Column A | Column B |
|----------|----------|
| 1        | 2        |

: Descriptive Title Reflecting the Takeaway. {#tbl-example}

::: {.table-notes}
*Notes.* Standard errors in parentheses. All *p*-values reported to
three decimal places.
:::
```

### Appendixes

Use the `.appendix` class on an H1 header to auto-insert a page break:

```markdown
# Appendix A: Stimuli {.appendix}

Content of the appendix...
```

### Citations

```markdown
Prior research demonstrates this effect [@smith2023].
Smith (2023) found that...
Multiple citations are alphabetical [@adams2020; @baker2021; @chen2022].
```

### Footnotes

Use sparingly (no more than 10, max 40 words each):

```markdown
This is a claim.[^fn1]

[^fn1]: A concise footnote not exceeding 40 words.
```

## Font Configuration

The extension uses pdfLaTeX with the `newtxtext` (Times) and `newtxmath` packages. No system fonts or additional font packages are required.

## Resources

- [AMA Submission Guidelines](https://www.ama.org/submission-guidelines-american-marketing-association-journals/)
- [AMA Reference Style Examples](https://www.ama.org/american-marketing-association-journals-reference-style-examples/)
- [AMA Editorial Policies and Procedures](https://www.ama.org/ama-journals-editorial-policies-procedures/)
- [AMA Research Transparency Policy](https://www.ama.org/research-transparency-policy/)
- [Change in JM's Policy for Reporting Results (2025)](https://www.ama.org/2025/02/11/change-in-journal-of-marketings-policy-for-reporting-results/)

## License

The CSL file is licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) by the Citation Style Language project. All other files in this extension are available under the [MIT License](LICENSE).
