<!---
	snippets.cfm
	Returns a list of available snippet files from the snippets/ directory.
--->
<cfset _startTick = getTickCount()>
<cfset snippetsPath = application.config.snippetsPath>
<cfset response = [:]>

<cfif !directoryExists(snippetsPath)>
	<cfset response["success"] = application.jTrue>
	<cfset response["snippets"] = []>
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfdirectory
	action="list"
	directory="#snippetsPath#"
	filter="*.cfm"
	name="fileQry"
	type="file"
	sort="name asc">

<cfset snippets = []>
<cfloop query="fileQry">
	<cfset entry = [
		"name": fileQry.name,
		"size": javacast("int", fileQry.size)
	]>
	<cfset arrayAppend(snippets, entry)>
</cfloop>

<cfset response["success"] = application.jTrue>
<cfset response["snippets"] = snippets>
<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
