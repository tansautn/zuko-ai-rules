---
name: cheatsheet-generator
description: >
  Generate structured, well-formatted Excel (.xlsx) cheatsheets for any technical topic,
  configuration, API, tool, framework, or concept. Use this skill whenever the user asks
  to "create a cheatsheet", "make a reference sheet", "summarize X into a spreadsheet",
  "generate a cheat sheet for X", or wants to organize technical documentation into a
  scannable tabular format. Also trigger when user says things like "tạo cheatsheet",
  "làm bảng tóm tắt", "reference sheet cho X", or asks to export structured knowledge
  to Excel. Works with any subject: CLI flags, config options, API endpoints, language
  syntax, keyboard shortcuts, regex patterns, design patterns, etc.
---

# Cheatsheet Generator Skill

Generates a structured, formatted `.xlsx` cheatsheet for any topic by:
1. Resolving the information source (web search or user-provided)
2. Synthesizing and categorizing the content
3. Producing a professional Excel file with multiple sheets

---

## Step 1: Resolve Information Source

### If topic is well-known / searchable:
- Use `web_search` to gather authoritative information
- Search for: official docs, reference pages, man pages, specification pages
- Aim for 3–5 reliable sources, then synthesize

### If topic is obscure, private, or user-specific:
- Ask the user: *"Could you paste the relevant documentation, config file, or description so I can build the cheatsheet from it?"*
- Accept pasted text, uploaded files, or URLs

### Source quality priority:
1. Official documentation / spec pages
2. GitHub READMEs / wikis
3. Reputable tech blogs / Stack Overflow (for examples)

---

## Step 2: Analyze & Categorize Content

After gathering info, identify the **content type** and apply the matching taxonomy:

### Content Type → Category Schema

| Content Type | Categories to Extract |
|---|---|
| **Config / Settings** | Parameter name, Default value, Allowed values/types, Effect/purpose, Notes |
| **CLI / Commands** | Command, Flags/Options, Arguments, Description, Example usage |
| **API / Endpoints** | Method, Endpoint, Parameters, Response, Auth required, Example |
| **Language Syntax** | Construct, Syntax, Description, Example, Common mistakes |
| **Keyboard Shortcuts** | Action, Shortcut (Win/Linux), Shortcut (Mac), Context/Mode |
| **Regex / Patterns** | Pattern, Matches, Does not match, Use case |
| **Concepts / Theory** | Term, Definition, Related terms, Example, Notes |
| **Design Patterns** | Pattern name, Category, Problem solved, Structure, When to use |

For **mixed** content, combine relevant categories. When unsure, use:
- Column 1: **Name / Key**
- Column 2: **Type / Category**
- Column 3: **Value / Syntax**
- Column 4: **Description / Meaning**
- Column 5: **Example**
- Column 6: **Notes**

---

## Step 3: Generate Excel File

Use `openpyxl` with the styling conventions below.

### Sheet Structure

**Single-topic cheatsheet** (< 50 rows of one type):
- One main sheet named after the topic
- Optional: `README` sheet with source links and description

**Multi-category cheatsheet** (50+ rows or 3+ distinct categories):
- `Index` sheet: table of contents with hyperlinks to each sheet
- One sheet per major category
- Sheet names: short, PascalCase or Title Case

### Python Script Template

