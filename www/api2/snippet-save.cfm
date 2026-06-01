<!---
	snippet-save.cfm
	Saves the current editor content as a snippet file.
	Expects: form.filename (bare name, no extension), form.code
--->
<cfset _startTick = getTickCount()>
<cfset response = [:]>

<cfif !structKeyExists(form, "filename") || !len(trim(form.filename))>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "No filename specified.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfif !structKeyExists(form, "code") || !len(form.code)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "No code provided.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<!--- Validate filename: alphanumeric, hyphens, underscores only. No spaces, periods, or path chars. --->
<cfset fileName = trim(form.filename)>
<cfif reFind("[^a-zA-Z0-9_\-]", fileName)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "Invalid filename. Use only letters, numbers, hyphens, and underscores.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfset fileName = fileName & ".cfm">
<cfset snippetsPath = application.config.snippetsPath>
<cfset filePath = snippetsPath & "/" & fileName>

<!--- Check if file already exists --->
<cfif fileExists(filePath)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "A snippet named '" & fileName & "' already exists.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfset fileWrite(filePath, form.code, "utf-8")>

<cfset response["success"] = application.jTrue>
<cfset response["message"] = "Snippet saved as " & fileName>
<cfset response["file"] = fileName>
<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
