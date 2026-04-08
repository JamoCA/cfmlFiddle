# CommandBox CFFiddle — Design Spec

A local web-based CFML fiddle tool powered by CommandBox. Users write CFML code in a browser-based editor and execute it against multiple CFML engine versions, comparing output across engines.

## Project Structure

```
cffiddle/
├── www/                          # Shared webroot (all engines point here)
│   ├── Application.cfc           # IP allowlist gate, path blocking, app config
│   ├── index.cfm                 # Single-page UI
│   ├── api2/                     # CFM-based API endpoints (api/ is reserved by CFML)
│   │   ├── Application.cfc       # Inherits parent, enforces JSON responses
│   │   ├── execute.cfm           # Posts payload to target engine, returns result
│   │   ├── servers.cfm           # Returns cached server statuses
│   │   ├── server-start.cfm      # Fires CommandBox server start
│   │   ├── server-stop.cfm       # Fires CommandBox server stop
│   │   ├── snippets.cfm          # Lists available snippet files
│   │   ├── snippet-load.cfm      # Returns content of a selected snippet
│   │   ├── session-clear.cfm     # Archives temp files, starts new session
│   │   └── config.cfm            # Returns/updates runtime config (timeout, etc.)
│   ├── _payloads/                # Temp execution files (blocked from direct browser access)
│   └── assets/                   # CSS, JS, images
├── archive/                      # ZIP archives (outside webroot, not web-accessible)
├── runtime/
│   └── servers/                  # App-generated server.json files (outside webroot)
├── snippets/                     # User-managed snippet files (cfm, json, md, etc.)
│   └── Application.cfc           # Blocks direct execution as safety net
├── current-servers/              # Template server.json files (hand-maintained)
├── JSONUtil/                     # JSONUtil.cfc for consistent JSON handling
└── intro.md
```

## Architecture

**Single-Page AJAX Application.** One `index.cfm` serves the entire UI — editor, results, status bar, and admin panel. All interactions happen via AJAX calls to `.cfm` API endpoints in `api2/`. No CFML framework dependencies.

**Host Engine Model.** The fiddle app runs on whichever CFML engine the user starts first via CommandBox. That host engine serves the UI, manages server lifecycle, proxies code execution to target engines, and is itself available as an execution target.

**API Endpoints are `.cfm` files, not `.cfc` files.** Some CFML platforms disable direct CFC access by default due to past security concerns. All API endpoints accept parameters via URL/form scope and return JSON via JSONUtil.

**JSONUtil for all serialization.** Native `serializeJSON`/`deserializeJSON` behaves differently across engines — notably, native functions silently ignore duplicate keys, whereas JSONUtil and BoxLang throw errors (preferred behavior to avoid silent data loss). All app-generated JSON uses JSONUtil for consistency.

**Ordered structs with quoted keys.** All structs/objects created by the application use ordered structs with quoted keys to retain key case and insertion order across all CFML platforms.

## Security

### IP Allowlist

The root `Application.cfc` enforces IP-based access control on every request. No part of the application executes if the requesting IP is not allowed.

**Configuration:** A variable at the top of `Application.cfc` defining allowed IPs:
```
this.allowedIPs = "127.0.0.1,::1,0:0:0:0:0:0:0:1";
```

**Matching logic (checked in `onRequestStart`):**
1. If the list contains `*` — allow all, skip checks
2. Exact match — `CGI.REMOTE_ADDR` equals an entry
3. Starts-with match — `CGI.REMOTE_ADDR` begins with an entry (e.g., `192.168.1` matches `192.168.1.50`)
4. If no match — abort the request and display: *"Access denied. Your IP address is [X.X.X.X]. Contact an administrator to be added to the allowlist."*

### Path Blocking

- **`/_payloads/`** — blocked from direct browser access in `Application.cfc`. Since all engines share the same `www/` webroot and thus the same `Application.cfc`, the blocking logic must distinguish between a user's browser request (blocked) and a server-to-server `cfhttp` request from the host engine (allowed). This can be achieved by requiring a shared secret token passed as a header or URL parameter on `cfhttp` calls from the host engine. Requests to `/_payloads/` without the valid token are rejected.
- **`/archive/`** — outside the webroot, inherently not web-accessible.
- **`/snippets/`** — outside the webroot, plus a safety-net `Application.cfc` that blocks all requests.

