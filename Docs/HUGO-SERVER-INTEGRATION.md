# Phase 8: Hugo Server Integration

This document describes the Hugo development server integration added to Victor, enabling live preview of Hugo sites directly within the application.

## Overview

Victor now includes a fully integrated Hugo development server that allows you to:
- Start/stop the Hugo server from within the app
- View live preview of your site rendered by Hugo
- See build errors with clickable file paths
- Configure server options (port, drafts, future posts, etc.)
- Automatic crash recovery

## Features

### 1. Server Controls (Toolbar)

When a Hugo site is open, the toolbar displays server controls:

| Control | Description |
|---------|-------------|
| Status Indicator | Colored dot showing server state (gray=stopped, yellow=starting, green=running, red=error) |
| Start/Stop Button | Toggle the Hugo development server |
| Open in Browser | Opens your site in the default browser (visible when running) |
| Settings (gear icon) | Opens configuration popover |
| Error Badge | Red badge showing build error count (clickable to view details) |

**Keyboard Shortcuts:** None currently assigned.

### 2. Live Preview

When the Hugo server is running, you can switch between two preview modes:

- **Markdown Preview**: The original preview that renders markdown to HTML locally
- **Live Preview**: Displays your actual Hugo site from the development server

**Toggle Location:** In the tab bar (right side), when server is running and in Preview or Split mode.

