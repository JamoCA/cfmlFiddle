<!---
    config.cfm
    GET: Returns current runtime config.
    POST: Updates mutable config values (executionTimeout).
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<!--- Handle POST: update mutable config values --->
<cfif CGI.REQUEST_METHOD eq "POST">
    <cfif structKeyExists(form, "executionTimeout") and isNumeric(form.executionTimeout)>
        <cfset application.config.executionTimeout = int(form.executionTimeout)>
    </cfif>
    <cfset response["success"] = true>
    <cfset response["message"] = "Configuration updated.">
<cfelse>
    <cfset response["success"] = true>
</cfif>

<!--- Always return current config --->
<cfset response["config"] = [:]>
<cfset response["config"]["executionTimeout"] = application.config.executionTimeout>
<cfset response["config"]["clientPollInterval"] = application.config.clientPollInterval>
<cfset response["config"]["startupTimeout"] = application.config.startupTimeout>
<cfset response["config"]["editorTheme"] = application.config.editorTheme>

<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