## Server Management

### Template vs. Runtime Configs

- `current-servers/` contains hand-maintained template `server.json` files for all 8 engines: cf2016, cf2021, cf2023, cf2025, lucee5, lucee6, lucee7, boxlang
- On startup, the app reads each template, clones it using JSONUtil (deserialize/re-serialize), applies runtime overrides (unique server name with `cffiddle-` prefix to avoid collisions), and writes the generated config to `runtime/servers/`
- CommandBox `server start` commands reference the generated configs in `runtime/servers/`

### Server Status Polling

**Server-side (heartbeat):**
- Configurable interval (default 30 seconds)
- The host engine loops through all known servers and makes a lightweight HTTP request to each engine's `host:port`
- Results cached in `Application` scope as an ordered struct keyed by server name: status (online/offline/starting), last checked timestamp, port, engine label

**Client-side (UI refresh):**
- Browser polls `api2/servers.cfm` on a configurable interval (default 10 seconds)
- Returns the cached status map — no server-to-server checks triggered by the UI poll

### Start/Stop Flow

**Start:**
1. `api2/server-start.cfm` fires a CommandBox `server start` command using the generated config in `runtime/servers/`
2. Returns immediately (fire-and-forget)
3. UI shows "Starting..." with a counter incrementing every second
4. If the heartbeat hasn't detected the server online within a configurable timeout (default 60 seconds), the UI displays a warning

**Stop:**
- `api2/server-stop.cfm` fires `server stop`
- Similar pattern — "Stopping..." until heartbeat confirms offline

## Code Execution Flow

### Single Engine Execution

1. User writes CFML in the Ace Editor
2. Selects a target engine from a dropdown (only online engines listed)
3. Clicks "Run"
4. `api2/execute.cfm` receives the CFML payload and target engine name
5. Generates a filename: `yyyymmddhhNNsslll-UUID.cfm`
6. Writes the payload to `www/_payloads/[filename]`
7. Makes a `cfhttp` request to `http://[engine-host]:[engine-port]/_payloads/[filename]`
8. Captures response body, HTTP status code, and measures duration
9. Builds an ordered struct result:
   - `"requestId"` — UUID
   - `"timestamp"` — ISO 8601 datestamp
   - `"duration"` — execution time in milliseconds
   - `"engine"` — engine name
   - `"success"` — boolean
   - `"output"` — rendered HTML output (on success)
   - `"error"` — normalized error message (on uncaught error)
10. Returns JSON via JSONUtil

### "Run All Online" Mode

- Fires execution against all online engines in parallel (using `cfthread` or sequential `cfhttp` depending on engine support)
- Collects all results into an ordered array
- Returns the full set for the UI to render

### Error Normalization

- If `cfhttp` returns an error response (4xx/5xx), parse the engine's native error page to extract: error type, message, line number, and detail
- Normalize into a consistent structure regardless of engine (Adobe CF, Lucee, and BoxLang all format errors differently)
- User-handled exceptions (`try/catch` in the payload) are not normalized — they are part of the successful output

### Execution Timeout

- Configurable timeout (default `0` = disabled)
- Adjustable in the UI for on-the-fly changes
- Applied to the `cfhttp` request to the target engine

## Session Management & Archiving

### Session Lifecycle

A session is implicit — starts when the user first runs code and continues until "Clear Session" is clicked or the application restarts.

### Temp File Retention

Each execution writes a `.cfm` file to `www/_payloads/` with the `yyyymmddhhNNsslll-UUID.cfm` naming convention. Files accumulate during the session.

### Archive Triggers

1. **User clicks "Clear Session"** — calls `api2/session-clear.cfm`
2. **Application startup** (`onApplicationStart`) — if any `.cfm` files exist in `_payloads/`, archive them (configurable, can be disabled via `archiveOnStartup` setting)

### Archive Process

1. Scan `_payloads/` for `.cfm` files
2. Group files by their `yyyymm` prefix (first 6 characters of the filename)
3. For each group, create a ZIP file in `archive/` named with the current timestamp plus the group month: `yyyymmddhhNNsslll-yyyymm.zip`
4. After successful ZIP, delete the source `.cfm` files from `_payloads/`

## User Interface

### Layout (Single Page)

