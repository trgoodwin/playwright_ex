# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this?

PlaywrightEx is an Elixir client for the Playwright Node.js server. It automates browsers (Chromium, Firefox, Safari, Edge) for web scraping and agentic AI. It is a ground-up implementation — intentionally simple and easy to extend, not comprehensive.

## Common Commands

```bash
mix setup              # Install deps + npm packages + Playwright browsers
mix test               # Run tests (local Playwright via Port transport)
mix test.websocket     # Run tests against remote Playwright via WebSocket (requires Docker)
mix check              # Full CI check: format, credo, compile warnings, dialyzer, tests
mix test path/to/test.exs           # Run a single test file
mix test path/to/test.exs:42       # Run a single test at line
```

The `PW_TIMEOUT` env var controls test timeouts (default: 1000ms).

## Architecture

### Communication Flow

```
Elixir Channel API (e.g. Frame.goto/2)
  → PlaywrightEx.Connection (gen_statem, routes by message ID)
  → Transport (PortTransport or WebSocketTransport)
  → Node.js Playwright server
  → Response routed back by ID → ChannelResponse.unwrap/2
```

### Two Transport Modes

- **PortTransport** (default): Launches local Node.js process via Erlang `:Port`. Binary framing: 4-byte length prefix + JSON payload.
- **WebSocketTransport**: Connects to remote Playwright server. Requires `{:websockex, "~> 0.4"}`. Retry logic: 30 attempts, 1s intervals.

### Channel Pattern

All channel modules (`Browser`, `BrowserContext`, `Page`, `Frame`, `Dialog`, `Tracing`) follow the same pattern:
1. Define option schema with NimbleOptions
2. Validate options
3. Extract connection name + timeout from the guid
4. Send message via `Connection.send/3`
5. Unwrap response via `ChannelResponse.unwrap/2`

The guid string encodes both the resource identity and which Connection process owns it.

### Key Internal Modules

- **Connection** (`gen_statem`): Central hub. Starts in `:pending`, transitions to `:started` after Playwright init. Routes messages by ID, manages subscriptions via `:pg`.
- **FrameEventRecorder**: Per-frame GenServer tracking navigation state (URL + load_states). Enables event-based waiting without polling.
- **FrameWaiter**: Pure functions evaluating navigation conditions against FrameEventRecorder state.
- **Serialization**: Bidirectional Elixir ↔ JSON conversion with snake_case ↔ camelCase, Regex support, nil handling.
- **Selector**: Builder API for constructing Playwright selector strings (role-based, CSS, text, etc.).

### API Design

Most interactions go through the **Frame** module, which has the richest API (goto, click, fill, evaluate, wait_for_selector, etc.). The **Page** module handles page-level concerns (screenshot, mouse events, reload). This differs from `playwright-elixir` where Page wraps Frame methods as convenience — here you work with Frame directly.

## Testing

Tests use `PlaywrightExCase` (in `test/support/`) which provides `setup` fixtures: `browser`, `browser_context`, `page`, and `frame`. Helper functions: `set_html/2`, `eval/2`, `assert_has/2`, `refute_has/2`.

Config in `config/test.exs` points the executable to `assets/node_modules/playwright/cli.js` and enables strict option validation (`fail_on_unknown_opts: true`).

## Style

Code is formatted with `mix format` and uses the `Styler` plugin. Linting via `Credo`. Type checking via `Dialyxir`.
