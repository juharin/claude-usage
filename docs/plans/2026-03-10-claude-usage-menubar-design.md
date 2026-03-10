# Claude Usage Menu Bar App — Design

## Overview

A native macOS menu bar app (Swift/SwiftUI) that shows Claude Pro subscription usage at a glance. Reads OAuth credentials from macOS Keychain (stored by Claude Code) and polls the Anthropic usage API.

## Data Source

**Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
**Auth:** `Authorization: Bearer <access_token>` + `anthropic-beta: oauth-2025-04-20`
**Token source:** macOS Keychain, service `Claude Code-credentials`
**Token refresh:** `POST https://console.anthropic.com/api/oauth/token` with refresh token

Response shape:
```json
{
  "five_hour": { "utilization": 67.0, "resets_at": "2025-11-04T04:59:59Z" },
  "seven_day": { "utilization": 35.0, "resets_at": "2025-11-06T03:59:59Z" },
  "seven_day_sonnet": { "utilization": 10.0, "resets_at": "..." },
  "seven_day_opus": { "utilization": 25.0, "resets_at": "..." }
}
```

## UI Design

### Menu Bar (always visible)

- Shows Claude icon + `67%` — the 5-hour utilization value
- Claude icon: small SF Symbol or custom asset resembling the Claude logo (sparkle/asterisk shape). `sparkles` or custom SVG template image.
- Color coding:
  - Green (default): 0–59%
  - Yellow: 60–84%
  - Red: 85–100%
- Error states:
  - `--` with grey color: not authenticated / token expired
  - `!` with red color: network error

### Dropdown (on click)

Normal state:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━
  5-Hour Usage     67%
  Resets in         2h 14m
  ──────────────────────────
  7-Day Usage      35%
  Resets in       4d 12h
  ──────────────────────────
  Opus (7d)        25%
  Sonnet (7d)      10%
  ──────────────────────────
  Last updated    just now
  ──────────────────────────
  Refresh
  Quit
━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Error/unauthenticated state:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚠ Not authenticated
  ──────────────────────────
  Open Claude.ai to sign in
  ──────────────────────────
  Quit
━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Clicking "Open Claude.ai to sign in" opens `https://claude.ai` in the default browser.

## Architecture

### Components

1. **ClaudeUsageApp** — `@main` App with `MenuBarExtra`
2. **UsageService** — Handles API calls, token refresh, polling
3. **KeychainManager** — Reads/refreshes OAuth tokens from Keychain
4. **UsageModel** — Observable data model for SwiftUI binding

### Flow

1. App launches → reads access token from Keychain
2. Calls usage API immediately
3. Polls every 60 seconds
4. If 401 → attempts token refresh using refresh token
5. If refresh fails → shows unauthenticated state
6. Clicking "Open Claude.ai" → `NSWorkspace.shared.open(url)`

### Token Management

- Read from Keychain: service `Claude Code-credentials`
- Access token expires every 8 hours
- On 401: POST to refresh endpoint with refresh token to get new access token
- Store refreshed access token back to Keychain
- If refresh token is also invalid → show auth error state

### Security

- Tokens accessed via native Keychain API (Security framework), not CLI
- No tokens written to disk outside Keychain
- Tokens held in memory only during app lifetime
- App requests Keychain access permission on first run (macOS prompt)

## Tech Stack

- Swift 5.9+
- SwiftUI with `MenuBarExtra`
- Security framework (Keychain)
- Foundation `URLSession` for HTTP
- No third-party dependencies
- Xcode project, targeting macOS 14+

## Polling & Performance

- Poll interval: 60 seconds
- Memory footprint: ~5-10MB
- No background processing beyond the timer
- Launch at login: optional, via `SMAppService`
