---
name: docx-writer
description: Author polished Microsoft Word (.docx) documents, contracts, SOPs, essays, and structured business reports using manage_document. Use when the user asks to create a Word document, .docx file, editable memo, or formal specification.
---

# Word (.docx) Writer

Create native OpenXML `.docx` documents with styled titles, hierarchical headings, bulleted lists, and formatted tables using `manage_document` (`action: "create_docx"`).

## Core Workflow

1. **Always use `manage_document` with `action: "create_docx"`**:
   - Pass `title`, optional `subtitle`, and rich Markdown `content`.
   - The generated `.docx` file is immediately previewable inside Kelivo's in-app document viewer and opens cleanly in Microsoft Word, Google Docs, and LibreOffice.

2. **Document Structure & Typography**:
   - Organize documents with `# Section Headings` (`Heading 1`) and `## Subsections` (`Heading 2`).
   - Use Markdown tables (`| Column A | Column B |`) for structured data, schedules, or sign-off matrices — they are converted into native Word tables (`w:tbl`) with styled navy headers and subtle borders.
   - Use bullet points (`- `) for requirements, deliverables, and action items.