```python
from openpyxl import Workbook
from openpyxl.styles import (
    Font, PatternFill, Alignment, Border, Side, GradientFill
)
from openpyxl.utils import get_column_letter
from openpyxl.styles.numbers import FORMAT_TEXT

COLORS = {
    'header_bg': '1E3A5F',      # Dark navy
    'header_fg': 'FFFFFF',      # White
    'subheader_bg': '2E86AB',   # Mid blue
    'subheader_fg': 'FFFFFF',
    'alt_row': 'EBF5FB',        # Light blue tint
    'white': 'FFFFFF',
    'border': 'BDC3C7',
    'index_bg': '2C3E50',
    'accent': 'E74C3C',         # Red accent for important cells
    'note': 'F39C12',           # Orange for notes/warnings
}

def make_border(color=COLORS['border']):
    side = Side(style='thin', color=color)
    return Border(left=side, right=side, top=side, bottom=side)

def style_header(cell, bg=COLORS['header_bg'], fg=COLORS['header_fg'], size=11):
    cell.font = Font(bold=True, color=fg, size=size, name='Calibri')
    cell.fill = PatternFill('solid', start_color=bg)
    cell.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
    cell.border = make_border()

def style_data(cell, row_idx, wrap=True):
    bg = COLORS['alt_row'] if row_idx % 2 == 0 else COLORS['white']
    cell.fill = PatternFill('solid', start_color=bg)
    cell.alignment = Alignment(vertical='top', wrap_text=wrap)
    cell.border = make_border()
    cell.font = Font(name='Calibri', size=10)

def auto_fit_columns(sheet, min_width=10, max_width=60):
    for col in sheet.columns:
        max_len = 0
        col_letter = get_column_letter(col[0].column)
        for cell in col:
            try:
                if cell.value:
                    max_len = max(max_len, len(str(cell.value)))
            except Exception:
                pass
        sheet.column_dimensions[col_letter].width = min(max(max_len + 2, min_width), max_width)

def write_cheatsheet_sheet(sheet, title, columns, rows):
    """
    columns: list of str (header names)
    rows: list of list (data rows)
    """
    sheet.freeze_panes = 'A2'

    # Header row
    for col_idx, col_name in enumerate(columns, 1):
        cell = sheet.cell(row=1, column=col_idx, value=col_name)
        style_header(cell)

    # Data rows
    for row_idx, row_data in enumerate(rows, 2):
        for col_idx, value in enumerate(row_data, 1):
            cell = sheet.cell(row=row_idx, column=col_idx, value=value)
            style_data(cell, row_idx)

    auto_fit_columns(sheet)
    sheet.row_dimensions[1].height = 30

def create_index_sheet(wb, sheet_names, topic_name, description='', sources=None):
    idx = wb.create_sheet('Index', 0)
    idx.sheet_view.showGridLines = False

    # Title
    idx.merge_cells('A1:D1')
    title_cell = idx['A1']
    title_cell.value = f'{topic_name} — Cheatsheet'
    title_cell.font = Font(bold=True, size=16, color=COLORS['header_fg'], name='Calibri')
    title_cell.fill = PatternFill('solid', start_color=COLORS['index_bg'])
    title_cell.alignment = Alignment(horizontal='center', vertical='center')
    idx.row_dimensions[1].height = 40

    # Description
    if description:
        idx.merge_cells('A2:D2')
        desc_cell = idx['A2']
        desc_cell.value = description
        desc_cell.font = Font(italic=True, size=10, name='Calibri')
        desc_cell.alignment = Alignment(wrap_text=True)
        idx.row_dimensions[2].height = 30

    start_row = 4
    idx.cell(row=start_row - 1, column=1, value='Sheets').font = Font(bold=True, name='Calibri')

    for i, sheet_name in enumerate(sheet_names):
        cell = idx.cell(row=start_row + i, column=1, value=sheet_name)
        cell.font = Font(color='0563C1', underline='single', name='Calibri')
        cell.hyperlink = f"#'{sheet_name}'!A1"
        cell.alignment = Alignment(vertical='center')
        idx.row_dimensions[start_row + i].height = 20

    if sources:
        src_row = start_row + len(sheet_names) + 2
        idx.cell(row=src_row, column=1, value='Sources').font = Font(bold=True, name='Calibri')
        for i, src in enumerate(sources):
            idx.cell(row=src_row + 1 + i, column=1, value=src).font = Font(
                color='0563C1', size=9, name='Calibri'
            )

    idx.column_dimensions['A'].width = 30
```

### Naming & Saving
- Save to `/mnt/user-data/outputs/<topic-slug>-cheatsheet.xlsx`
- Topic slug: lowercase, hyphens, no spaces (e.g., `nginx-config-cheatsheet.xlsx`)

---

## Step 4: Recalculate & Verify

```bash
python /mnt/skills/public/xlsx/scripts/recalc.py /mnt/user-data/outputs/<file>.xlsx
```

Check output JSON — if `status` is `errors_found`, fix before presenting.

---

## Step 5: Present to User

Use `present_files` tool with the output path.

Include a brief summary:
- Topic covered
- Number of sheets / rows
- Source(s) used
- Any limitations or gaps noted

---

## Quality Checklist

- [ ] All columns have descriptive headers
- [ ] Freeze panes on row 1 of each data sheet
- [ ] No formula errors
- [ ] Column widths auto-fitted (min 10, max 60 chars)
- [ ] Alternating row colors for readability
- [ ] Index sheet present if 2+ data sheets
- [ ] Source attribution included (in Index or README sheet)
- [ ] File named descriptively with `-cheatsheet.xlsx` suffix

---

## Edge Cases

**Topic too broad** (e.g., "Linux cheatsheet"):
→ Ask user to narrow scope: *"Linux is very broad — shall I focus on a specific area? e.g., file system commands, networking, process management, bash scripting?"*

**Conflicting information across sources**:
→ Note discrepancies in a "Notes" column with version context

**Very large topics** (100+ items):
→ Split into multiple sheets by category; add Index sheet with row counts per sheet

**User provides raw config/code**:
→ Parse it directly, infer parameter meanings from context and common knowledge
