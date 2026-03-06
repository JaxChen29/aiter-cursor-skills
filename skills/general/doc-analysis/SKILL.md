---
name: doc-analysis
description: Parse documents (PDF, markdown, code files) and produce structured tech reports. Use when the user wants to read a PDF paper or spec, analyze source code, summarize technical documents, or export findings as a markdown report, PDF, or PowerPoint presentation.
---

# Document Analysis and Tech Report Export

## Overview

Read input documents, extract and analyze content, then export a structured tech report.
Supports PDF papers/specs, markdown docs, and source code files as input.
Outputs markdown (always), and optionally PDF or PPTX.

## Step 1: Detect Input Type and Extract Content

### PDF files

```python
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    full_text = ""
    tables = []
    for page in pdf.pages:
        full_text += page.extract_text() or ""
        full_text += "\n\n"
        for table in page.extract_tables():
            tables.append(table)
```

For scanned PDFs (no extractable text), fall back to OCR:

```python
from pdf2image import convert_from_path
import pytesseract

images = convert_from_path("scanned.pdf")
text = "\n\n".join(pytesseract.image_to_string(img) for img in images)
```

Use `pypdf` for metadata:

```python
from pypdf import PdfReader
meta = PdfReader("document.pdf").metadata
# meta.title, meta.author, meta.subject
```

### Markdown files

Read directly. Parse headings to build a section tree for the report structure.

### Code files

Read the source files. Identify structure (classes, functions, key data structures).
Focus on: public API, architecture patterns, dependencies, and non-obvious logic.

## Step 2: Analyze and Structure

Organize extracted content into a report outline. Choose the template that best fits the input.

### Template A: Technical Paper Summary

Use for academic papers, conference papers, arXiv preprints.

```markdown
# [Paper Title]

## Metadata
- **Authors:** ...
- **Published:** ...
- **Source:** ...

## Executive Summary
[2-3 sentence overview of the paper's contribution]

## Problem Statement
[What problem does the paper address?]

## Approach
[Key technical ideas, algorithms, or methods]

## Key Results
[Main experimental findings, benchmarks, comparisons]

## Architecture / Design
[System design, model architecture, or algorithm structure]

## Strengths and Limitations
[Critical assessment]

## Relevance to Our Work
[How this relates to aiter / kernel development]
```

### Template B: Spec / Reference Summary

Use for hardware specs, ISA manuals, API documentation.

```markdown
# [Document Title] -- Technical Summary

## Overview
[What this spec covers]

## Key Specifications
| Parameter | Value | Notes |
|-----------|-------|-------|
| ...       | ...   | ...   |

## Architecture
[Block diagrams, data flow, key components]

## Important Details
[Constraints, edge cases, gotchas]

## Actionable Items
[What we need to do based on this spec]
```

### Template C: Code Analysis Report

Use for source code review, architecture analysis.

```markdown
# Code Analysis: [Component/Module Name]

## Overview
[What the code does, its role in the system]

## Architecture
[Module structure, key classes/functions, data flow]

## Key Implementation Details
[Non-obvious logic, algorithms, performance considerations]

## Dependencies
[External libraries, internal modules]

## Potential Issues
[Bugs, tech debt, performance bottlenecks, security concerns]

## Recommendations
[Suggested improvements, refactoring opportunities]
```

## Step 3: Export

### Markdown (always produced first)

Write the report as a `.md` file. This is the primary output.

### PDF export

Use `reportlab` Platypus for structured PDF output:

```python
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib import colors

def export_pdf(sections, output_path):
    doc = SimpleDocTemplate(output_path, pagesize=letter)
    styles = getSampleStyleSheet()
    story = []

    for section in sections:
        story.append(Paragraph(section["title"], styles["Heading1"]))
        story.append(Spacer(1, 12))
        story.append(Paragraph(section["body"], styles["Normal"]))
        story.append(Spacer(1, 20))

    doc.build(story)
```

For tables in the PDF:

```python
from reportlab.platypus import Table, TableStyle
from reportlab.lib import colors

def make_table(data):
    t = Table(data)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.grey),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
        ("GRID", (0, 0), (-1, -1), 1, colors.black),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
    ]))
    return t
```

**Important:** Never use Unicode subscript/superscript characters in reportlab. Use `<sub>` and `<super>` tags in Paragraph objects instead.

For a simpler approach, convert markdown to PDF via HTML:

```bash
pip install weasyprint
```

```python
import markdown
from weasyprint import HTML

md_content = open("report.md").read()
html = markdown.markdown(md_content, extensions=["tables", "fenced_code"])
html_doc = f"<html><body>{html}</body></html>"
HTML(string=html_doc).write_pdf("report.pdf")
```

### PPTX export

Use `python-pptx` to generate slides from report sections:

```python
from pptx import Presentation
from pptx.util import Inches, Pt

def export_pptx(sections, output_path):
    prs = Presentation()

    # Title slide
    slide = prs.slides.add_slide(prs.slide_layouts[0])
    slide.shapes.title.text = sections[0]["title"]
    slide.placeholders[1].text = "Generated Tech Report"

    # Content slides (one per section)
    for section in sections[1:]:
        slide = prs.slides.add_slide(prs.slide_layouts[1])
        slide.shapes.title.text = section["title"]
        body = slide.placeholders[1]
        tf = body.text_frame
        tf.text = section["body"][:500]  # truncate long sections

        # Add bullet points if section has a list
        for point in section.get("bullets", []):
            p = tf.add_paragraph()
            p.text = point
            p.level = 1

    prs.save(output_path)
```

For table slides:

```python
from pptx.util import Inches

def add_table_slide(prs, title, headers, rows):
    slide = prs.slides.add_slide(prs.slide_layouts[5])  # blank layout
    slide.shapes.title.text = title

    n_rows = len(rows) + 1
    n_cols = len(headers)
    table_shape = slide.shapes.add_table(n_rows, n_cols, Inches(0.5), Inches(1.5), Inches(9), Inches(5))
    table = table_shape.table

    for i, h in enumerate(headers):
        table.cell(0, i).text = h
    for r, row in enumerate(rows):
        for c, val in enumerate(row):
            table.cell(r + 1, c).text = str(val)
```

## Workflow Summary

```
1. User provides document(s) (PDF path, markdown path, or code files)
2. Detect type, extract text/tables/metadata
3. Choose report template (paper summary / spec summary / code analysis)
4. Generate structured markdown report
5. If requested: export to PDF and/or PPTX
```

## Dependencies

Install as needed:

```bash
pip install pdfplumber pypdf reportlab python-pptx
pip install weasyprint markdown   # for MD->PDF via HTML
pip install pytesseract pdf2image # for scanned PDF OCR (requires tesseract system package)
```

## Additional Resources

For detailed library API examples, see [reference.md](reference.md).
