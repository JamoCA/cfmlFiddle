<!---
	gist-import.cfm
	Imports a single file from a GitHub Gist URL.
	Expects: form.url (must be a gist.github.com URL)
	Returns the content of the first file in the gist.
--->
<cfset _startTick = getTickCount()>
<cfset response = [:]>

<cfif !structKeyExists(form, "url") || !len(trim(form.url))>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "No URL provided.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfset gistURL = trim(form.url)>

<!--- Validate that the URL is a gist.github.com URL --->
<cfif !reFindNoCase("^https?://gist\.github\.com/", gistURL)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "URL must be from gist.github.com">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<!--- Extract the gist ID from the URL (last path segment, ignoring any hash) --->
<cfset gistPath = listLast(replace(listFirst(gistURL, "##"), "https://gist.github.com/", ""), "/")>
<cfif !len(gistPath) || reFind("[^a-fA-F0-9]", gistPath)>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "Could not extract a valid gist ID from the URL.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<!--- Fetch the gist via GitHub API --->
<cftry>
	<cfhttp url="https://api.github.com/gists/#gistPath#" method="GET" timeout="10" result="gistResult" userAgent="#application.userAgent#">
		<cfhttpparam type="header" name="Accept" value="application/vnd.github+json">
	</cfhttp>

	<cfif val(gistResult.statusCode) neq 200>
		<cfset response["success"] = application.jFalse>
		<cfset response["error"] = "GitHub API returned HTTP " & gistResult.statusCode>
		<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
		<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
		<cfabort>
	</cfif>

	<cfset gistData = deserializeJSON(gistResult.fileContent)>

	<!--- Get the first file from the gist --->
	<cfset gistFiles = gistData.files>
	<cfset fileNames = structKeyArray(gistFiles)>
	<cfif !arrayLen(fileNames)>
		<cfset response["success"] = application.jFalse>
		<cfset response["error"] = "Gist contains no files.">
		<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
		<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
		<cfabort>
	</cfif>

	<cfset firstFile = gistFiles[fileNames[1]]>

	<cfset response["success"] = application.jTrue>
	<cfset response["filename"] = firstFile.filename>
	<cfset response["content"] = firstFile.content>
	<cfset response["description"] = gistData.description ?: "">

<cfcatch type="any">
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "Failed to fetch gist: " & cfcatch.message>
</cfcatch>
</cftry>

<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
