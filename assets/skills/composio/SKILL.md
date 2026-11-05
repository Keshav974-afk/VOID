---
name: composio
description: Connect and orchestrate 500+ apps and services (GitHub, Slack, Google Calendar, Gmail, Jira, Linear, Notion, Discord, Twitter, etc.) through Composio MCP integration. Use when the user wants to interact with external tools, workspace services, or automate tasks across services.
---

# Composio Integration

Composio gives you access to 500+ apps, integrations, and tools through a unified Model Context Protocol (MCP) server.

## Overview

Composio enables autonomous agents to perform authenticated actions across external services:
- **Productivity & Workspaces**: Google Calendar, Gmail, Google Drive, Notion, Slack, Discord, Jira, Linear, Trello, Asana
- **Developer Tools**: GitHub, GitLab, Bitbucket, Vercel, Supabase, Cloudflare
- **Social & Media**: Twitter/X, LinkedIn, Reddit, YouTube
- **Finance & CRM**: Stripe, QuickBooks, Salesforce, HubSpot

## Connecting Composio MCP

To connect Composio in Kelivo:
1. Open the side menu and tap **MCP Servers** (or Settings > MCP).
2. Tap **Add Server** or tap the **Composio** quick preset.
3. Configure the connection:
   - **Transport**: SSE / HTTP
   - **URL**: `https://backend.composio.dev/api/v1/mcp`
   - **Headers**:
     - `x-api-key`: `<YOUR_COMPOSIO_API_KEY>`
4. Tap **Save**. Kelivo will automatically discover available tools for your connected integrations.

## Workflows

### 1. Check Connected Integrations
When asked to perform actions in external apps, first check if the tool is available from the Composio MCP server.

### 2. Execute Actions
Invoke the appropriate Composio tool with required parameters. Confirm destructive actions (deletions, modifications) with the user before executing.

### 3. Handle Auth & Setup
If an integration requires authentication, guide the user to their Composio dashboard (`https://app.composio.dev/apps`) to link the target service.
