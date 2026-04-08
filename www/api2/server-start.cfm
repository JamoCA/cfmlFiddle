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
