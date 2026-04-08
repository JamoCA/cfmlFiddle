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
