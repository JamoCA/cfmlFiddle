<!---
    snippet-load.cfm
    Returns the content of a selected snippet file.
    Expects: url.file (filename only, no path traversal allowed)
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<cfif not structKeyExists(url, "file") or not len(trim(url.file))>
    <cfset response["success"] = false>
    <cfset response["error"] = "No file specified.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<!--- Security: strip any path components — only allow bare filenames --->
<cfset var fileName = listLast(replace(url.file, "\", "/", "all"), "/")>

<!--- Reject if filename contains suspicious characters --->
<cfif reFind("[^a-zA-Z0-9._\-]", fileName)>
    <cfset response["success"] = false>
    <cfset response["error"] = "Invalid filename.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var snippetsPath = expandPath(application.config.snippetsDir)>
<cfset var filePath = snippetsPath & "/" & fileName>

<cfif not fileExists(filePath)>
    <cfset response["success"] = false>
    <cfset response["error"] = "File not found: " & encodeForHTML(fileName)>
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var content = fileRead(filePath, "utf-8")>

<cfset response["success"] = true>
<cfset response["file"] = fileName>
<cfset response["content"] = content>
<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
