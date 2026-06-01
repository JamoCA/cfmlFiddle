<!---
	servers.cfm
	Returns the cached server statuses as JSON.
	The browser polls this endpoint on clientPollInterval.
--->
<cfset _startTick = getTickCount()>

<cfset response = [
	"success": application.jTrue,
	"timestamp": dateTimeFormat(now(), application.timestampMask),
	"pollInterval": javacast("int", application.config.clientPollInterval),
	"hostServer": application.hostServerKey,
	"heartbeatDuration": javacast("int", structKeyExists(application, "heartbeatDuration") ? application.heartbeatDuration : 0),
	"payloadCount": javacast("int", arrayLen(directoryList(application.config.payloadsPath, false, "name", "*.cfm"))),
	"servers": application.serverStatuses,
	"duration": javacast("int", getTickCount() - _startTick)
]>

<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
