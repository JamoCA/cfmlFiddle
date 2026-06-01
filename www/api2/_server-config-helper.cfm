<!---
	_server-config-helper.cfm
	Included by Application.cfc onApplicationStart.
	Reads template server.json files from current-servers/
	and populates the server registry. Configs are used directly
	from current-servers/ so relative paths (webroot, etc.) resolve correctly.
--->
<cfset templateDir = application.config.templateServersPath>

<!--- Scan for server.*.json files in the template directory --->
<cfdirectory
	action="list"
	directory="#templateDir#"
	filter="server.*.json"
	name="templatesQry"
	type="file">

<!--- Build the server registry in application scope --->
<cfset application.serverRegistry = [:]>

<cfloop query="templatesQry">
	<cfset templatePath = templateDir & "/" & templatesQry.name>
	<cfset configJSON = fileRead(templatePath, "utf-8")>
	<cfset config = application.jsonUtil.deserializeJSON(JSONvar=configJSON, strictMapping=true)>

	<!--- Extract the server name (already prefixed with cfmlfiddle- in template) --->
	<cfset serverName = config["name"]>

	<!--- Derive the engine key by stripping the cfmlfiddle- prefix --->
	<cfset engineKey = serverName>
	<cfif left(serverName, len(application.config.serverNamePrefix)) eq application.config.serverNamePrefix>
		<cfset engineKey = mid(serverName, len(application.config.serverNamePrefix) + 1, len(serverName) - len(application.config.serverNamePrefix))>
	</cfif>

	<!--- Register the server in application scope (keyed by engine key, e.g. "cf2016") --->
	<cfset application.serverRegistry["#engineKey#"] = [
		"name": serverName,
		"engineKey": engineKey,
		"cfengine": config["app"]["cfengine"],
		"host": config["web"]["hostAlias"],
		"port": javacast("int", config["web"]["HTTP"]["port"]),
		"configPath": templatePath
	]>

	<!--- Initialize status entry --->
	<cfset application.serverStatuses["#engineKey#"] = [
		"name": serverName,
		"cfengine": config["app"]["cfengine"],
		"host": config["web"]["hostAlias"],
		"port": javacast("int", config["web"]["HTTP"]["port"]),
		"status": "offline",
		"lastChecked": "",
		"productName": "",
		"productVersion": "",
		"onlineSince": ""
	]>
</cfloop>
