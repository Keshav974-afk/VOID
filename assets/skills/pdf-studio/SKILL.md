---
name: pdf-studio
description: Design and generate attractive, publication-grade PDF documents with executive headers, color themes, styled tables, callouts, and pagination using manage_document. Use when the user asks to create a PDF report, invoice, resume, proposal, letter, or guide.
---

# PDF Studio

Generate visually polished, structured PDF documents natively on the device using the `manage_document` tool (`action: "create_pdf"`).

## Core Workflow

1. **Always use `manage_document` with `action: "create_pdf"`**:
   - Never use `bash` or `sandbox_vps` to generate user PDFs unless explicitly asked to run a custom remote script.
   - `manage_document` renders the PDF directly on the user's device and displays an interactive in-app PDF preview card with zoom, page counter, download, and share buttons.

2. **Choose an Appropriate Color Theme (`theme`)**:
   - `"executive"` (Default): Deep Navy & Ocean Blue — ideal for business reports, proposals, invoices, and formal letters.
   - `"emerald"`: Forest & Emerald Green — ideal for financial summaries, sustainability reports, and growth plans.
   - `"royal"`: Indigo & Royal Violet — ideal for technical architecture docs, product specs, and creative briefs.
   - `"crimson"`: Deep Red & Rose — ideal for urgent audits, security advisories, and executive alerts.
   - `"slate"`: Minimalist Charcoal & Slate — ideal for resumes, academic papers, and legal agreements.

3. **Structure Content for Maximum Visual Appeal (`content`)**:
   - Provide a clear `title` and a descriptive `subtitle` (e.g., `"Prepared for Acme Corp • Q4 Executive Analysis"`).
   - Use `# Heading 1` for major sections (rendered with a colored accent bar).
   - Use `## Heading 2` and `### Heading 3` for subsections.
   - Use **Markdown Tables** (`| Metric | Q3 | Q4 | Growth |`) whenever presenting comparisons, budgets, schedules, or KPIs — `manage_document` automatically styles them with themed header rows and alternating zebra striping.
   - Use **Blockquotes** (`> Key Takeaway: ...`) for executive callouts and highlights.
   - Use bullet lists (`- `) or numbered lists (`1. `) for actionable items.
   - Use horizontal rules (`---`) to visually separate major topics.
