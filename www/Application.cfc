<cfcomponent output="false">

	<!--- Application identity --->
	<cfset this.version = "1.0.0">
	<cfset this.name = "CFMLFiddle_" & hash(getCurrentTemplatePath())>
	<cfset this.sessionManagement = false>

	<!--- Map to JSONUtil (outside webroot) --->
	<cfset this.mappings["/jsonutil"] = createObject("java","java.io.File").init(
		getDirectoryFromPath(getCurrentTemplatePath()), "../JSONUtil"
	).getCanonicalPath()>



	<!--- ============================================================
		CONFIGURATION - loaded from ../config.json
		Edit config.json (above webroot) to customize the app.
		Use Reinit in the UI to reload after changes.
		============================================================ --->
	<cfset local.configPath = createObject("java","java.io.File").init(
		getDirectoryFromPath(getCurrentTemplatePath()), "../config.json"
	).getCanonicalPath()>
	<cfif fileExists(local.configPath)>
		<cfset local.cfg = deserializeJSON(fileRead(local.configPath, "utf-8"))>
	<cfelse>
		<cfset local.cfg = {}>
	</cfif>

	<cfset this.allowedIPs = local.cfg.allowedIPs ?: "127.0.0.1,::1,0:0:0:0:0:0:0:1">
	<cfset this.executionTimeout = local.cfg.executionTimeout ?: 0>
	<cfset this.serverPollInterval = local.cfg.serverPollInterval ?: 30>
	<cfset this.clientPollInterval = local.cfg.clientPollInterval ?: 10>
	<cfset this.startupTimeout = local.cfg.startupTimeout ?: 60>
	<cfset this.editorTheme = local.cfg.editorTheme ?: "monokai">
	<cfset this.serverNamePrefix = local.cfg.serverNamePrefix ?: "cfmlfiddle-">
	<cfset this.boxExe = local.cfg.boxExe ?: "box">
	<cfset this.payloadsDir = local.cfg.payloadsDir ?: "_payloads">
	<cfset this.archiveDir = local.cfg.archiveDir ?: "../archive">
	<cfset this.snippetsDir = local.cfg.snippetsDir ?: "../snippets">
	<cfset this.templateServersDir = local.cfg.templateServersDir ?: "../current-servers">
	<cfset this.customTagsDir = local.cfg.customTagsDir ?: "../CustomTags">
	<cfset this.javaLibsDir = local.cfg.javaLibsDir ?: "../JavaLibs">
	<cfset this.useLocalAssets = local.cfg.useLocalAssets ?: true>
	<cfset this.useSSE = local.cfg.useSSE ?: false>

	<!--- Resolve custom tags and java libs to absolute paths --->
	<cfset local.jFile = createObject("java","java.io.File")>
	<cfset local.cfcDir = getDirectoryFromPath(getCurrentTemplatePath())>
	<cfset local.customTagsPath = local.jFile.init(local.cfcDir, this.customTagsDir).getCanonicalPath()>
	<cfset local.javaLibsPath = local.jFile.init(local.cfcDir, this.javaLibsDir).getCanonicalPath()>

	<!--- Register custom tags at the application level (works across all engines) --->
	<cfset this.customTagPaths = local.customTagsPath>

	<!--- Register Java libraries --->
	<cfset this.javaSettings = {
		"loadPaths": [local.javaLibsPath],
		"reloadOnChange": false
	}>

	<!--- Shared secret token for _payloads/ access via cfhttp.
		Must be stable across all engines sharing this webroot,
		so derive from the application name prefix (not engine-specific paths). --->
	<cfset this.payloadToken = hash("CFMLFiddle_payloadAccess_" & this.serverNamePrefix, "SHA-256")>

	<cffunction name="onApplicationStart" returntype="boolean" output="false">
		<!--- Initialize JSONUtil --->
		<cfset application.jsonUtil = new jsonutil.JSONUtil()>

		<!--- JSON-safe booleans --->
		<cfset application.jTrue = javacast("boolean", true)>
		<cfset application.jFalse = javacast("boolean", false)>

		<!--- Detect timestamp mask: CFML engines use nn=minutes/lll=ms,
			BoxLang native mode uses Java's mm=minutes/A=ms-of-day.
			Test by formatting a known date - if nn produces "30" it's CFML mode. --->
		<cfset var testMinutes = dateTimeFormat(createDateTime(2000, 1, 1, 0, 30, 0), "nn")>
		<cfset application.timestampMask = (testMinutes eq "30")
			? "yyyy-MM-dd'T'HH:nn:ss.lllZ"
			: "yyyy-MM-dd'T'HH:mm:ss.AZ">

		<!--- Build absolute paths from the CFC's own location (immune to
			request-template context shifts during reinit).
			getCurrentTemplatePath() always returns this CFC's path. --->
		<cfset var webroot = getDirectoryFromPath(getCurrentTemplatePath())>
		<cfset var jFile = createObject("java", "java.io.File")>

		<!--- Store config in application scope for api2 endpoints to read --->
		<cfset application.version = this.version>
		<cfif structKeyExists(server, "coldfusion")>
			<cfset application.userAgent = "CFMLFiddle/#this.version# (#server.coldfusion.productname# #server.coldfusion.productversion#; CommandBox)">
		<cfelseif structKeyExists(server, "boxlang")>
			<cfset application.userAgent = "CFMLFiddle/#this.version# (BoxLang #server.boxlang.version#; CommandBox)">
		<cfelse>
			<cfset application.userAgent = "CFMLFiddle/#this.version# (CommandBox)">
		</cfif>

		<cfset application.config = [
			"version": this.version,
			"executionTimeout": this.executionTimeout,
			"serverPollInterval": this.serverPollInterval,
			"clientPollInterval": this.clientPollInterval,
			"startupTimeout": this.startupTimeout,
			"editorTheme": this.editorTheme,
			"serverNamePrefix": this.serverNamePrefix,
			"boxExe": this.boxExe,
			"payloadsDir": this.payloadsDir,
			"payloadsPath": jFile.init(webroot, this.payloadsDir).getCanonicalPath(),
			"archivePath": jFile.init(webroot, this.archiveDir).getCanonicalPath(),
			"snippetsPath": jFile.init(webroot, this.snippetsDir).getCanonicalPath(),
			"templateServersPath": jFile.init(webroot, this.templateServersDir).getCanonicalPath(),
			"customTagsPath": jFile.init(webroot, this.customTagsDir).getCanonicalPath(),
			"javaLibsPath": jFile.init(webroot, this.javaLibsDir).getCanonicalPath(),
			"payloadToken": this.payloadToken,
			"useLocalAssets": this.useLocalAssets,
			"useSSE": this.useSSE
		]>

		<!--- Initialize server status cache --->
		<cfset application.serverStatuses = [:]>

		<!--- Reset host server detection (re-detected on first request) --->
		<cfset application.hostServerKey = "">

		<!--- Ensure directories exist --->
		<cfif !directoryExists(application.config.payloadsPath)>
			<cfset directoryCreate(application.config.payloadsPath)>
		</cfif>
		<cfif !directoryExists(application.config.archivePath)>
			<cfset directoryCreate(application.config.archivePath)>
		</cfif>

		<!--- Generate runtime server configs from templates --->
		<cfinclude template="api2/_server-config-helper.cfm">

		<!--- Run initial heartbeat to detect already-running servers --->
		<cfinclude template="api2/_heartbeat-helper.cfm">
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

		<cfif !ipAllowed>
			<cfcontent type="text/html" reset="true">
			<cfoutput>
				<h2>Access Denied</h2>
				<p>Your IP address is <strong>#encodeForHTML(remoteIP)#</strong>.</p>
				<p>Contact an administrator to be added to the allowlist.</p>
			</cfoutput>
			<cfreturn false>
		</cfif>

		<!--- ===== SECURITY HEADERS ===== --->
		<cfheader name="X-Content-Type-Options" value="nosniff">
		<cfheader name="X-Frame-Options" value="SAMEORIGIN">
		<cfheader name="Referrer-Policy" value="strict-origin-when-cross-origin">

		<!--- ===== APPLICATION REINIT ===== --->
		<cfif structKeyExists(url, "reinit")>
			<cfset onApplicationStart()>

			<!--- Propagate reinit to all other online servers sharing this webroot --->
			<cfset var reqPort = val(CGI.SERVER_PORT)>
			<cfloop collection="#application.serverStatuses#" item="local.rKey">
				<cfif application.serverStatuses[local.rKey]["status"] eq "online"
					&& application.serverStatuses[local.rKey]["port"] neq reqPort>
					<cftry>
						<cfhttp url="http://#application.serverStatuses[local.rKey]['host']#:#application.serverStatuses[local.rKey]['port']#/?reinit"
							method="GET" timeout="5" result="local.reinitResult" userAgent="#application.userAgent#">
							<cfhttpparam type="header" name="X-Payload-Token" value="#application.config.payloadToken#">
						</cfhttp>
					<cfcatch>
						<!--- Server may be slow to respond; continue with others --->
					</cfcatch>
					</cftry>
				</cfif>
			</cfloop>
		</cfif>

		<!--- ===== DETECT HOST SERVER (once, on first request) ===== --->
		<cfif !structKeyExists(application, "hostServerKey") || !len(application.hostServerKey)>
			<cfset var reqPort = val(CGI.SERVER_PORT)>
			<cfloop collection="#application.serverRegistry#" item="local.sKey">
				<cfif application.serverRegistry[local.sKey]["port"] eq reqPort>
					<cfset application.hostServerKey = local.sKey>
					<cfbreak>
				</cfif>
			</cfloop>
			<cfif !structKeyExists(application, "hostServerKey")>
				<cfset application.hostServerKey = "">
			</cfif>
		</cfif>

		<!--- ===== BLOCK api2 HELPER FILES (underscore-prefixed, cfinclude only) ===== --->
		<cfif findNoCase("/api2/", arguments.targetPage) eq 1>
			<cfif left(listLast(arguments.targetPage, "/\"), 1) eq "_">
				<cfcontent type="text/html" reset="true">
				<cfoutput>
					<h2>Access Denied</h2>
					<p>Direct access to this file is not permitted.</p>
				</cfoutput>
				<cfreturn false>
			</cfif>
			<!--- Set JSON content type for api2 responses (except SSE endpoint) --->
			<cfif !findNoCase("server-events.cfm", arguments.targetPage)>
				<cfcontent type="application/json" reset="true">
			</cfif>
		</cfif>

		<!--- ===== BLOCK DIRECT ACCESS TO _payloads/ ===== --->
		<cfif findNoCase("_payloads", arguments.targetPage)>
			<!--- Allow if the shared secret token is present via header (server-to-server cfhttp).
					Check multiple CGI key formats for cross-engine compatibility. --->
			<cfset var tokenMatch = false>
			<cfif structKeyExists(CGI, "HTTP_X_PAYLOAD_TOKEN") && CGI.HTTP_X_PAYLOAD_TOKEN eq this.payloadToken>
				<cfset tokenMatch = true>
			</cfif>
			<!--- Some engines use getHTTPRequestData for custom headers --->
			<cfif !tokenMatch>
				<cftry>
					<cfset var reqHeaders = getHTTPRequestData().headers>
					<cfif structKeyExists(reqHeaders, "X-Payload-Token") && reqHeaders["X-Payload-Token"] eq this.payloadToken>
						<cfset tokenMatch = true>
					</cfif>
				<cfcatch></cfcatch>
				</cftry>
			</cfif>
			<!--- Allow signed URL token for iframe interactive mode --->
			<cfif !tokenMatch && structKeyExists(url, "_tk")>
				<cfset var fileName = listLast(arguments.targetPage, "/\")>
				<cfif url._tk eq hash(fileName & this.payloadToken, "SHA-256")>
					<cfset tokenMatch = true>
				</cfif>
			</cfif>
			<cfif tokenMatch>
				<!--- Allowed: this is a server-to-server execution request --->
			<cfelse>
				<cfcontent type="text/html" reset="true">
				<cfoutput>
					<h2>Access Denied</h2>
					<p>Direct access to this directory is not permitted.</p>
				</cfoutput>
				<cfreturn false>
			</cfif>
		</cfif>

		<!--- ===== HEARTBEAT: check if server-side poll is due (runs in background thread) ===== --->
		<cfif structKeyExists(application, "lastHeartbeat")
			&& dateDiff("s", application.lastHeartbeat, now()) gte application.config.serverPollInterval>
			<cfset application.lastHeartbeat = now()>
			<cfthread name="heartbeat_#createUUID()#" action="run">
				<cfinclude template="api2/_heartbeat-helper.cfm">
			</cfthread>
		</cfif>

		<cfreturn true>
	</cffunction>

</cfcomponent>
