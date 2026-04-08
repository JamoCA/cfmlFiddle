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
                <!--- Starts-with match (append dot if missing to prevent 192.168.1 matching 192.168.10.x) --->
                <cfset var prefix = local.allowedIP>
                <cfif right(prefix, 1) neq ".">
                    <cfset prefix = prefix & ".">
                </cfif>
                <cfif left(remoteIP, len(prefix)) eq prefix>
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
