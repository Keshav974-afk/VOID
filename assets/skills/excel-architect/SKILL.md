---
name: excel-architect
description: Build clean, well-structured Excel (.xlsx) spreadsheets, financial models, trackers, and data tables using manage_document. Use when the user asks for an Excel file, spreadsheet, .xlsx workbook, budget table, or dataset export.
---

# Excel (.xlsx) Architect

Create native OpenXML `.xlsx` spreadsheets with styled header rows, typed numeric cells, and structured worksheets using `manage_document` (`action: "create_xlsx"`).

## Core Workflow

1. **Always use `manage_document` with `action: "create_xlsx"`**:
   - Provide `title` (used for the workbook and default sheet name).
   - Pass `headers` (list of column names) and `rows` (2D array of values), or pass a Markdown table in `content`.
   - Numeric values (integers, decimals) are automatically stored as native Excel numbers so formulas and sorting work immediately in Excel or Google Sheets.

2. **Spreadsheet Design Guidelines**:
   - Use clear, descriptive column headers in Row 1 (automatically styled with a bold navy header fill and white text).
   - Normalize units across columns (e.g., keep currency or percentages consistent) and include summary/total rows at the bottom when appropriate.
   - When the user needs multiple tabs, pass a `sheets` list where each entry has `{"name": "Sheet Name", "rows": [[...], [...]]}`.
