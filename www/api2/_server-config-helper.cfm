<!---
    _server-config-helper.cfm
    Included by Application.cfc onApplicationStart.
    Reads template server.json files, clones them with a unique name prefix,
    and writes generated configs to runtime/servers/.
--->
<cfset var templateDir = expandPath(application.config.templateServersDir)>
<cfset var runtimeDir = expandPath(application.config.runtimeServersDir)>
<cfset var jsonUtil = application.jsonUtil>

<!--- Scan for server.*.json files in the template directory --->
<cfdirectory
    action="list"
    directory="#templateDir#"
    filter="server.*.json"
    name="local.templateFiles"
    type="file">

<!--- Build the server registry in application scope --->
<cfset application.serverRegistry = [:]>

<cfloop query="local.templateFiles">
    <cfset var templatePath = templateDir & "/" & local.templateFiles.name>
    <cfset var configJSON = fileRead(templatePath, "utf-8")>
    <cfset var config = jsonUtil.deserializeJSON(configJSON)>

    <!--- Extract the original server name --->
    <cfset var originalName = config["name"]>
    <cfset var runtimeName = application.config.serverNamePrefix & originalName>

    <!--- Clone: update the name to avoid collisions --->
    <cfset config["name"] = runtimeName>

    <!--- Write the runtime config --->
    <cfset var runtimePath = runtimeDir & "/server." & originalName & ".json">
    <cfset var outputJSON = jsonUtil.serializeJSON(config)>
    <cfset fileWrite(runtimePath, outputJSON, "utf-8")>

    <!--- Register the server in application scope --->
    <cfset application.serverRegistry["#originalName#"] = [:]>
    <cfset application.serverRegistry[originalName]["name"] = originalName>
    <cfset application.serverRegistry[originalName]["runtimeName"] = runtimeName>
    <cfset application.serverRegistry[originalName]["cfengine"] = config["app"]["cfengine"]>
    <cfset application.serverRegistry[originalName]["host"] = config["web"]["hostAlias"]>
    <cfset application.serverRegistry[originalName]["port"] = config["web"]["HTTP"]["port"]>
    <cfset application.serverRegistry[originalName]["runtimeConfigPath"] = runtimePath>
    <cfset application.serverRegistry[originalName]["templateConfigPath"] = templatePath>

    <!--- Initialize status entry --->
    <cfset application.serverStatuses["#originalName#"] = [:]>
    <cfset application.serverStatuses[originalName]["name"] = originalName>
    <cfset application.serverStatuses[originalName]["cfengine"] = config["app"]["cfengine"]>
    <cfset application.serverStatuses[originalName]["host"] = config["web"]["hostAlias"]>
    <cfset application.serverStatuses[originalName]["port"] = config["web"]["HTTP"]["port"]>
    <cfset application.serverStatuses[originalName]["status"] = "offline">
    <cfset application.serverStatuses[originalName]["lastChecked"] = "">
</cfloop>
