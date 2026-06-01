<!---
	server-start.cfm
	Starts a CommandBox server using its template config.
	Expects: url.server (server key name, e.g., "cf2025")
	Checks for stale registrations before starting.
	Returns after issuing the start command (fire-and-forget via cmd /c start).
--->

<cfset _startTick = getTickCount()>
<cfset response = [:]>

<cfif !structKeyExists(url, "server") || !structKeyExists(application.serverRegistry, url.server)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "Invalid or missing server parameter.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfset serverKey = url.server>
<cfset serverInfo = application.serverRegistry[serverKey]>
<cfset serverName = serverInfo["name"]>
<cfset configPath = serverInfo["configPath"]>
<cfset boxExe = application.config.boxExe>
<cfset expectedWebroot = createObject("java","java.io.File").init(application.config.payloadsPath).getParentFile().getCanonicalPath()>

<!--- Update status to "starting" with lock to prevent heartbeat from flipping back --->
<cfset application.serverStatuses[serverKey]["status"] = "starting">
<cfset application.serverStatuses[serverKey]["statusLockedUntil"] = dateAdd("s", application.config.startupTimeout, now())>
<cfset application.serverStatuses[serverKey]["lastChecked"] = dateTimeFormat(now(), application.timestampMask)>

<!--- Check if this server name is already registered in CommandBox --->
<cftry>
	<cfexecute name="#boxExe#"
		arguments="server list name=#serverName# --json"
		timeout="30" variable="listOutput" />

	<cfset listOutput = trim(listOutput)>
	<cfif len(listOutput)>
		<cfset parsed = deserializeJSON(listOutput)>
		<!--- Normalize: server list --json may return an array or a struct keyed by name --->
		<cfset candidates = []>
		<cfif isArray(parsed)>
			<cfset candidates = parsed>
		<cfelseif isStruct(parsed)>
			<cfloop collection="#parsed#" item="sKey">
				<cfif isStruct(parsed[sKey])>
					<cfset arrayAppend(candidates, parsed[sKey])>
				</cfif>
			</cfloop>
		</cfif>

		<!--- Find our server by .name or .processName --->
		<cfset registered = "">
		<cfloop array="#candidates#" index="candidate">
			<cfif structKeyExists(candidate, "name") && compareNoCase(candidate["name"], serverName) eq 0>
				<cfset registered = candidate>
				<cfbreak>
			</cfif>
			<cfif structKeyExists(candidate, "processName")>
				<cfset pName = candidate["processName"]>
				<cfset bracketPos = find("[", pName)>
				<cfif bracketPos gt 0><cfset pName = trim(left(pName, bracketPos - 1))></cfif>
				<cfif compareNoCase(pName, serverName) eq 0>
					<cfset registered = candidate>
					<cfbreak>
				</cfif>
			</cfif>
		</cfloop>

		<cfif isStruct(registered)>
			<cfset regWebroot = structKeyExists(registered, "webroot") ? registered["webroot"] : "">
			<cfset regWebroot = trim(regWebroot)>
			<!--- Strip trailing slashes for comparison --->
			<cfif len(regWebroot) && listFind("/,\", right(regWebroot, 1))>
				<cfset regWebroot = left(regWebroot, len(regWebroot) - 1)>
			</cfif>

			<!--- If registered to a different directory, forget it --->
			<cfif len(regWebroot) && compareNoCase(regWebroot, expectedWebroot) neq 0>
				<cfexecute name="#boxExe#"
					arguments="server forget #serverName# --force"
					timeout="30" />
			</cfif>
		</cfif>
	</cfif>
<cfcatch>
	<!--- If check fails, proceed with start anyway --->
</cfcatch>
</cftry>

<!--- Fire-and-forget: cmd /c start detaches the process. Minimized unless showConsole requested. --->
<cfset startFlag = structKeyExists(url, "showConsole") ? "" : "/min">
<cfexecute
	name="cmd"
	arguments="/c start #startFlag# """" ""#boxExe#"" server start serverConfigFile=""#configPath#"""
	timeout="30">
</cfexecute>

<cfset response["success"] = application.jTrue>
<cfset response["message"] = "Server '#serverKey#' start command issued.">
<cfset response["server"] = serverKey>
<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>

<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
