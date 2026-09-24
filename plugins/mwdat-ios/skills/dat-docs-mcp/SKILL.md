---
name: dat-docs-mcp
description: Use the Wearables DAT MCP server for live DAT documentation search with `search_dat_docs`, Muse Code, Claude Code, Codex, Cursor, and MCP Inspector
---

# DAT Docs MCP (iOS)

Use this skill whenever a user asks about the DAT MCP server, live docs search,
current DAT documentation, API lookup, code examples, MCP setup, or MCP
Inspector.

This is the documentation counterpart to `live-debugging-mcp`: use this skill to
look up published DAT documentation, and use `live-debugging-mcp` for observed
runtime behavior in a running app.

## Endpoint

- MCP endpoint: `https://mcp.developer.meta.com/wearables`
- Transport: HTTP (Streamable HTTP)
- Authentication: none. Do not configure tokens, OAuth, or custom
  `Authorization` headers for this server.

Connect to the MCP host above directly. Do not point an MCP client at the
Wearables developer website URL; that is a docs site, not the MCP endpoint.

## Tools

- `search_dat_docs` — semantic search over DAT guides, API reference, and code
  examples.

The server may add more DAT MCP tools over time, so list the tools after
connecting instead of assuming this is the only one.

## Repo config vs. MCP

- Use the repo-local AI config (these skills, `.cursor/rules/`,
  `.github/copilot-instructions.md`, `AGENTS.md`) for coding patterns, setup
  steps, and project conventions.
- Use the MCP endpoint for live DAT documentation and exact current API
  symbols, especially when a symbol may have changed since this repo config was
  written.

## Setup: Muse Code, Claude Code, and Codex

Installing the `mwdat-ios` plugin registers the hosted DAT docs MCP server in
Muse Code, Claude Code, and Codex. No separate MCP configuration is required.

## Setup: Cursor

Add an HTTP MCP server with:

- Name: `wearables-dat`
- Type/transport: HTTP
- URL: `https://mcp.developer.meta.com/wearables`

For JSON-backed Cursor settings:

```json
{
  "mcpServers": {
    "wearables-dat": {
      "type": "http",
      "url": "https://mcp.developer.meta.com/wearables"
    }
  }
}
```

## Setup: MCP Inspector

```bash
npx @modelcontextprotocol/inspector
```

1. Set transport to Streamable HTTP, or HTTP if that is the label in the
   installed Inspector.
2. Set URL to `https://mcp.developer.meta.com/wearables`.
3. Set connection type to Direct.
4. Initialize, then list tools and confirm `search_dat_docs` appears.
5. Run a query such as `camera streaming`.

## Example prompts

- `Search the Wearables DAT docs for camera streaming setup on iOS.`
- `How do I stream camera on Ray-Ban Meta glasses?`
- `How do I initialize the Wearables SDK and access a connected device?`
- `How do I test DAT integrations without physical glasses?`
- `Bluetooth connection lifecycle events`

## Troubleshooting

- Server does not connect: re-enter `https://mcp.developer.meta.com/wearables`
  and reconnect.
- No tools appear: reconnect and initialize the session before listing tools.
- The client asks for auth: remove any stale custom auth headers or tokens for
  this server and reconnect. This server does not require authentication.
- Results are too broad: include the platform, module, or exact API name in the
  query, for example `iOS MWDATCamera StreamConfiguration frameRate` instead of
  `frame rate`.

## Static fallback

When a tool cannot use remote MCP servers at all, point it at the static
reference instead: `https://wearables.developer.meta.com/llms.txt?full=true`.
