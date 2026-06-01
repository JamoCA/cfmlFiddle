<!---
	payload-load.cfm
	Returns the content of a payload file for reloading into the editor.
	Expects: url.file (filename only, no path traversal allowed)
	Strips any prepended <cfsetting requesttimeout="..."> line added by execute.cfm.
--->
<cfset _startTick = getTickCount()>
<cfset response = [:]>

<cfif !structKeyExists(url, "file") || !len(trim(url.file))>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "No file specified.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<!--- Security: strip any path components - only allow bare filenames --->
<cfset fileName = listLast(replace(url.file, "\", "/", "all"), "/")>

<!--- Reject if filename contains suspicious characters --->
<cfif reFind("[^a-zA-Z0-9._\-]", fileName)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "Invalid filename.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfset payloadsPath = application.config.payloadsPath>
<cfset filePath = payloadsPath & "/" & fileName>

<cfif !fileExists(filePath)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "File not found: " & encodeForHTML(fileName)>
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfset content = fileRead(filePath, "utf-8")>

<!--- Strip the cfsetting requesttimeout line that execute.cfm prepends --->
<cfif left(content, 11) eq "<cfsetting " && find(chr(10), content)>
	<cfset firstLine = left(content, find(chr(10), content))>
	<cfif reFindNoCase("^<cfsetting\s+requesttimeout=""[0-9]+""\s*/?>", trim(firstLine))>
		<cfset content = mid(content, find(chr(10), content) + 1, len(content))>
	</cfif>
</cfif>

<cfset response["success"] = application.jTrue>
<cfset response["file"] = fileName>
<cfset response["content"] = content>
<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
