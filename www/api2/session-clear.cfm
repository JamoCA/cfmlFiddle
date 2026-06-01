<!---
	session-clear.cfm
	Archives .cfm files from _payloads/ and clears the directory.
--->
<cfset _startTick = getTickCount()>
<cfset response = [:]>

<cftry>
	<cfinclude template="_archive-helper.cfm">

	<cfset response["success"] = application.jTrue>
	<cfset response["message"] = "Session cleared and files archived.">
<cfcatch type="any">
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = cfcatch.message>
</cfcatch>
</cftry>

<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