**Top bar:**
- App title
- "Clear Session" button
- Execution timeout setting (0 = disabled)
- Snippet dropdown (auto-populated from files in `snippets/` directory)
- Compact server status indicators (colored dots per engine)

**Editor panel:**
- Ace Editor with ColdFusion mode (`mode-coldfusion.min.js`)
- Pre-populated with empty `<cfscript>` block
- Monokai theme (configurable)

**Controls bar:**
- Target engine dropdown (only online engines listed)
- "Run" button
- "Run All Online" button

**Results panel:**
- Metadata line per result: engine name, request UUID, ISO timestamp, duration
- Rendered HTML output by default
- "Source" toggle button (only visible if output contains HTML-like tags)
- For multi-engine results: dynamic display toggle — stacked, side-by-side, or tabbed (switchable after results are returned)

### Admin Panel (Modal/Slide-Out)

- Triggered by clicking the status bar indicators or a gear icon
- Server cards: engine name, version, host:port, status indicator, start/stop button
- "Starting..." state shows a seconds counter ticking up, with warning after configurable timeout
- Heartbeat indicators for online servers

### Snippets

- The `snippets/` directory holds user-managed text files (`.cfm`, `.json`, `.md`, etc.)
- If files exist, a dropdown in the top bar lists them by filename
- Selecting a snippet replaces the editor content with the file's contents
- A separate `Application.cfc` in the `snippets/` directory blocks any direct execution

## Configuration

All configurable values at the top of `Application.cfc`:

| Setting | Default | Description |
|---|---|---|
| `allowedIPs` | `127.0.0.1,::1,0:0:0:0:0:0:0:1` | IP allowlist (exact, starts-with, or `*` for any) |
| `executionTimeout` | `0` | Seconds before aborting execution (0 = disabled, adjustable in UI) |
| `serverPollInterval` | `30` | Seconds between server-side heartbeat checks |
| `clientPollInterval` | `10` | Seconds between browser status refreshes |
| `startupTimeout` | `60` | Seconds before UI warns server start may have failed |
| `archiveOnStartup` | `true` | Archive leftover `_payloads/` files on app start |
| `editorTheme` | `monokai` | Ace Editor theme |
| `serverNamePrefix` | `cffiddle-` | Prefix for generated server names to avoid collisions |
| `payloadsDir` | `_payloads` | Temp execution directory name |
| `archiveDir` | `../archive` | Path to archive directory (relative to webroot) |
| `snippetsDir` | `../snippets` | Path to snippets directory |
| `templateServersDir` | `../current-servers` | Path to template server.json files |
| `runtimeServersDir` | `../runtime/servers` | Path to generated server.json files |

## Supported Engines

| Engine | Config Template | Port | Host Alias | Java Home |
|---|---|---|---|---|
| Adobe CF 2016 | `server.cf2016.json` | 2016 | `cf2016.local` | `jdk-11.0.25` |
| Adobe CF 2021 | `server.cf2021.json` | 2021 | `cf2021.local` | (engine default) |
| Adobe CF 2023 | `server.cf2023.json` | 2023 | `cf2023.local` | (engine default) |
| Adobe CF 2025 | `server.cf2025.json` | 2025 | `cf2025.local` | `jdk-24` |
| Lucee 5 | `server.lucee5.json` | 3005 | `lucee5.local` | (engine default) |
| Lucee 6 | `server.lucee6.json` | 3006 | `lucee6.local` | (engine default) |
| Lucee 7 | `server.lucee7.json` | 3007 | `lucee7.local` | `jre21` |
| BoxLang | `server.boxlang.json` | 4000 | `boxlang.local` | `jdk-24` |

### Shared Config Across All Engines

- `libDirs`: `c:\CFusionExtra\java,c:\CFusionExtra\java2021`
- `customTagPaths`: `c:\CFusionExtra\customtags`
- `webroot`: `www`
- `aliases`: `/_scriptsGlobal` -> `c:\Commandbox\www\_scriptsGlobal`
- `jvm.args`: XML external access restrictions
- `mimeTypes`: `heic` -> `image/heic`

### Engine-Specific Config

- **Lucee engines:** `luceeConfig.customTagMappings` for custom tag support
- **BoxLang:** `boxlang.compatibility.adobe = true`
- **CF 2025:** `scripts.onServerInitialInstall` installs caching and debugger packages
