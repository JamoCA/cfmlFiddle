# CommandBox CFFiddle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local web-based CFML fiddle tool where users write code in an Ace Editor and execute it against multiple CFML engine versions via CommandBox.

**Architecture:** Single-page AJAX app served by any CommandBox CFML engine. The host engine proxies code execution to target engines via cfhttp against a shared webroot. All API endpoints are .cfm files (not CFCs). JSONUtil handles all serialization with ordered structs and quoted keys throughout.

**Tech Stack:** CFML (cross-engine compatible), Ace Editor via CDN, CommandBox server management, JSONUtil for JSON handling, vanilla JavaScript (no frameworks)

**Spec:** `docs/superpowers/specs/2026-04-08-cffiddle-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `www/Application.cfc` | IP allowlist gate, path blocking, config, app startup archiving, server config generation, heartbeat scheduling |
| `www/index.cfm` | Single-page UI: Ace Editor, results panel, status bar, admin modal |
| `www/api2/Application.cfc` | Inherits root, sets JSON content type, wraps responses |
| `www/api2/execute.cfm` | Writes payload to `_payloads/`, cfhttp to target engine, returns result JSON |
| `www/api2/servers.cfm` | Returns cached server status map from Application scope |
| `www/api2/server-start.cfm` | Fires CommandBox `server start` via cfexecute, returns immediately |
| `www/api2/server-stop.cfm` | Fires CommandBox `server stop` via cfexecute, returns immediately |
| `www/api2/snippets.cfm` | Lists files in `snippets/` directory |
| `www/api2/snippet-load.cfm` | Returns content of a selected snippet file |
| `www/api2/session-clear.cfm` | Archives `_payloads/` files to ZIP, clears directory |
| `www/api2/config.cfm` | GET/POST runtime config values (execution timeout) |
| `www/assets/css/style.css` | All application styles |
| `www/assets/js/app.js` | All client-side JavaScript: editor init, AJAX calls, polling, UI state |
| `snippets/Application.cfc` | Blocks all direct execution of snippet files |

---

## Task 1: Directory Structure & Safety Gates

**Files:**
- Create: `www/Application.cfc`
- Create: `snippets/Application.cfc`
- Create: `www/api2/Application.cfc`

This task creates the foundational `Application.cfc` files that enforce security and establish the app framework. Everything else depends on this.

- [ ] **Step 1: Create the `snippets/Application.cfc` safety gate**

This is the simplest file — it blocks all requests to the snippets directory.

```cfm
<cfcomponent output="false">

    <cffunction name="onRequestStart" returntype="boolean" output="true">
        <cfargument name="targetPage" type="string" required="true">
        <cfcontent type="text/html" reset="true">
        <cfoutput>
            <h2>Access Denied</h2>
            <p>Direct access to this directory is not permitted.</p>
        </cfoutput>
        <cfreturn false>
    </cffunction>