**Features:**
- Navigation toolbar with back/forward/refresh buttons
- URL display showing current page
- Server status indicator
- Auto-refresh on file changes (via Hugo's live reload)
- Automatic navigation to the current file's URL

### 3. Build Error Display

Build errors are displayed in two ways:

1. **Error Badge Popover**: Click the red error badge in the toolbar to see a list of all errors with:
   - Error/warning level icons
   - File path and line number (when available)
   - Error message
   - Timestamp

2. **Build Error Overlay**: When using Live Preview, a semi-transparent overlay appears showing:
   - Error count summary
   - Scrollable list of errors
   - Clickable file paths
   - Dismiss button to view stale preview

### 4. Server Configuration

Access via the gear icon in the toolbar:

| Setting | Default | Description |
|---------|---------|-------------|
| Port | 1313 | Server port number |
| Build Drafts | On | Include draft content |
| Build Future | On | Include future-dated content |
| Build Expired | Off | Include expired content |
| Disable Live Reload | Off | Turn off browser auto-reload |

### 5. Preferences (Server Tab)

The Preferences window now includes a **Server** tab showing:

- **Hugo Installation Status**: Whether Hugo is installed and its version
- **Install Hugo Link**: Direct link to Hugo installation docs (if not installed)
- **Default Server Settings**: Port, drafts, future, expired settings

## Architecture

### Services

#### HugoServerService (`Victor/Services/HugoServerService.swift`)

An actor-based service managing the Hugo server subprocess:

```swift
actor HugoServerService {
    static let shared = HugoServerService()

    // State
    var status: HugoServerStatus
    var config: HugoServerConfig
    var buildErrors: [HugoBuildError]
    var serverOutput: [String]
    var serverURL: URL?

    // Control
    func start(siteURL: URL) async throws
    func stop() async
    func restart(siteURL: URL) async throws

    // Observers (supports multiple)
    func addOnStatusChange(_ callback: ...) -> UUID
    func addOnBuildErrorsChange(_ callback: ...) -> UUID
    func addOnOutputChange(_ callback: ...) -> UUID
}
```

**Key Features:**
- Hugo binary detection (checks common paths + `which hugo`)
- Port conflict detection and automatic resolution
- Crash recovery with auto-restart (up to 3 attempts)
- Multi-observer pattern for state changes

#### BuildErrorParser (`Victor/Services/BuildErrorParser.swift`)

Utility for parsing Hugo build output:

```swift
enum BuildErrorParser {
    static func parseLine(_ line: String) -> HugoBuildError?
    static func extractFileLocation(from text: String) -> (file: String?, line: Int?)
    static func parseServerReady(_ line: String) -> Int?
    static func isRebuildingLine(_ line: String) -> Bool
    static func parseBuildComplete(_ line: String) -> Int?
}
```

### Models

#### HugoServerStatus

```swift
enum HugoServerStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case error(message: String)

    var isRunning: Bool
    var displayText: String
}
```

#### HugoServerConfig

```swift
struct HugoServerConfig: Equatable {
    var port: Int = 1313
    var bindAddress: String = "localhost"
    var buildDrafts: Bool = true
    var buildFuture: Bool = true
    var buildExpired: Bool = false
    var watch: Bool = true
    var navigateToChanged: Bool = true
    var disableLiveReload: Bool = false
}
```

#### HugoBuildError

```swift
struct HugoBuildError: Identifiable, Equatable {
    let id: UUID
    let level: Level  // .error, .warning, .info
    let message: String
    let file: String?
    let line: Int?
    let timestamp: Date

    var clickableFilePath: String?
}
```

### Views

| File | Purpose |
|------|---------|
| `ServerControlView.swift` | Toolbar controls for server management |
| `ServerConfigPopover.swift` | Configuration popover |
| `ServerLogView.swift` | Server output log viewer |
| `LivePreviewPanel.swift` | WKWebView-based live preview |
| `BuildErrorOverlay.swift` | Error overlay for preview panel |

### ViewModel Integration

**SiteViewModel** additions:

```swift
// State
var hugoServerStatus: HugoServerStatus
var isHugoServerRunning: Bool  // computed
var hugoBuildErrors: [HugoBuildError]
var hugoServerURL: URL?
var useLivePreview: Bool

// Methods
func setupHugoServerObservers()
func startHugoServer() async throws
func stopHugoServer() async
func toggleHugoServer() async
func toggleLivePreview()
```

### ContentView Integration

- Server controls added to toolbar
- Preview panel switches between `PreviewPanel` and `LivePreviewPanel` based on `useLivePreview` state
- Hugo server observers set up on appear

### TabBarView Integration

- Live Preview toggle button (visible when server running + preview/split mode)

## File Locations

```
Victor/
├── Services/
│   ├── HugoServerService.swift    # Server management actor
│   └── BuildErrorParser.swift     # Output parsing
├── Views/
│   ├── ServerControls/
│   │   ├── ServerControlView.swift
│   │   ├── ServerConfigPopover.swift
│   │   └── ServerLogView.swift
│   └── Preview/
│       ├── LivePreviewPanel.swift
│       └── BuildErrorOverlay.swift
├── ViewModels/
│   └── SiteViewModel.swift        # (modified)
└── Views/
    ├── MainWindow/
    │   ├── ContentView.swift      # (modified)
    │   └── TabBarView.swift       # (modified)
    └── Preferences/
        └── PreferencesView.swift  # (modified - new Server tab)

VictorTests/
└── HugoServerTests.swift          # 19 tests
```

## Testing

The `HugoServerTests.swift` file contains 19 tests covering:

- BuildErrorParser line parsing
- File location extraction
- Message cleaning
- Server ready detection
- Rebuild detection
- Build completion parsing
- HugoServerStatus display text and isRunning
- HugoServerConfig defaults
- HugoBuildError clickable file paths
- HugoServerError descriptions

Run tests:
```bash
xcodebuild test -project Victor.xcodeproj -scheme Victor \
  -destination 'platform=macOS' \
  -only-testing:VictorTests/HugoServerTests
```

## Error Handling

### Hugo Not Found

If Hugo is not installed, the user sees:
- Disabled start button
- Alert with installation instructions
- Link to Hugo installation docs in Preferences

### Port Conflicts

If the default port (1313) is in use:
- Automatically finds next available port
- Logs the port change
- Updates UI to show actual port

### Server Crashes

If the server crashes unexpectedly:
- Status changes to error state
- Auto-restart attempted (up to 3 times)
- Error message displayed in status

### Build Errors

Build errors from Hugo are:
- Parsed and structured
- Displayed in error badge count
- Shown in clickable popover
- Overlaid on live preview panel

## Future Enhancements

Potential improvements not yet implemented:

1. **File Navigation**: Clicking error file paths could navigate to that file in the editor
2. **Hugo Install Helper**: Built-in Hugo installation via Homebrew
3. **Multiple Server Instances**: Support for running multiple Hugo sites
4. **Build Statistics**: Show build time, page count, etc.
5. **Custom Hugo Path**: Allow specifying Hugo binary location in preferences

---

**Document Version**: 1.0
**Last Updated**: 2026-01-13
**Status**: Production Ready
