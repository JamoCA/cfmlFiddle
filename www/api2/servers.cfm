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