</cfcomponent>
```

- [ ] **Step 2: Create the root `www/Application.cfc` with config and IP gate**

This is the core security file. It defines all configuration, enforces the IP allowlist, blocks `_payloads/` direct access, and handles app startup.

```cfm
<cfcomponent output="false">

    <!--- Application identity --->
    <cfset this.name = "CFFiddle_" & hash(getCurrentTemplatePath())>
    <cfset this.sessionManagement = true>
    <cfset this.sessionTimeout = createTimeSpan(0, 2, 0, 0)>

    <!--- Map to JSONUtil (outside webroot) --->
    <cfset this.mappings["/jsonutil"] = expandPath("../JSONUtil")>

    <!--- ============================================================
          CONFIGURATION — Edit these values to customize the app
          ============================================================ --->

    <!--- IP Allowlist: comma-delimited list.
          Matching rules:
            "*"           = allow all IPs
            exact match   = "192.168.1.50"
            starts-with   = "192.168.1" matches 192.168.1.*
          Default: localhost only --->
    <cfset this.allowedIPs = "127.0.0.1,::1,0:0:0:0:0:0:0:1">

    <!--- Execution timeout in seconds (0 = disabled). Adjustable in UI. --->
    <cfset this.executionTimeout = 0>

    <!--- Server-side heartbeat interval in seconds --->
    <cfset this.serverPollInterval = 30>

    <!--- Client-side UI refresh interval in seconds --->
    <cfset this.clientPollInterval = 10>

    <!--- Seconds before UI warns that a server start may have failed --->
    <cfset this.startupTimeout = 60>

    <!--- Archive leftover _payloads/ files on application start --->
    <cfset this.archiveOnStartup = true>

    <!--- Ace Editor theme name --->
    <cfset this.editorTheme = "monokai">

    <!--- Prefix for generated server names to avoid collisions --->
    <cfset this.serverNamePrefix = "cffiddle-">

    <!--- Directories (relative to webroot) --->
    <cfset this.payloadsDir = "_payloads">
    <cfset this.archiveDir = "../archive">
    <cfset this.snippetsDir = "../snippets">
    <cfset this.templateServersDir = "../current-servers">
    <cfset this.runtimeServersDir = "../runtime/servers">

    <!--- Shared secret token for _payloads/ access via cfhttp --->
    <cfset this.payloadToken = hash(this.name & "payloadAccess" & getCurrentTemplatePath(), "SHA-256")>

    <cffunction name="onApplicationStart" returntype="boolean" output="false">
        <!--- Initialize JSONUtil --->
        <cfset application.jsonUtil = createObject("component", "jsonutil.JSONUtil").init()>

        <!--- Store config in application scope for api2 endpoints to read --->
        <cfset application.config = [
            "executionTimeout": this.executionTimeout,
            "serverPollInterval": this.serverPollInterval,
            "clientPollInterval": this.clientPollInterval,
            "startupTimeout": this.startupTimeout,
            "editorTheme": this.editorTheme,
            "serverNamePrefix": this.serverNamePrefix,
            "payloadsDir": this.payloadsDir,
            "archiveDir": this.archiveDir,
            "snippetsDir": this.snippetsDir,
            "templateServersDir": this.templateServersDir,
            "runtimeServersDir": this.runtimeServersDir,
            "payloadToken": this.payloadToken
        ]>

        <!--- Initialize server status cache --->
        <cfset application.serverStatuses = [:]>

        <!--- Ensure directories exist --->
        <cfset var payloadsPath = expandPath(this.payloadsDir)>
        <cfset var archivePath = expandPath(this.archiveDir)>
        <cfset var runtimeServersPath = expandPath(this.runtimeServersDir)>
        <cfif not directoryExists(payloadsPath)>
            <cfset directoryCreate(payloadsPath)>
        </cfif>
        <cfif not directoryExists(archivePath)>
            <cfset directoryCreate(archivePath)>
        </cfif>
        <cfif not directoryExists(runtimeServersPath)>
            <cfset directoryCreate(runtimeServersPath)>
        </cfif>

        <!--- Archive leftover payloads from prior session if enabled --->
        <cfif this.archiveOnStartup and fileExists(expandPath("api2/_archive-helper.cfm"))>
            <cfinclude template="api2/_archive-helper.cfm">
        </cfif>

        <!--- Generate runtime server configs from templates --->
        <cfif fileExists(expandPath("api2/_server-config-helper.cfm"))>
            <cfinclude template="api2/_server-config-helper.cfm">
        </cfif>

        <!--- Initialize heartbeat tracking --->
        <cfset application.lastHeartbeat = now()>

        <cfreturn true>
    </cffunction>

    <cffunction name="onRequestStart" returntype="boolean" output="true">
        <cfargument name="targetPage" type="string" required="true">

        <!--- ===== IP ALLOWLIST CHECK ===== --->
        <cfset var ipAllowed = false>
        <cfset var remoteIP = CGI.REMOTE_ADDR>
        <cfset var ipList = this.allowedIPs>

        <!--- Wildcard: allow all --->
        <cfif listFind(ipList, "*")>
            <cfset ipAllowed = true>
        <cfelse>
            <cfloop list="#ipList#" index="local.allowedIP">
                <cfset local.allowedIP = trim(local.allowedIP)>
                <!--- Exact match --->
                <cfif remoteIP eq local.allowedIP>
                    <cfset ipAllowed = true>
                    <cfbreak>
                </cfif>
                <!--- Starts-with match --->
                <cfif left(remoteIP, len(local.allowedIP)) eq local.allowedIP>
                    <cfset ipAllowed = true>
                    <cfbreak>
                </cfif>
            </cfloop>
        </cfif>

        <cfif not ipAllowed>
            <cfcontent type="text/html" reset="true">
            <cfoutput>
                <h2>Access Denied</h2>
                <p>Your IP address is <strong>#encodeForHTML(remoteIP)#</strong>.</p>
                <p>Contact an administrator to be added to the allowlist.</p>
            </cfoutput>
            <cfreturn false>
        </cfif>

        <!--- ===== BLOCK DIRECT ACCESS TO _payloads/ ===== --->
        <cfif findNoCase("/_payloads/", arguments.targetPage) eq 1
              or findNoCase("\_payloads\", arguments.targetPage) eq 1>
            <!--- Allow if the shared secret token is present (server-to-server cfhttp) --->
            <cfif structKeyExists(url, "_pt") and url._pt eq this.payloadToken>
                <!--- Allowed: this is a server-to-server execution request --->
            <cfelseif structKeyExists(CGI, "HTTP_X_PAYLOAD_TOKEN") and CGI.HTTP_X_PAYLOAD_TOKEN eq this.payloadToken>
                <!--- Allowed via header --->
            <cfelse>
                <cfcontent type="text/html" reset="true">
                <cfoutput>
                    <h2>Access Denied</h2>
                    <p>Direct access to this directory is not permitted.</p>
                </cfoutput>
                <cfreturn false>
            </cfif>
        </cfif>

        <!--- ===== HEARTBEAT: check if server-side poll is due ===== --->
        <cfif structKeyExists(application, "lastHeartbeat")
              and dateDiff("s", application.lastHeartbeat, now()) gte application.config.serverPollInterval
              and fileExists(expandPath("api2/_heartbeat-helper.cfm"))>
            <cfset application.lastHeartbeat = now()>
            <cfinclude template="api2/_heartbeat-helper.cfm">
        </cfif>

        <cfreturn true>
    </cffunction>

</cfcomponent>
```

- [ ] **Step 3: Create the `www/api2/Application.cfc` for JSON responses**

This inherits the root Application.cfc and wraps all API responses as JSON with the correct content type.

```cfm
<cfcomponent extends="Application" output="false">

    <cffunction name="onRequestStart" returntype="boolean" output="false">
        <cfargument name="targetPage" type="string" required="true">

        <!--- Call parent onRequestStart for IP check and path blocking --->
        <cfset var parentResult = super.onRequestStart(arguments.targetPage)>
        <cfif not parentResult>
            <cfreturn false>
        </cfif>

        <!--- Skip helper files (prefixed with underscore) — they are cfinclude only --->
        <cfif left(listLast(arguments.targetPage, "/\"), 1) eq "_">
            <cfcontent type="text/html" reset="true">
            <cfoutput>
                <h2>Access Denied</h2>
                <p>Direct access to this file is not permitted.</p>
            </cfoutput>
            <cfreturn false>
        </cfif>

        <!--- Set JSON content type for all api2 responses --->
        <cfcontent type="application/json" reset="true">

        <cfreturn true>
    </cffunction>

</cfcomponent>
```

- [ ] **Step 4: Create directory scaffolding**

Run these commands to create the empty directories the app expects:

```bash
mkdir -p C:/commandbox/ai/cffiddle/www/_payloads
mkdir -p C:/commandbox/ai/cffiddle/www/api2
mkdir -p C:/commandbox/ai/cffiddle/www/assets/css
mkdir -p C:/commandbox/ai/cffiddle/www/assets/js
mkdir -p C:/commandbox/ai/cffiddle/archive
mkdir -p C:/commandbox/ai/cffiddle/runtime/servers
mkdir -p C:/commandbox/ai/cffiddle/snippets
```

- [ ] **Step 5: Verify by starting a host engine and hitting the IP gate**

Start one of the existing engines (e.g., cf2025) and navigate to `http://cf2025.local:2025/`. You should see an empty page (no index.cfm yet, but no error — the Application.cfc should load without errors). If you access from a non-localhost IP, you should see the "Access Denied" message.

- [ ] **Step 6: Commit**

```bash
git add www/Application.cfc www/api2/Application.cfc snippets/Application.cfc
git commit -m "feat: add Application.cfc security gates with IP allowlist and path blocking"
```

---

## Task 2: Server Config Generation Helper

**Files:**
- Create: `www/api2/_server-config-helper.cfm`

This helper is `cfinclude`d by `Application.cfc` on startup. It reads each template `server.json` from `current-servers/`, clones it with JSONUtil, applies the `cffiddle-` name prefix, and writes the generated config to `runtime/servers/`.

- [ ] **Step 1: Create `www/api2/_server-config-helper.cfm`**

```cfm
<!---
    _server-config-helper.cfm
    Included by Application.cfc onApplicationStart.
    Reads template server.json files, clones them with a unique name prefix,
    and writes generated configs to runtime/servers/.
--->
<cfset var templateDir = expandPath(application.config.templateServersDir)>
<cfset var runtimeDir = expandPath(application.config.runtimeServersDir)>
<cfset var jsonUtil = application.jsonUtil>

<!--- Scan for server.*.json files in the template directory --->
<cfdirectory
    action="list"
    directory="#templateDir#"
    filter="server.*.json"
    name="local.templateFiles"
    type="file">

<!--- Build the server registry in application scope --->
<cfset application.serverRegistry = [:]>

<cfloop query="local.templateFiles">
    <cfset var templatePath = templateDir & "/" & local.templateFiles.name>
    <cfset var configJSON = fileRead(templatePath, "utf-8")>
    <cfset var config = jsonUtil.deserializeJSON(configJSON)>

    <!--- Extract the original server name --->
    <cfset var originalName = config["name"]>
    <cfset var runtimeName = application.config.serverNamePrefix & originalName>

    <!--- Clone: update the name to avoid collisions --->
    <cfset config["name"] = runtimeName>

    <!--- Write the runtime config --->
    <cfset var runtimePath = runtimeDir & "/server." & originalName & ".json">
    <cfset var outputJSON = jsonUtil.serializeJSON(config)>
    <cfset fileWrite(runtimePath, outputJSON, "utf-8")>

    <!--- Register the server in application scope --->
    <cfset application.serverRegistry["#originalName#"] = [:]>
    <cfset application.serverRegistry[originalName]["name"] = originalName>
    <cfset application.serverRegistry[originalName]["runtimeName"] = runtimeName>
    <cfset application.serverRegistry[originalName]["cfengine"] = config["app"]["cfengine"]>
    <cfset application.serverRegistry[originalName]["host"] = config["web"]["hostAlias"]>
    <cfset application.serverRegistry[originalName]["port"] = config["web"]["HTTP"]["port"]>
    <cfset application.serverRegistry[originalName]["runtimeConfigPath"] = runtimePath>
    <cfset application.serverRegistry[originalName]["templateConfigPath"] = templatePath>

    <!--- Initialize status entry --->
    <cfset application.serverStatuses["#originalName#"] = [:]>
    <cfset application.serverStatuses[originalName]["name"] = originalName>
    <cfset application.serverStatuses[originalName]["cfengine"] = config["app"]["cfengine"]>
    <cfset application.serverStatuses[originalName]["host"] = config["web"]["hostAlias"]>
    <cfset application.serverStatuses[originalName]["port"] = config["web"]["HTTP"]["port"]>
    <cfset application.serverStatuses[originalName]["status"] = "offline">
    <cfset application.serverStatuses[originalName]["lastChecked"] = "">
</cfloop>
```

- [ ] **Step 2: Verify by restarting the app**

Reinitialize the application (add `?reinit=1` support or restart the engine). Check that `runtime/servers/` now contains cloned server.json files with `cffiddle-` prefixed names.

- [ ] **Step 3: Commit**

```bash
git add www/api2/_server-config-helper.cfm
git commit -m "feat: add server config generation helper — clones templates to runtime with name prefix"
```

---

## Task 3: Heartbeat Helper

**Files:**
- Create: `www/api2/_heartbeat-helper.cfm`

This helper is `cfinclude`d by `Application.cfc` on each request when the poll interval has elapsed. It checks each registered server with a lightweight HTTP request.

- [ ] **Step 1: Create `www/api2/_heartbeat-helper.cfm`**

```cfm
<!---
    _heartbeat-helper.cfm
    Included by Application.cfc onRequestStart when heartbeat interval has elapsed.
    Pings each registered server to determine online/offline status.
--->
<cfloop collection="#application.serverRegistry#" item="local.serverKey">
    <cfset var serverInfo = application.serverRegistry[local.serverKey]>
    <cfset var statusEntry = application.serverStatuses[local.serverKey]>
    <cfset var pingURL = "http://#serverInfo['host']#:#serverInfo['port']#/">

    <cftry>
        <cfhttp url="#pingURL#" method="HEAD" timeout="5" result="local.pingResult">
        </cfhttp>

        <cfif val(local.pingResult.statusCode) gte 200 and val(local.pingResult.statusCode) lt 500>
            <cfset statusEntry["status"] = "online">
        <cfelse>
            <cfset statusEntry["status"] = "offline">
        </cfif>
    <cfcatch type="any">
        <cfset statusEntry["status"] = "offline">
    </cfcatch>
    </cftry>

    <cfset statusEntry["lastChecked"] = dateTimeFormat(now(), "yyyy-MM-dd'T'HH:nn:ss.lllZ")>
</cfloop>
```

- [ ] **Step 2: Verify heartbeat is running**

Restart the app, then make a request. After the first poll interval passes, make another request. Check that `application.serverStatuses` is populated (you can temporarily dump it from index.cfm to verify).

- [ ] **Step 3: Commit**

```bash
git add www/api2/_heartbeat-helper.cfm
git commit -m "feat: add heartbeat helper — polls server status on configurable interval"
```

---

## Task 4: Archive Helper

**Files:**
- Create: `www/api2/_archive-helper.cfm`

This helper archives `.cfm` files from `_payloads/` into ZIP files grouped by `yyyymm` prefix, named with the current timestamp.

- [ ] **Step 1: Create `www/api2/_archive-helper.cfm`**

```cfm
<!---
    _archive-helper.cfm
    Included by Application.cfc onApplicationStart (if archiveOnStartup)
    and by session-clear.cfm.
    Archives .cfm files from _payloads/ into ZIP files in archive/.
    Groups files by yyyymm prefix; names ZIPs with current timestamp + group month.
--->
<cfset var payloadsPath = expandPath(application.config.payloadsDir)>
<cfset var archivePath = expandPath(application.config.archiveDir)>

<!--- Scan for .cfm files in _payloads/ --->
<cfdirectory
    action="list"
    directory="#payloadsPath#"
    filter="*.cfm"
    name="local.payloadFiles"
    type="file"
    sort="name asc">

<cfif local.payloadFiles.recordCount eq 0>
    <!--- Nothing to archive --->
<cfelse>
    <!--- Group files by yyyymm prefix (first 6 chars of filename) --->
    <cfset var groups = [:]>
    <cfloop query="local.payloadFiles">
        <cfset var fileName = local.payloadFiles.name>
        <cfset var groupKey = left(fileName, 6)>
        <cfif not structKeyExists(groups, groupKey)>
            <cfset groups[groupKey] = []>
        </cfif>
        <cfset arrayAppend(groups[groupKey], fileName)>
    </cfloop>

    <!--- Create a ZIP for each group --->
    <cfset var currentTimestamp = dateTimeFormat(now(), "yyyyMMddHHnnsslll")>
    <cfloop collection="#groups#" item="local.groupMonth">
        <cfset var zipName = currentTimestamp & "-" & local.groupMonth & ".zip">
        <cfset var zipPath = archivePath & "/" & zipName>

        <cfzip action="zip" file="#zipPath#" overwrite="true">
            <cfloop array="#groups[local.groupMonth]#" index="local.cfmFile">
                <cfzipparam source="#payloadsPath#/#local.cfmFile#" entrypath="#local.cfmFile#">
            </cfloop>
        </cfzip>

        <!--- Delete the source files after successful ZIP --->
        <cfloop array="#groups[local.groupMonth]#" index="local.cfmFile">
            <cfset fileDelete(payloadsPath & "/" & local.cfmFile)>
        </cfloop>
    </cfloop>
</cfif>
```

- [ ] **Step 2: Test by creating a dummy payload file**

Create a test file in `www/_payloads/202604081200000000-test-uuid.cfm` with dummy content. Restart the app (triggering `archiveOnStartup`). Verify:
- The file is gone from `_payloads/`
- A ZIP file exists in `archive/` with the pattern `yyyymmddHHnnsslll-202604.zip`
- The ZIP contains the original file

- [ ] **Step 3: Commit**

```bash
git add www/api2/_archive-helper.cfm
git commit -m "feat: add archive helper — zips payloads grouped by month with timestamped names"
```

---

## Task 5: Server Status API Endpoint

**Files:**
- Create: `www/api2/servers.cfm`

Returns the cached server status map as JSON. This is what the browser polls.

- [ ] **Step 1: Create `www/api2/servers.cfm`**

```cfm
<!---
    servers.cfm
    Returns the cached server statuses as JSON.
    The browser polls this endpoint on clientPollInterval.
--->
<cfset var jsonUtil = application.jsonUtil>

<cfset var response = [:]>
<cfset response["success"] = true>
<cfset response["timestamp"] = dateTimeFormat(now(), "yyyy-MM-dd'T'HH:nn:ss.lllZ")>
<cfset response["pollInterval"] = application.config.clientPollInterval>
<cfset response["servers"] = application.serverStatuses>

<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
```

- [ ] **Step 2: Verify by hitting the endpoint**

Navigate to `http://[host-engine]:[port]/api2/servers.cfm` in a browser. You should see a JSON response with server statuses (all offline initially since no target engines are started). Verify the content type is `application/json`.

- [ ] **Step 3: Commit**

```bash
git add www/api2/servers.cfm
git commit -m "feat: add servers.cfm API endpoint — returns cached server statuses as JSON"
```

---

## Task 6: Server Start/Stop API Endpoints

**Files:**
- Create: `www/api2/server-start.cfm`
- Create: `www/api2/server-stop.cfm`

Fire-and-forget CommandBox server start/stop commands.

- [ ] **Step 1: Create `www/api2/server-start.cfm`**

```cfm
<!---
    server-start.cfm
    Starts a CommandBox server using its runtime config.
    Expects: url.server (server key name, e.g., "cf2025")
    Returns immediately (fire-and-forget).
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<cfif not structKeyExists(url, "server") or not structKeyExists(application.serverRegistry, url.server)>
    <cfset response["success"] = false>
    <cfset response["error"] = "Invalid or missing server parameter.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var serverKey = url.server>
<cfset var serverInfo = application.serverRegistry[serverKey]>
<cfset var configPath = serverInfo["runtimeConfigPath"]>

<!--- Update status to "starting" --->
<cfset application.serverStatuses[serverKey]["status"] = "starting">
<cfset application.serverStatuses[serverKey]["lastChecked"] = dateTimeFormat(now(), "yyyy-MM-dd'T'HH:nn:ss.lllZ")>

<!--- Fire CommandBox server start in the background --->
<cfthread name="startServer_#serverKey#_#createUUID()#" serverKey="#serverKey#" configPath="#configPath#">
    <cfexecute
        name="box.exe"
        arguments="server start serverConfigFile=#attributes.configPath#"
        timeout="300">
    </cfexecute>
</cfthread>

<cfset response["success"] = true>
<cfset response["message"] = "Server '#serverKey#' start command issued.">
<cfset response["server"] = serverKey>

<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
```

- [ ] **Step 2: Create `www/api2/server-stop.cfm`**

```cfm
<!---
    server-stop.cfm
    Stops a CommandBox server.
    Expects: url.server (server key name, e.g., "cf2025")
    Returns immediately (fire-and-forget).
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<cfif not structKeyExists(url, "server") or not structKeyExists(application.serverRegistry, url.server)>
    <cfset response["success"] = false>
    <cfset response["error"] = "Invalid or missing server parameter.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var serverKey = url.server>
<cfset var serverInfo = application.serverRegistry[serverKey]>

<!--- Update status to "stopping" --->
<cfset application.serverStatuses[serverKey]["status"] = "stopping">
<cfset application.serverStatuses[serverKey]["lastChecked"] = dateTimeFormat(now(), "yyyy-MM-dd'T'HH:nn:ss.lllZ")>

<!--- Fire CommandBox server stop in the background --->
<cfthread name="stopServer_#serverKey#_#createUUID()#" serverKey="#serverKey#" runtimeName="#serverInfo['runtimeName']#">
    <cfexecute
        name="box.exe"
        arguments="server stop #attributes.runtimeName#"
        timeout="120">
    </cfexecute>
</cfthread>

<cfset response["success"] = true>
<cfset response["message"] = "Server '#serverKey#' stop command issued.">
<cfset response["server"] = serverKey>

<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
```

- [ ] **Step 3: Verify by starting a server**

Hit `http://[host]:[port]/api2/server-start.cfm?server=lucee7` in a browser. Verify:
- JSON response with `success: true`
- Server status changes to "starting" in `api2/servers.cfm`
- After a minute or so, the heartbeat detects it as "online"

- [ ] **Step 4: Verify by stopping the server**

Hit `http://[host]:[port]/api2/server-stop.cfm?server=lucee7`. Verify status transitions to "stopping" then eventually "offline".

- [ ] **Step 5: Commit**

```bash
git add www/api2/server-start.cfm www/api2/server-stop.cfm
git commit -m "feat: add server start/stop API endpoints — fire-and-forget CommandBox commands"
```

---

## Task 7: Code Execution API Endpoint

**Files:**
- Create: `www/api2/execute.cfm`

The core endpoint: receives CFML payload, writes to `_payloads/`, executes via cfhttp on target engine(s), returns results.

- [ ] **Step 1: Create `www/api2/execute.cfm`**

```cfm
<!---
    execute.cfm
    Receives CFML payload and target engine(s), executes via cfhttp.
    Expects:
      form.code    — the CFML source code
      form.engine  — target engine key (e.g., "cf2025") or "all" for all online
    Returns JSON with execution results.
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<!--- Validate inputs --->
<cfif not structKeyExists(form, "code") or not len(trim(form.code))>
    <cfset response["success"] = false>
    <cfset response["error"] = "No code provided.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfif not structKeyExists(form, "engine") or not len(trim(form.engine))>
    <cfset response["success"] = false>
    <cfset response["error"] = "No engine specified.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var code = form.code>
<cfset var engineParam = trim(form.engine)>
<cfset var payloadsPath = expandPath(application.config.payloadsDir)>

<!--- Generate the payload filename: yyyymmddhhNNsslll-UUID.cfm --->
<cfset var timestamp = dateTimeFormat(now(), "yyyyMMddHHnnsslll")>
<cfset var requestId = createUUID()>
<cfset var fileName = timestamp & "-" & requestId & ".cfm">
<cfset var filePath = payloadsPath & "/" & fileName>

<!--- Write the payload file --->
<cfset fileWrite(filePath, code, "utf-8")>

<!--- Determine target engines --->
<cfset var targetEngines = []>
<cfif engineParam eq "all">
    <cfloop collection="#application.serverStatuses#" item="local.sKey">
        <cfif application.serverStatuses[local.sKey]["status"] eq "online">
            <cfset arrayAppend(targetEngines, local.sKey)>
        </cfif>
    </cfloop>
<cfelse>
    <cfif structKeyExists(application.serverRegistry, engineParam)>
        <cfset arrayAppend(targetEngines, engineParam)>
    <cfelse>
        <cfset response["success"] = false>
        <cfset response["error"] = "Unknown engine: " & encodeForHTML(engineParam)>
        <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
        <cfabort>
    </cfif>
</cfif>

<!--- Execute on each target engine --->
<cfset var results = []>
<cfset var execTimeout = application.config.executionTimeout>
<cfif execTimeout eq 0>
    <cfset execTimeout = 300><!--- default cfhttp timeout when disabled --->
</cfif>

<cfloop array="#targetEngines#" index="local.engineKey">
    <cfset var engineInfo = application.serverRegistry[local.engineKey]>
    <cfset var execURL = "http://#engineInfo['host']#:#engineInfo['port']#/#application.config.payloadsDir#/#fileName#?_pt=#application.config.payloadToken#">

    <cfset var result = [:]>
    <cfset result["requestId"] = requestId>
    <cfset result["timestamp"] = dateTimeFormat(now(), "yyyy-MM-dd'T'HH:nn:ss.lllZ")>
    <cfset result["engine"] = local.engineKey>
    <cfset result["cfengine"] = engineInfo["cfengine"]>

    <cfset var startTick = getTickCount()>

    <cftry>
        <cfhttp url="#execURL#" method="GET" timeout="#execTimeout#" result="local.httpResult">
            <cfhttpparam type="header" name="X-Payload-Token" value="#application.config.payloadToken#">
        </cfhttp>

        <cfset var duration = getTickCount() - startTick>
        <cfset result["duration"] = duration>

        <cfif val(local.httpResult.statusCode) gte 200 and val(local.httpResult.statusCode) lt 400>
            <cfset result["success"] = true>
            <cfset result["output"] = local.httpResult.fileContent>
        <cfelse>
            <!--- Uncaught error: normalize --->
            <cfset result["success"] = false>
            <cfset var errorBody = local.httpResult.fileContent>
            <cfset result["error"] = [:]>
            <cfset result["error"]["statusCode"] = local.httpResult.statusCode>
            <cfset result["error"]["message"] = _normalizeError(errorBody)>
            <cfset result["error"]["raw"] = errorBody>
        </cfif>
    <cfcatch type="any">
        <cfset var duration = getTickCount() - startTick>
        <cfset result["duration"] = duration>
        <cfset result["success"] = false>
        <cfset result["error"] = [:]>
        <cfset result["error"]["statusCode"] = "0">
        <cfset result["error"]["message"] = cfcatch.message>
        <cfif structKeyExists(cfcatch, "detail")>
            <cfset result["error"]["detail"] = cfcatch.detail>
        </cfif>
    </cfcatch>
    </cftry>

    <cfset arrayAppend(results, result)>
</cfloop>

<cfset response["success"] = true>
<cfset response["results"] = results>
<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>

<!--- Helper: extract meaningful error from HTML error pages --->
<cffunction name="_normalizeError" access="private" returntype="string" output="false">
    <cfargument name="errorHTML" type="string" required="true">
    <cfset var msg = arguments.errorHTML>

    <!--- Try to extract text from common error page patterns --->
    <!--- Adobe CF: look for <title> or <b> with error message --->
    <cfset var titleMatch = reFind("<title[^>]*>([^<]+)</title>", msg, 1, true)>
    <cfif titleMatch.pos[1] gt 0 and arrayLen(titleMatch.pos) gte 2 and titleMatch.pos[2] gt 0>
        <cfreturn mid(msg, titleMatch.pos[2], titleMatch.len[2])>
    </cfif>

    <!--- Strip HTML tags as fallback --->
    <cfset msg = reReplace(msg, "<[^>]+>", " ", "all")>
    <cfset msg = reReplace(msg, "\s+", " ", "all")>
    <cfset msg = trim(msg)>

    <!--- Truncate if too long --->
    <cfif len(msg) gt 500>
        <cfset msg = left(msg, 500) & "...">
    </cfif>

    <cfreturn msg>
</cffunction>
```

- [ ] **Step 2: Verify execution against a running engine**

Start a target engine. Use curl or a browser tool to POST:
```
POST http://[host]:[port]/api2/execute.cfm
Content-Type: application/x-www-form-urlencoded

code=<cfscript>writeOutput("Hello from CFFiddle!");</cfscript>&engine=cf2025
```

Verify:
- JSON response with `success: true`
- `results` array with one entry containing `output: "Hello from CFFiddle!"`
- `requestId`, `timestamp`, and `duration` are populated
- A `.cfm` file exists in `www/_payloads/`

- [ ] **Step 3: Verify error normalization**

POST code with a syntax error:
```
code=<cfscript>writeOutput(;</cfscript>&engine=cf2025
```

Verify the response has `success: false` with a normalized error message.

- [ ] **Step 4: Commit**

```bash
git add www/api2/execute.cfm
git commit -m "feat: add execute.cfm API endpoint — proxies CFML execution to target engines"
```

---

## Task 8: Snippets API Endpoints

**Files:**
- Create: `www/api2/snippets.cfm`
- Create: `www/api2/snippet-load.cfm`

- [ ] **Step 1: Create `www/api2/snippets.cfm`**

```cfm
<!---
    snippets.cfm
    Returns a list of available snippet files from the snippets/ directory.
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var snippetsPath = expandPath(application.config.snippetsDir)>
<cfset var response = [:]>

<cfif not directoryExists(snippetsPath)>
    <cfset response["success"] = true>
    <cfset response["snippets"] = []>
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfdirectory
    action="list"
    directory="#snippetsPath#"
    name="local.files"
    type="file"
    sort="name asc">

<!--- Filter to text-based files, exclude Application.cfc --->
<cfset var snippets = []>
<cfset var allowedExtensions = "cfm,cfml,cfc,json,md,txt,html,htm,xml,sql,css,js">

<cfloop query="local.files">
    <cfset var ext = listLast(local.files.name, ".")>
    <cfif listFindNoCase(allowedExtensions, ext) and local.files.name neq "Application.cfc">
        <cfset var entry = [:]>
        <cfset entry["name"] = local.files.name>
        <cfset entry["size"] = local.files.size>
        <cfset arrayAppend(snippets, entry)>
    </cfif>
</cfloop>

<cfset response["success"] = true>
<cfset response["snippets"] = snippets>
<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
```

- [ ] **Step 2: Create `www/api2/snippet-load.cfm`**

```cfm
<!---
    snippet-load.cfm
    Returns the content of a selected snippet file.
    Expects: url.file (filename only, no path traversal allowed)
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<cfif not structKeyExists(url, "file") or not len(trim(url.file))>
    <cfset response["success"] = false>
    <cfset response["error"] = "No file specified.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<!--- Security: strip any path components — only allow bare filenames --->
<cfset var fileName = listLast(replace(url.file, "\", "/", "all"), "/")>

<!--- Reject if filename contains suspicious characters --->
<cfif reFind("[^a-zA-Z0-9._\-]", fileName)>
    <cfset response["success"] = false>
    <cfset response["error"] = "Invalid filename.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var snippetsPath = expandPath(application.config.snippetsDir)>
<cfset var filePath = snippetsPath & "/" & fileName>

<cfif not fileExists(filePath)>
    <cfset response["success"] = false>
    <cfset response["error"] = "File not found: " & encodeForHTML(fileName)>
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var content = fileRead(filePath, "utf-8")>

<cfset response["success"] = true>
<cfset response["file"] = fileName>
<cfset response["content"] = content>
<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
```

- [ ] **Step 3: Test by creating a sample snippet**

Create `snippets/hello.cfm` with content:
```cfm
<cfscript>
writeOutput("Hello World!");
</cfscript>
```

Hit `api2/snippets.cfm` — should list `hello.cfm`.
Hit `api2/snippet-load.cfm?file=hello.cfm` — should return the file content.

- [ ] **Step 4: Commit**

```bash
git add www/api2/snippets.cfm www/api2/snippet-load.cfm
git commit -m "feat: add snippets API endpoints — list and load snippet files"
```

---

## Task 9: Session Clear & Config API Endpoints

**Files:**
- Create: `www/api2/session-clear.cfm`
- Create: `www/api2/config.cfm`

- [ ] **Step 1: Create `www/api2/session-clear.cfm`**

```cfm
<!---
    session-clear.cfm
    Archives .cfm files from _payloads/ and clears the directory.
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<cftry>
    <cfinclude template="_archive-helper.cfm">

    <cfset response["success"] = true>
    <cfset response["message"] = "Session cleared and files archived.">
<cfcatch type="any">
    <cfset response["success"] = false>
    <cfset response["error"] = cfcatch.message>
</cfcatch>
</cftry>

<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
```

- [ ] **Step 2: Create `www/api2/config.cfm`**

```cfm
<!---
    config.cfm
    GET: Returns current runtime config.
    POST: Updates mutable config values (executionTimeout).
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<!--- Handle POST: update mutable config values --->
<cfif CGI.REQUEST_METHOD eq "POST">
    <cfif structKeyExists(form, "executionTimeout") and isNumeric(form.executionTimeout)>
        <cfset application.config.executionTimeout = int(form.executionTimeout)>
    </cfif>
    <cfset response["success"] = true>
    <cfset response["message"] = "Configuration updated.">
<cfelse>
    <cfset response["success"] = true>
</cfif>

<!--- Always return current config --->
<cfset response["config"] = [:]>
<cfset response["config"]["executionTimeout"] = application.config.executionTimeout>
<cfset response["config"]["clientPollInterval"] = application.config.clientPollInterval>
<cfset response["config"]["startupTimeout"] = application.config.startupTimeout>
<cfset response["config"]["editorTheme"] = application.config.editorTheme>

<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
```

- [ ] **Step 3: Test session clear**

Create a dummy file in `_payloads/`, hit `api2/session-clear.cfm`, verify the file is archived and deleted.

- [ ] **Step 4: Test config endpoint**

GET `api2/config.cfm` — should return current config.
POST `api2/config.cfm` with `executionTimeout=30` — should update and return the new value.

- [ ] **Step 5: Commit**

```bash
git add www/api2/session-clear.cfm www/api2/config.cfm
git commit -m "feat: add session-clear and config API endpoints"
```

---

## Task 10: Main UI — HTML Shell & Ace Editor

**Files:**
- Create: `www/index.cfm`
- Create: `www/assets/css/style.css`

This task builds the static HTML structure and initializes the Ace Editor. No AJAX wiring yet — that comes in the next task.

- [ ] **Step 1: Create `www/assets/css/style.css`**

```css
/* ===== Reset & Base ===== */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #1e1e1e;
    color: #d4d4d4;
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

/* ===== Top Bar ===== */
.top-bar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 16px;
    background: #2d2d2d;
    border-bottom: 1px solid #404040;
    flex-wrap: wrap;
}
.top-bar h1 {
    font-size: 16px;
    font-weight: 600;
    color: #e0e0e0;
    margin-right: auto;
}
.top-bar select, .top-bar input, .top-bar button {
    font-size: 13px;
    padding: 4px 8px;
    background: #3c3c3c;
    color: #d4d4d4;
    border: 1px solid #555;
    border-radius: 3px;
}
.top-bar button:hover { background: #4c4c4c; cursor: pointer; }
.top-bar label { font-size: 12px; color: #aaa; }

/* ===== Status Indicators ===== */
.status-bar {
    display: flex;
    gap: 8px;
    align-items: center;
    cursor: pointer;
}
.status-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    display: inline-block;
    position: relative;
}
.status-dot.online { background: #4caf50; }
.status-dot.offline { background: #666; }
.status-dot.starting, .status-dot.stopping {
    background: #ff9800;
    animation: pulse 1s infinite;
}
@keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
}
.status-dot-label {
    font-size: 11px;
    color: #aaa;
}

/* ===== Editor Panel ===== */
.editor-panel { flex: 1; min-height: 200px; position: relative; }
#editor { position: absolute; top: 0; right: 0; bottom: 0; left: 0; }

/* ===== Controls Bar ===== */
.controls-bar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 16px;
    background: #2d2d2d;
    border-top: 1px solid #404040;
    border-bottom: 1px solid #404040;
}
.controls-bar select {
    font-size: 13px;
    padding: 4px 8px;
    background: #3c3c3c;
    color: #d4d4d4;
    border: 1px solid #555;
    border-radius: 3px;
}
.btn-run {
    padding: 6px 16px;
    font-size: 13px;
    font-weight: 600;
    border: none;
    border-radius: 3px;
    cursor: pointer;
}
.btn-run-single { background: #0e639c; color: #fff; }
.btn-run-single:hover { background: #1177bb; }
.btn-run-all { background: #388e3c; color: #fff; }
.btn-run-all:hover { background: #43a047; }

/* ===== Results Panel ===== */
.results-panel {
    flex: 1;
    min-height: 150px;
    overflow-y: auto;
    padding: 0;
    background: #1e1e1e;
}
.result-card {
    border: 1px solid #404040;
    margin: 8px;
    border-radius: 4px;
    overflow: hidden;
}
.result-header {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 12px;
    background: #2d2d2d;
    font-size: 12px;
    color: #aaa;
}
.result-header .engine-name { color: #569cd6; font-weight: 600; }
.result-header .duration { color: #dcdcaa; }
.result-body {
    padding: 12px;
    background: #fff;
    color: #000;
    font-size: 14px;
    overflow-x: auto;
}
.result-body.source-view {
    background: #1e1e1e;
    color: #d4d4d4;
    font-family: monospace;
    white-space: pre-wrap;
}
.result-body.error-view {
    background: #2d1515;
    color: #f48771;
    font-family: monospace;
    white-space: pre-wrap;
}
.btn-source-toggle {
    font-size: 11px;
    padding: 2px 8px;
    background: #3c3c3c;
    color: #aaa;
    border: 1px solid #555;
    border-radius: 3px;
    cursor: pointer;
    margin-left: auto;
}
.btn-source-toggle:hover { background: #4c4c4c; }

/* ===== Display Mode Toggle ===== */
.display-mode-toggle {
    display: flex;
    gap: 4px;
    padding: 8px 16px;
}
.display-mode-toggle button {
    font-size: 11px;
    padding: 3px 10px;
    background: #3c3c3c;
    color: #aaa;
    border: 1px solid #555;
    border-radius: 3px;
    cursor: pointer;
}
.display-mode-toggle button.active { background: #0e639c; color: #fff; border-color: #0e639c; }

.results-container.side-by-side {
    display: flex;
    flex-wrap: wrap;
    gap: 0;
}
.results-container.side-by-side .result-card {
    flex: 1 1 calc(50% - 16px);
    min-width: 300px;
}
.results-container.tabbed .result-card { display: none; }
.results-container.tabbed .result-card.active { display: block; }
.tab-bar {
    display: none;
    gap: 4px;
    padding: 8px 16px 0;
}
.results-container.tabbed ~ .tab-bar,
.tabbed-active .tab-bar { display: flex; }
.tab-bar button {
    font-size: 12px;
    padding: 4px 12px;
    background: #3c3c3c;
    color: #aaa;
    border: 1px solid #555;
    border-radius: 3px 3px 0 0;
    cursor: pointer;
}
.tab-bar button.active { background: #2d2d2d; color: #d4d4d4; border-bottom-color: #2d2d2d; }

/* ===== Admin Modal ===== */
.modal-overlay {
    display: none;
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0,0,0,0.6);
    z-index: 1000;
    justify-content: center;
    align-items: center;
}
.modal-overlay.open { display: flex; }
.modal {
    background: #2d2d2d;
    border: 1px solid #555;
    border-radius: 8px;
    padding: 24px;
    min-width: 500px;
    max-width: 800px;
    max-height: 80vh;
    overflow-y: auto;
}
.modal h2 { font-size: 18px; margin-bottom: 16px; color: #e0e0e0; }
.server-card {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px;
    border: 1px solid #404040;
    border-radius: 4px;
    margin-bottom: 8px;
    background: #252525;
}
.server-card .server-name { font-weight: 600; color: #569cd6; min-width: 100px; }
.server-card .server-engine { font-size: 12px; color: #aaa; min-width: 120px; }
.server-card .server-host { font-size: 12px; color: #888; min-width: 150px; }
.server-card .server-status { font-size: 12px; min-width: 80px; }
.server-card .server-status.online { color: #4caf50; }
.server-card .server-status.offline { color: #888; }
.server-card .server-status.starting { color: #ff9800; }
.server-card .server-status.stopping { color: #ff9800; }
.server-card button {
    font-size: 12px;
    padding: 4px 12px;
    border: 1px solid #555;
    border-radius: 3px;
    cursor: pointer;
    margin-left: auto;
}
.btn-start { background: #2e7d32; color: #fff; }
.btn-start:hover { background: #388e3c; }
.btn-stop { background: #c62828; color: #fff; }
.btn-stop:hover { background: #d32f2f; }
.btn-modal-close {
    float: right;
    background: none;
    border: none;
    color: #aaa;
    font-size: 20px;
    cursor: pointer;
}
.btn-modal-close:hover { color: #fff; }
.starting-counter { font-size: 12px; color: #ff9800; margin-left: 8px; }
.starting-warning { color: #f44336; font-size: 11px; }

/* ===== Splitter ===== */
.splitter {
    height: 5px;
    background: #404040;
    cursor: row-resize;
}
.splitter:hover { background: #0e639c; }
```

- [ ] **Step 2: Create `www/index.cfm`**

```cfm
<!--- Ensure Application.cfc has loaded config into application scope --->
<cfparam name="application.config.editorTheme" default="monokai">
<cfparam name="application.config.clientPollInterval" default="10">
<cfparam name="application.config.startupTimeout" default="60">
<cfparam name="application.config.executionTimeout" default="0">
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CommandBox CFFiddle</title>
    <link rel="stylesheet" href="assets/css/style.css">
</head>
<body>

    <!--- ===== Top Bar ===== --->
    <div class="top-bar">
        <h1>CFFiddle</h1>

        <label for="snippetSelect">Snippet:</label>
        <select id="snippetSelect">
            <option value="">-- none --</option>
        </select>

        <label for="timeoutInput">Timeout (s):</label>
        <cfoutput>
        <input type="number" id="timeoutInput" value="#application.config.executionTimeout#" min="0" style="width:60px" title="Execution timeout in seconds (0 = disabled)">
        </cfoutput>

        <button id="btnClearSession" title="Archive temp files and start a new session">Clear Session</button>

        <div class="status-bar" id="statusBar" title="Click to manage servers">
            <!--- Populated by JavaScript --->
        </div>
    </div>

    <!--- ===== Editor Panel ===== --->
    <div class="editor-panel" id="editorPanel">
        <div id="editor"><cfscript>
</cfscript></div>
    </div>

    <!--- ===== Splitter ===== --->
    <div class="splitter" id="splitter"></div>

    <!--- ===== Controls Bar ===== --->
    <div class="controls-bar">
        <label for="engineSelect">Engine:</label>
        <select id="engineSelect">
            <option value="">-- select --</option>
        </select>
        <button class="btn-run btn-run-single" id="btnRun">Run</button>
        <button class="btn-run btn-run-all" id="btnRunAll">Run All Online</button>

        <div class="display-mode-toggle" id="displayModeToggle" style="margin-left:auto; display:none;">
            <button data-mode="stacked" class="active">Stacked</button>
            <button data-mode="side-by-side">Side by Side</button>
            <button data-mode="tabbed">Tabbed</button>
        </div>
    </div>

    <!--- ===== Tab Bar (for tabbed mode) ===== --->
    <div class="tab-bar" id="tabBar"></div>

    <!--- ===== Results Panel ===== --->
    <div class="results-panel">
        <div class="results-container" id="resultsContainer"></div>
    </div>

    <!--- ===== Admin Modal ===== --->
    <div class="modal-overlay" id="adminModal">
        <div class="modal">
            <button class="btn-modal-close" id="btnCloseModal">&times;</button>
            <h2>Server Management</h2>
            <div id="serverCards">
                <!--- Populated by JavaScript --->
            </div>
        </div>
    </div>

    <!--- ===== Ace Editor CDN ===== --->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ace.min.js" integrity="sha512-BHJlu9vUXVrcxhRwbBdNv3uTsbscp8pp3LJ5z/sw9nBJUegkNlkcZnvODRgynJWhXMCsVUGZlFuzTrr5I2X3sQ==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/theme-monokai.min.js" integrity="sha512-g9yptARGYXbHR9r3kTKIAzF+vvmgEieTxuuUUcHC5tKYFpLR3DR+lsisH2KZJG2Nwaou8jjYVRdbbbBQI3Bo5w==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ext-language_tools.min.js" integrity="sha512-pGeiKdzOOI7LQFQdSOoweS7JVXdwyKaigCy+04DZ34GzUI+9n0/vEg+pk1cVzN8owSr9c0X7dB/aCLNNvm3S5A==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-coldfusion.min.js" integrity="sha512-ZslkmZ4D+2Wp4LWOAhbRxIesLqGUK6TLOLAxwN6SXacAPnhulkda5MiachluWjqgC8fsbQahWWOe/VX+dsq4Cg==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/snippets/coldfusion.min.js" integrity="sha512-/q4t/H2FTC2kwXv+AMCZ+54UIdUFkjNxaSfhKRz982pbBAXHZzDRaH0k80QobC3Q4SNB6mi4/hc1s1btgoouNw==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-html.min.js" integrity="sha512-D64TbdwtINWYv5Qa8znJN5wDlSGYpzJGUXBJ82tt2Bmhq0V9qfH2u29AUMOKtzGlubvQnuGspZ0qKJX2XGLRaA==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>

    <!--- ===== App Config (passed from CFML to JS) ===== --->
    <cfoutput>
    <script>
        var APP_CONFIG = {
            clientPollInterval: #application.config.clientPollInterval# * 1000,
            startupTimeout: #application.config.startupTimeout#,
            editorTheme: "#encodeForJavaScript(application.config.editorTheme)#",
            executionTimeout: #application.config.executionTimeout#
        };
    </script>
    </cfoutput>

    <script src="assets/js/app.js"></script>
</body>
</html>
```

- [ ] **Step 3: Verify the page loads**

Navigate to `http://[host]:[port]/` in a browser. You should see:
- Dark-themed page with "CFFiddle" title bar
- Ace Editor with `<cfscript>\n</cfscript>` content and ColdFusion syntax highlighting
- Controls bar with empty engine dropdown, Run and Run All buttons
- Empty results panel

- [ ] **Step 4: Commit**

```bash
git add www/index.cfm www/assets/css/style.css
git commit -m "feat: add main UI shell with Ace Editor, results panel, and admin modal HTML"
```

---

## Task 11: Client-Side JavaScript — Core Wiring

**Files:**
- Create: `www/assets/js/app.js`

This is the main JavaScript file. It wires up: Ace Editor initialization, AJAX calls to all API endpoints, status polling, admin modal, display mode toggle, splitter, and snippets.

- [ ] **Step 1: Create `www/assets/js/app.js`**

```js
(function() {
    "use strict";

    // ===== Ace Editor Setup =====
    var editor = ace.edit("editor");
    editor.setTheme("ace/theme/" + APP_CONFIG.editorTheme);
    editor.session.setMode("ace/mode/coldfusion");
    editor.setOptions({
        enableBasicAutocompletion: true,
        enableSnippets: true,
        enableLiveAutocompletion: false,
        fontSize: "14px",
        showPrintMargin: false,
        wrap: true
    });
    // Place cursor inside the cfscript block
    editor.gotoLine(2, 0, false);
    editor.focus();

    // ===== DOM References =====
    var engineSelect = document.getElementById("engineSelect");
    var snippetSelect = document.getElementById("snippetSelect");
    var timeoutInput = document.getElementById("timeoutInput");
    var btnRun = document.getElementById("btnRun");
    var btnRunAll = document.getElementById("btnRunAll");
    var btnClearSession = document.getElementById("btnClearSession");
    var statusBar = document.getElementById("statusBar");
    var adminModal = document.getElementById("adminModal");
    var btnCloseModal = document.getElementById("btnCloseModal");
    var serverCards = document.getElementById("serverCards");
    var resultsContainer = document.getElementById("resultsContainer");
    var displayModeToggle = document.getElementById("displayModeToggle");
    var tabBar = document.getElementById("tabBar");

    var currentDisplayMode = "stacked";
    var serverStatuses = {};
    var startingTimers = {};

    // ===== AJAX Helper =====
    function ajax(method, url, data, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open(method, url, true);
        if (method === "POST") {
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                var resp;
                try { resp = JSON.parse(xhr.responseText); }
                catch(e) { resp = { success: false, error: xhr.responseText }; }
                callback(resp);
            }
        };
        xhr.send(data || null);
    }

    function encodeParams(obj) {
        var parts = [];
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) {
                parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(obj[key]));
            }
        }
        return parts.join("&");
    }

    // ===== Status Polling =====
    function pollServers() {
        ajax("GET", "api2/servers.cfm", null, function(resp) {
            if (resp.success && resp.servers) {
                serverStatuses = resp.servers;
                renderStatusBar();
                renderEngineDropdown();
                renderServerCards();
            }
        });
    }

    function renderStatusBar() {
        var html = "";
        for (var key in serverStatuses) {
            if (!serverStatuses.hasOwnProperty(key)) continue;
            var s = serverStatuses[key];
            html += '<span class="status-dot ' + s.status + '" title="' + key + ': ' + s.status + '"></span>';
            html += '<span class="status-dot-label">' + key + '</span>';
        }
        statusBar.innerHTML = html;
    }

    function renderEngineDropdown() {
        var current = engineSelect.value;
        var html = '<option value="">-- select --</option>';
        for (var key in serverStatuses) {
            if (!serverStatuses.hasOwnProperty(key)) continue;
            var s = serverStatuses[key];
            if (s.status === "online") {
                var sel = (key === current) ? " selected" : "";
                html += '<option value="' + key + '"' + sel + '>' + key + ' (' + s.cfengine + ')</option>';
            }
        }
        engineSelect.innerHTML = html;
    }

    // ===== Admin Modal =====
    statusBar.addEventListener("click", function() {
        adminModal.classList.add("open");
        renderServerCards();
    });
    btnCloseModal.addEventListener("click", function() {
        adminModal.classList.remove("open");
    });
    adminModal.addEventListener("click", function(e) {
        if (e.target === adminModal) adminModal.classList.remove("open");
    });

    function renderServerCards() {
        var html = "";
        for (var key in serverStatuses) {
            if (!serverStatuses.hasOwnProperty(key)) continue;
            var s = serverStatuses[key];
            html += '<div class="server-card">';
            html += '<span class="server-name">' + key + '</span>';
            html += '<span class="server-engine">' + s.cfengine + '</span>';
            html += '<span class="server-host">' + s.host + ':' + s.port + '</span>';
            html += '<span class="server-status ' + s.status + '">' + s.status;
            if (s.status === "starting" && startingTimers[key]) {
                var elapsed = startingTimers[key].elapsed;
                html += ' <span class="starting-counter">(' + elapsed + 's)</span>';
                if (elapsed >= APP_CONFIG.startupTimeout) {
                    html += ' <span class="starting-warning">Warning: exceeded timeout</span>';
                }
            }
            html += '</span>';

            if (s.status === "offline") {
                html += '<button class="btn-start" data-server="' + key + '">Start</button>';
            } else if (s.status === "online") {
                html += '<button class="btn-stop" data-server="' + key + '">Stop</button>';
            }
            html += '</div>';
        }
        serverCards.innerHTML = html;

        // Bind start/stop buttons
        var startBtns = serverCards.querySelectorAll(".btn-start");
        var stopBtns = serverCards.querySelectorAll(".btn-stop");
        for (var i = 0; i < startBtns.length; i++) {
            startBtns[i].addEventListener("click", handleStart);
        }
        for (var j = 0; j < stopBtns.length; j++) {
            stopBtns[j].addEventListener("click", handleStop);
        }
    }

    function handleStart(e) {
        var serverKey = e.target.getAttribute("data-server");
        ajax("GET", "api2/server-start.cfm?server=" + encodeURIComponent(serverKey), null, function(resp) {
            if (resp.success) {
                // Start a seconds counter
                startingTimers[serverKey] = { elapsed: 0, interval: null };
                startingTimers[serverKey].interval = setInterval(function() {
                    startingTimers[serverKey].elapsed++;
                    renderServerCards();
                    // Check if heartbeat has detected it as online
                    if (serverStatuses[serverKey] && serverStatuses[serverKey].status === "online") {
                        clearInterval(startingTimers[serverKey].interval);
                        delete startingTimers[serverKey];
                        renderServerCards();
                    }
                }, 1000);
                pollServers();
            }
        });
    }

    function handleStop(e) {
        var serverKey = e.target.getAttribute("data-server");
        ajax("GET", "api2/server-stop.cfm?server=" + encodeURIComponent(serverKey), null, function(resp) {
            if (resp.success) pollServers();
        });
    }

    // ===== Code Execution =====
    btnRun.addEventListener("click", function() {
        var engine = engineSelect.value;
        if (!engine) { alert("Please select an engine."); return; }
        executeCode(engine);
    });

    btnRunAll.addEventListener("click", function() {
        executeCode("all");
    });

    function executeCode(engine) {
        // Update timeout config if changed
        var timeout = parseInt(timeoutInput.value, 10) || 0;
        if (timeout !== APP_CONFIG.executionTimeout) {
            APP_CONFIG.executionTimeout = timeout;
            ajax("POST", "api2/config.cfm", encodeParams({ executionTimeout: timeout }), function() {});
        }

        var code = editor.getValue();
        btnRun.disabled = true;
        btnRunAll.disabled = true;
        resultsContainer.innerHTML = '<div style="padding:16px;color:#aaa;">Executing...</div>';

        ajax("POST", "api2/execute.cfm", encodeParams({ code: code, engine: engine }), function(resp) {
            btnRun.disabled = false;
            btnRunAll.disabled = false;
            if (resp.success && resp.results) {
                renderResults(resp.results);
            } else {
                resultsContainer.innerHTML = '<div class="result-card"><div class="result-body error-view">' +
                    escapeHtml(resp.error || "Unknown error") + '</div></div>';
            }
        });
    }

    // ===== Results Rendering =====
    function renderResults(results) {
        if (results.length > 1) {
            displayModeToggle.style.display = "flex";
        } else {
            displayModeToggle.style.display = "none";
        }

        var html = "";
        tabBar.innerHTML = "";

        for (var i = 0; i < results.length; i++) {
            var r = results[i];
            var isActive = (currentDisplayMode === "tabbed" && i === 0) ? " active" : "";
            html += '<div class="result-card' + isActive + '" data-index="' + i + '">';
            html += '<div class="result-header">';
            html += '<span class="engine-name">' + escapeHtml(r.engine) + '</span>';
            html += '<span>' + escapeHtml(r.requestId) + '</span>';
            html += '<span>' + escapeHtml(r.timestamp) + '</span>';
            html += '<span class="duration">' + r.duration + 'ms</span>';

            if (r.success && r.output && hasHtmlTags(r.output)) {
                html += '<button class="btn-source-toggle" data-index="' + i + '">Source</button>';
            }
            html += '</div>';

            if (r.success) {
                html += '<div class="result-body" data-index="' + i + '">' + r.output + '</div>';
            } else {
                var errMsg = r.error;
                if (typeof errMsg === "object") errMsg = errMsg.message || JSON.stringify(errMsg);
                html += '<div class="result-body error-view">' + escapeHtml(errMsg) + '</div>';
            }
            html += '</div>';

            // Tab bar entry
            if (results.length > 1) {
                var tabActive = (i === 0) ? " active" : "";
                tabBar.innerHTML += '<button class="' + tabActive + '" data-index="' + i + '">' + escapeHtml(r.engine) + '</button>';
            }
        }

        resultsContainer.innerHTML = html;
        applyDisplayMode();
        bindResultEvents();
    }

    function hasHtmlTags(str) {
        return /<[a-zA-Z][^>]*>/.test(str);
    }

    function bindResultEvents() {
        // Source toggle buttons
        var toggleBtns = resultsContainer.querySelectorAll(".btn-source-toggle");
        for (var i = 0; i < toggleBtns.length; i++) {
            toggleBtns[i].addEventListener("click", function() {
                var idx = this.getAttribute("data-index");
                var body = resultsContainer.querySelector('.result-body[data-index="' + idx + '"]');
                if (body.classList.contains("source-view")) {
                    body.classList.remove("source-view");
                    body.innerHTML = body.getAttribute("data-html");
                    this.textContent = "Source";
                } else {
                    if (!body.getAttribute("data-html")) {
                        body.setAttribute("data-html", body.innerHTML);
                    }
                    body.classList.add("source-view");
                    body.textContent = body.getAttribute("data-html");
                    this.textContent = "Rendered";
                }
            });
        }

        // Store original HTML for source toggle
        var bodies = resultsContainer.querySelectorAll(".result-body:not(.error-view)");
        for (var j = 0; j < bodies.length; j++) {
            bodies[j].setAttribute("data-html", bodies[j].innerHTML);
        }

        // Tab bar buttons
        var tabBtns = tabBar.querySelectorAll("button");
        for (var k = 0; k < tabBtns.length; k++) {
            tabBtns[k].addEventListener("click", function() {
                var idx = this.getAttribute("data-index");
                // Deactivate all tabs and cards
                var allTabs = tabBar.querySelectorAll("button");
                var allCards = resultsContainer.querySelectorAll(".result-card");
                for (var m = 0; m < allTabs.length; m++) allTabs[m].classList.remove("active");
                for (var n = 0; n < allCards.length; n++) allCards[n].classList.remove("active");
                // Activate selected
                this.classList.add("active");
                var card = resultsContainer.querySelector('.result-card[data-index="' + idx + '"]');
                if (card) card.classList.add("active");
            });
        }
    }

    // ===== Display Mode Toggle =====
    var modeButtons = displayModeToggle.querySelectorAll("button");
    for (var m = 0; m < modeButtons.length; m++) {
        modeButtons[m].addEventListener("click", function() {
            for (var i = 0; i < modeButtons.length; i++) modeButtons[i].classList.remove("active");
            this.classList.add("active");
            currentDisplayMode = this.getAttribute("data-mode");
            applyDisplayMode();
        });
    }

    function applyDisplayMode() {
        resultsContainer.className = "results-container";
        tabBar.style.display = "none";
        if (currentDisplayMode === "side-by-side") {
            resultsContainer.classList.add("side-by-side");
        } else if (currentDisplayMode === "tabbed") {
            resultsContainer.classList.add("tabbed");
            tabBar.style.display = "flex";
        }
    }

    // ===== Snippets =====
    function loadSnippetList() {
        ajax("GET", "api2/snippets.cfm", null, function(resp) {
            if (resp.success && resp.snippets) {
                var html = '<option value="">-- none --</option>';
                for (var i = 0; i < resp.snippets.length; i++) {
                    html += '<option value="' + escapeHtml(resp.snippets[i].name) + '">' +
                        escapeHtml(resp.snippets[i].name) + '</option>';
                }
                snippetSelect.innerHTML = html;
            }
        });
    }

    snippetSelect.addEventListener("change", function() {
        var fileName = this.value;
        if (!fileName) return;
        ajax("GET", "api2/snippet-load.cfm?file=" + encodeURIComponent(fileName), null, function(resp) {
            if (resp.success) {
                editor.setValue(resp.content, -1);
                editor.gotoLine(1, 0, false);
            }
        });
    });

    // ===== Clear Session =====
    btnClearSession.addEventListener("click", function() {
        if (!confirm("Archive current session files and start fresh?")) return;
        ajax("GET", "api2/session-clear.cfm", null, function(resp) {
            if (resp.success) {
                resultsContainer.innerHTML = '<div style="padding:16px;color:#4caf50;">Session cleared and archived.</div>';
            }
        });
    });

    // ===== Timeout Input =====
    timeoutInput.addEventListener("change", function() {
        var val = parseInt(this.value, 10) || 0;
        ajax("POST", "api2/config.cfm", encodeParams({ executionTimeout: val }), function() {});
    });

    // ===== Splitter (drag to resize editor/results) =====
    var splitter = document.getElementById("splitter");
    var editorPanel = document.getElementById("editorPanel");
    var isDragging = false;

    splitter.addEventListener("mousedown", function(e) {
        isDragging = true;
        e.preventDefault();
    });
    document.addEventListener("mousemove", function(e) {
        if (!isDragging) return;
        var containerTop = editorPanel.parentElement.getBoundingClientRect().top;
        var topBarHeight = document.querySelector(".top-bar").offsetHeight;
        var newHeight = e.clientY - editorPanel.getBoundingClientRect().top;
        if (newHeight < 100) newHeight = 100;
        editorPanel.style.flex = "none";
        editorPanel.style.height = newHeight + "px";
        editor.resize();
    });
    document.addEventListener("mouseup", function() {
        isDragging = false;
    });

    // ===== Utility =====
    function escapeHtml(str) {
        if (!str) return "";
        var div = document.createElement("div");
        div.appendChild(document.createTextNode(str));
        return div.innerHTML;
    }

    // ===== Initialize =====
    pollServers();
    loadSnippetList();
    setInterval(pollServers, APP_CONFIG.clientPollInterval);

})();
```

- [ ] **Step 2: Verify full UI functionality**

Navigate to the app in a browser. Test:
- Ace Editor loads with ColdFusion mode and monokai theme
- Status bar populates with server dots (all gray/offline initially)
- Clicking status bar opens admin modal with server cards
- Snippet dropdown is populated (if files exist in `snippets/`)
- Timeout input is visible with default value

- [ ] **Step 3: Commit**

```bash
git add www/assets/js/app.js
git commit -m "feat: add client-side JavaScript — editor init, AJAX, polling, admin modal, results"
```

---

## Task 12: End-to-End Integration Test

No new files. This task verifies the entire system works together.

- [ ] **Step 1: Start the host engine**

Start one of the CFML engines to act as the host. Navigate to the app URL.

- [ ] **Step 2: Start a target engine via the UI**

Open the admin modal, click "Start" on another engine. Verify:
- Status changes to "starting" with a seconds counter
- After the engine boots, heartbeat detects it as "online"
- The engine appears in the engine dropdown

- [ ] **Step 3: Execute code on a single engine**

Enter code in the editor:
```cfml
<cfscript>
writeOutput("Hello from CFFiddle! Server: " & server.coldfusion.productname);
</cfscript>
```
Select the online engine, click Run. Verify:
- Result card appears with engine name, UUID, timestamp, duration
- Output shows the rendered text
- A `.cfm` file exists in `www/_payloads/`

- [ ] **Step 4: Execute on all online engines**

Start a second engine. Click "Run All Online". Verify:
- Multiple result cards appear
- Display mode toggle becomes visible
- Switching between stacked/side-by-side/tabbed works

- [ ] **Step 5: Test Source toggle**

Run code that outputs HTML:
```cfml
<cfscript>
writeOutput("<h1>Test</h1><p>Paragraph</p>");
</cfscript>
```
Verify the "Source" button appears and toggles between rendered HTML and source view.

- [ ] **Step 6: Test error handling**

Run code with a syntax error:
```cfml
<cfscript>
writeOutput(;
</cfscript>
```
Verify an error result card appears with a normalized error message.

- [ ] **Step 7: Test session clear**

Click "Clear Session". Verify:
- Files are removed from `_payloads/`
- ZIP file(s) appear in `archive/`
- Results panel shows confirmation message

- [ ] **Step 8: Test snippet loading**

Create a file in `snippets/` (e.g., `hello.cfm`). Refresh the page. Select it from the dropdown. Verify the editor content is replaced.

- [ ] **Step 9: Stop a server via the UI**

In the admin modal, click "Stop" on a running engine. Verify it transitions to "stopping" then "offline".

- [ ] **Step 10: Commit any fixes**

If any adjustments were needed during integration testing, commit them:
```bash
git add -A
git commit -m "fix: integration test fixes"
```

---

## Task 13: Final Cleanup & Sample Snippet

**Files:**
- Create: `snippets/hello.cfm`

- [ ] **Step 1: Create a sample snippet**

```cfm
<cfscript>
// Hello World — basic CFFiddle test
writeOutput("<h2>Hello from CFFiddle!</h2>");
writeOutput("<p>Engine: " & server.coldfusion.productname & " " & server.coldfusion.productversion & "</p>");
writeOutput("<p>Timestamp: " & dateTimeFormat(now(), "yyyy-MM-dd HH:nn:ss") & "</p>");
</cfscript>
```

- [ ] **Step 2: Verify the snippet appears in the dropdown and loads correctly**

- [ ] **Step 3: Commit**

```bash
git add snippets/hello.cfm
git commit -m "feat: add sample hello.cfm snippet"
```
