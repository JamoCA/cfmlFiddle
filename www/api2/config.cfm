<!---
    config.cfm
    GET: Returns current runtime config.
    POST: Updates mutable config values (executionTimeout).
--->
<cfset _startTick = getTickCount()>
<cfset response = [:]>

<!--- Handle POST: update mutable config values --->
<cfif CGI.REQUEST_METHOD eq "POST">
    <cfif structKeyExists(form, "executionTimeout") && isNumeric(form.executionTimeout)>
        <cfset application.config.executionTimeout = int(form.executionTimeout)>
    </cfif>
    <cfset response["success"] = application.jTrue>
    <cfset response["message"] = "Configuration updated.">
<cfelse>
    <cfset response["success"] = application.jTrue>
</cfif>

<!--- Always return current config --->
<cfset response["config"] = [
	"executionTimeout": javacast("int", application.config.executionTimeout),
	"clientPollInterval": javacast("int", application.config.clientPollInterval),
	"startupTimeout": javacast("int", application.config.startupTimeout),
	"editorTheme": application.config.editorTheme
]>

<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
