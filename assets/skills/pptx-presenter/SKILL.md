---
name: pptx-presenter
description: Create structured, persuasive PowerPoint (.pptx) slide decks and presentations natively using manage_document. Use when the user asks to make a presentation, pitch deck, lecture slides, or .pptx file.
---

# PowerPoint (.pptx) Presenter

Design and generate native `.pptx` slide decks using the `manage_document` tool (`action: "create_pptx"`).

## Core Workflow

1. **Always use `manage_document` with `action: "create_pptx"`**:
   - Pass `title`, optional `subtitle`, and either a structured `slides` array or Markdown `content`.
   - Every generated `.pptx` file is immediately viewable in Kelivo's in-app Office viewer and can be downloaded or opened in Microsoft PowerPoint, Keynote, or Google Slides.

2. **Slide Deck Architecture**:
   - Aim for **5 to 10 impactful slides** unless the user specifies a different length.
   - Follow a clear narrative arc:
     1. **Title & Executive Vision**
     2. **Problem / Opportunity Context**
     3. **Core Solution / Strategy**
     4. **Key Data, Metrics & Architecture**
     5. **Roadmap / Implementation Plan**
     6. **Next Steps & Recommendations**

3. **Formatting Best Practices**:
   - Keep slide titles concise and action-oriented (e.g., `"Q4 Revenue Accelerated by 34% YoY"` instead of `"Revenue"`).
   - Limit each slide to **3–5 crisp bullet points** (`bullets` array) so slides remain clean, scannable, and executive-ready.
   - Avoid walls of paragraph text on slides; distill complex ideas into high-signal points.
