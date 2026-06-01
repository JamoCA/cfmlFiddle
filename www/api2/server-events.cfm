<!---
	server-events.cfm
	Server-Sent Events (SSE) endpoint.
	Streams server status updates to the client in real time.
	Falls back to polling if SSE is disabled in config.

	The connection stays open and pushes updates at the configured
	serverPollInterval. Each event contains the same JSON payload
	as servers.cfm.
--->
<cfsetting requesttimeout="65000">

<!--- SSE headers --->
<cfcontent type="text/event-stream" reset="true">
<cfheader name="Cache-Control" value="no-cache">
<cfheader name="Connection" value="keep-alive">
<cfheader name="X-Accel-Buffering" value="no">

<cfset jThread = createObject("java", "java.lang.Thread")>
<cfset pollInterval = javacast("int", application.config.clientPollInterval)>
<cfif pollInterval lt 5><cfset pollInterval = 5></cfif>
<cfset sleepMs = javacast("long", pollInterval * 1000)>

<!--- Send events in a loop until the client disconnects --->
<cfset keepRunning = true>
<cfloop condition="keepRunning">
	<cftry>
		<!--- Run heartbeat to refresh statuses --->
		<cfinclude template="_heartbeat-helper.cfm">

		<!--- Build the event payload (same shape as servers.cfm) --->
		<cfset eventData = [
			"success": application.jTrue,
			"timestamp": dateTimeFormat(now(), application.timestampMask),
			"pollInterval": javacast("int", application.config.clientPollInterval),
			"hostServer": application.hostServerKey,
			"heartbeatDuration": javacast("int", structKeyExists(application, "heartbeatDuration") ? application.heartbeatDuration : 0),
			"payloadCount": javacast("int", arrayLen(directoryList(application.config.payloadsPath, false, "name", "*.cfm"))),
			"servers": application.serverStatuses
		]>

		<cfset eventJSON = application.jsonUtil.serializeJSON(var=eventData, strictMapping=true)>

		<!--- Write SSE event --->
		<cfoutput>data: #eventJSON##chr(10)##chr(10)#</cfoutput>
		<cfflush>

		<!--- Sleep until next poll --->
		<cfset jThread.sleep(sleepMs)>

	<cfcatch type="any">
		<!--- Client disconnected or error - exit gracefully --->
		<cfset keepRunning = false>
	</cfcatch>
	</cftry>
</cfloop>
