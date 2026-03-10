# Claude Usage Menu Bar App — Implementation Plan

Based on [design doc](./2026-03-10-claude-usage-menubar-design.md).

## Steps

### 1. Create Xcode project structure
- Create Swift Package / Xcode project for `ClaudeUsage` macOS app
- Set deployment target to macOS 14.0+
- Configure app as agent (LSUIElement = true, no Dock icon)
- Add Keychain entitlement

### 2. Create the Claude icon asset
- Create a small template image for the menu bar (16x16 / 32x32 @2x)
- Use a simplified Claude-like sparkle shape as an SF Symbol alternative
- Must be a template image (monochrome, respects light/dark mode)

### 3. Implement KeychainManager
- Read credentials from Keychain service `Claude Code-credentials`
- Parse stored JSON to extract access_token and refresh_token
- Use Security framework (`SecItemCopyMatching`) directly
- No writing back initially — just read

### 4. Implement UsageService
- `fetchUsage()` — GET to `/api/oauth/usage` with bearer token
- `refreshToken()` — POST to refresh endpoint when 401
- Parse JSON response into `UsageData` model
- Handle errors: network, 401, invalid response

### 5. Implement UsageModel (ObservableObject)
- Properties: fiveHourUtil, fiveHourResetsAt, sevenDayUtil, sevenDayResetsAt, opusUtil, sonnetUtil
- State: `.loading`, `.loaded`, `.unauthenticated`, `.error(String)`
- Timer-based polling every 60 seconds
- Computed properties for reset countdowns

### 6. Implement menu bar UI
- `MenuBarExtra` with label showing icon + percentage text
- Color the percentage text based on thresholds
- Dropdown menu with usage details, reset countdowns, model breakdown
- Error state with "Open Claude.ai to sign in" button
- Refresh and Quit menu items

### 7. Wire up and test
- Connect all components in the App entry point
- Test with real Keychain credentials
- Test error states (remove token, network off)
- Test token refresh flow

### 8. Polish
- Launch at login toggle (SMAppService)
- Smooth transitions when data updates
- Proper error messages for edge cases
