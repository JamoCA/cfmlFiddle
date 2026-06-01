<!---
	server-stop.cfm
	Stops a CommandBox server.
	Expects: url.server (server key name, e.g., "cf2025")
	Runs synchronously — box server stop returns after the server is stopped.
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
<cfset boxExe = application.config.boxExe>

<!--- Update status to "stopping" with 60s lock to prevent heartbeat from flipping back --->
<cfset application.serverStatuses[serverKey]["status"] = "stopping">
<cfset application.serverStatuses[serverKey]["statusLockedUntil"] = dateAdd("s", 60, now())>
<cfset application.serverStatuses[serverKey]["lastChecked"] = dateTimeFormat(now(), application.timestampMask)>

<!--- Run box server stop synchronously - it returns after the server is stopped --->
<cftry>
	<cfexecute
		name="#boxExe#"
		arguments="server stop #serverInfo['name']#"
		timeout="60"
		variable="stopOutput">
	</cfexecute>

	<cfset application.serverStatuses[serverKey]["status"] = "offline">
	<cfset structDelete(application.serverStatuses[serverKey], "statusLockedUntil")>

	<cfset response["success"] = application.jTrue>
	<cfset response["message"] = "Server '#serverKey#' stopped.">
<cfcatch>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "Stop command failed: " & cfcatch.message>
</cfcatch>
</cftry>

<cfset response["server"] = serverKey>
<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
