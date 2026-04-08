<!---
    session-clear.cfm
    Archives .cfm files from _payloads/ and clears the directory.
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<cftry>
    <cfinclude template="_archive-helper.cfm">

    <cfset response["success"] = true>
    <cfset response["message"] = "Session cleared and files archived.">
<cfcatch type="any">
    <cfset response["success"] = false>
    <cfset response["error"] = cfcatch.message>
</cfcatch>
</cftry>

<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
