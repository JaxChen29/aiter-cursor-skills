# Document Analysis -- Library Reference

## pdfplumber (PDF text and table extraction)

### Extract text with layout

```python
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()
        print(text)
```

### Extract tables as DataFrames

```python
import pandas as pd
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    all_tables = []
    for page in pdf.pages:
        for table in page.extract_tables():
            if table:
                df = pd.DataFrame(table[1:], columns=table[0])
                all_tables.append(df)
    if all_tables:
        combined = pd.concat(all_tables, ignore_index=True)
```

### Extract specific page range

```python
with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages[2:5]:  # pages 3-5 (0-indexed)
        text = page.extract_text()
```

---

## pypdf (PDF metadata, merge, split)

### Read metadata

```python
from pypdf import PdfReader

reader = PdfReader("document.pdf")
meta = reader.metadata
print(f"Title: {meta.title}")
print(f"Author: {meta.author}")
print(f"Pages: {len(reader.pages)}")
```

### Merge PDFs

```python
from pypdf import PdfWriter, PdfReader

writer = PdfWriter()
for pdf_file in ["doc1.pdf", "doc2.pdf"]:
    reader = PdfReader(pdf_file)
    for page in reader.pages:
        writer.add_page(page)
with open("merged.pdf", "wb") as f:
    writer.write(f)
```

### Split PDF

```python
reader = PdfReader("input.pdf")
for i, page in enumerate(reader.pages):
    writer = PdfWriter()
    writer.add_page(page)
    with open(f"page_{i+1}.pdf", "wb") as f:
        writer.write(f)
```

### Password protection

```python
writer = PdfWriter()
for page in PdfReader("input.pdf").pages:
    writer.add_page(page)
writer.encrypt("userpass", "ownerpass")
with open("encrypted.pdf", "wb") as f:
    writer.write(f)
```

---

## reportlab (PDF creation)

### Simple document with Platypus

```python
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet

doc = SimpleDocTemplate("report.pdf", pagesize=letter)
styles = getSampleStyleSheet()
story = []

story.append(Paragraph("Report Title", styles["Title"]))
story.append(Spacer(1, 12))
story.append(Paragraph("Body text goes here. " * 20, styles["Normal"]))
story.append(PageBreak())
story.append(Paragraph("Page 2", styles["Heading1"]))
story.append(Paragraph("More content.", styles["Normal"]))

doc.build(story)
```

### Tables

```python
from reportlab.platypus import Table, TableStyle
from reportlab.lib import colors

data = [
    ["Header 1", "Header 2", "Header 3"],
    ["Row 1 Col 1", "Row 1 Col 2", "Row 1 Col 3"],
    ["Row 2 Col 1", "Row 2 Col 2", "Row 2 Col 3"],
]

t = Table(data)
t.setStyle(TableStyle([
    ("BACKGROUND", (0, 0), (-1, 0), colors.grey),
    ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
    ("ALIGN", (0, 0), (-1, -1), "CENTER"),
    ("GRID", (0, 0), (-1, -1), 1, colors.black),
    ("FONTSIZE", (0, 0), (-1, -1), 9),
    ("BOTTOMPADDING", (0, 0), (-1, 0), 12),
]))
```

### Subscripts and superscripts

Never use Unicode subscript/superscript characters in reportlab -- they render as black boxes.
Use XML tags in Paragraph objects:

```python
chemical = Paragraph("H<sub>2</sub>O", styles["Normal"])
squared = Paragraph("x<super>2</super> + y<super>2</super>", styles["Normal"])
```

---

## python-pptx (PowerPoint creation)

### Basic presentation

```python
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()

# Title slide
slide = prs.slides.add_slide(prs.slide_layouts[0])
slide.shapes.title.text = "Presentation Title"
slide.placeholders[1].text = "Subtitle or author"

# Content slide with bullets
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Section Title"
body = slide.placeholders[1].text_frame
body.text = "First bullet point"
p = body.add_paragraph()
p.text = "Second bullet point"
p.level = 0
p = body.add_paragraph()
p.text = "Sub-bullet"
p.level = 1

prs.save("output.pptx")
```

### Add a table

```python
from pptx.util import Inches

slide = prs.slides.add_slide(prs.slide_layouts[5])  # blank
slide.shapes.title.text = "Data Table"

rows, cols = 4, 3
table_shape = slide.shapes.add_table(rows, cols, Inches(0.5), Inches(1.5), Inches(9), Inches(4))
table = table_shape.table

headers = ["Name", "Value", "Unit"]
for i, h in enumerate(headers):
    table.cell(0, i).text = h

data = [["Clock", "2100", "MHz"], ["Memory", "128", "GB"], ["TDP", "750", "W"]]
for r, row in enumerate(data):
    for c, val in enumerate(row):
        table.cell(r + 1, c).text = val
```

### Add an image

```python
slide = prs.slides.add_slide(prs.slide_layouts[5])
slide.shapes.add_picture("diagram.png", Inches(1), Inches(1), width=Inches(8))
```

### Slide layouts reference

| Index | Layout Name | Use For |
|-------|-------------|---------|
| 0 | Title Slide | First slide |
| 1 | Title and Content | Standard content with bullets |
| 2 | Section Header | Section dividers |
| 5 | Blank | Tables, images, custom layout |
| 6 | Title Only | Slide with just a title bar |

---

## weasyprint (Markdown to PDF via HTML)

```python
import markdown
from weasyprint import HTML

md_text = open("report.md").read()
html_body = markdown.markdown(md_text, extensions=["tables", "fenced_code"])
styled_html = f"""
<html><head><style>
body {{ font-family: sans-serif; margin: 40px; line-height: 1.6; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border: 1px solid #ccc; padding: 8px; text-align: left; }}
th {{ background: #f0f0f0; }}
code {{ background: #f5f5f5; padding: 2px 6px; border-radius: 3px; }}
pre {{ background: #f5f5f5; padding: 12px; border-radius: 4px; overflow-x: auto; }}
</style></head><body>{html_body}</body></html>
"""
HTML(string=styled_html).write_pdf("report.pdf")
```

---

## OCR for scanned PDFs

Requires `tesseract` system package and Python bindings:

```bash
# System package (Ubuntu/Debian)
sudo apt install tesseract-ocr

# Python packages
pip install pytesseract pdf2image
```

```python
from pdf2image import convert_from_path
import pytesseract

images = convert_from_path("scanned.pdf", dpi=300)
for i, img in enumerate(images):
    text = pytesseract.image_to_string(img)
    print(f"--- Page {i+1} ---")
    print(text)
```

---

## Command-line alternatives

```bash
# Extract text preserving layout (poppler-utils)
pdftotext -layout input.pdf output.txt

# Extract specific pages
pdftotext -f 1 -l 5 input.pdf output.txt

# Merge PDFs (qpdf)
qpdf --empty --pages file1.pdf file2.pdf -- merged.pdf

# Extract images (poppler-utils)
pdfimages -j input.pdf output_prefix
```
