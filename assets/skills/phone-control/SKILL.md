---
name: phone-control
description: Autonomous Android device control via Accessibility Service. Inspect screen contents, tap buttons, enter text, scroll, press navigation keys, open apps, send messages on WhatsApp, and automate mobile workflows. Use when the user asks the assistant to control the phone, click UI elements, open apps, or automate mobile tasks.
---

# Phone Control (Android Automation)

VOID's Phone Control Service leverages the Android Accessibility API to inspect the on-screen UI hierarchy and execute precise touches, inputs, app launches, and navigation gestures autonomously.

## Prerequisites

- **Accessibility Permission**: The user must enable "VOID Phone Control" in Android Settings > Accessibility > Installed Apps.
- **Floating Overlay**: During automation, a sleek circular floating widget appears with an active progress ring, live stopwatch, and phone control indicator `📱` so the user knows automation is active.

## Capabilities

1. **App Launching**:
   - `open_app`: Launch any installed app by package name or common name (e.g., `whatsapp`, `chrome`, `youtube`, `settings`). Supports direct deep-link URIs (e.g., `whatsapp://send?text=...`).
2. **Instant Messaging (e.g. WhatsApp)**:
   - `whatsapp_send`: Directly opens WhatsApp with the message text already drafted and ready to send to a contact or phone number.
   - `click_text`: Taps on any visible element matching contact names (e.g. "Mom") or buttons (e.g. "Send", "Search").
   - `type_text`: Types message or query directly into the focused or editable text field.
3. **Screen Inspection**:
   - `read_screen`: Dumps the current view hierarchy, including text labels, content descriptions, view IDs, bounding boxes, and clickability.
4. **Click & Tap**:
   - `tap`: Tap on specific UI elements identified by `node_id`, `text`, or exact screen coordinates `(x, y)`.
   - `click_text`: Fuzzy match visible text or buttons and click them.
5. **Text Input**:
   - `set_text` / `type_text`: Focus input fields and enter text.
6. **Scroll & Swipe**:
   - `scroll`: Scroll up, down, left, right to navigate feeds, chats, and pages.
   - `swipe`: Move finger across specific coordinates.
7. **System Navigation**:
   - `back`, `home`, `recents`, `notifications`, `quick_settings`.

## Example Workflows

### 1. Send WhatsApp Message (e.g. "Send message to Mom that I am coming home late tonight"):
1. Call `phone_control` with `action: "whatsapp_send"`, `text: "I am coming home late tonight"`.
2. WhatsApp opens immediately with the contact chooser and drafted text.
3. Call `action: "click_text"`, `text: "Mom"` to select Mom from recent chats or contacts.
4. Call `action: "click_text"`, `text: "Send"` (or icon) to dispatch the message.
5. Alternatively, open WhatsApp directly: `open_app(app_name: "whatsapp")` -> `click_text(text: "Mom")` -> `type_text(text: "I am coming home late tonight")` -> `click_text(text: "Send")`.

### 2. Search on YouTube or Chrome:
1. `open_app(app_name: "youtube")`
2. `click_text(text: "Search")`
3. `type_text(text: "flutter tutorial")`
4. `tap` the search keyboard action or top result.
