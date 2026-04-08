<!---
    snippets.cfm
    Returns a list of available snippet files from the snippets/ directory.
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var snippetsPath = expandPath(application.config.snippetsDir)>
<cfset var response = [:]>

<cfif not directoryExists(snippetsPath)>
    <cfset response["success"] = true>
    <cfset response["snippets"] = []>
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfdirectory
    action="list"
    directory="#snippetsPath#"
    name="local.files"
    type="file"
    sort="name asc">

<!--- Filter to text-based files, exclude Application.cfc --->
<cfset var snippets = []>
<cfset var allowedExtensions = "cfm,cfml,cfc,json,md,txt,html,htm,xml,sql,css,js">

<cfloop query="local.files">
    <cfset var ext = listLast(local.files.name, ".")>
    <cfif listFindNoCase(allowedExtensions, ext) and local.files.name neq "Application.cfc">
        <cfset var entry = [:]>
        <cfset entry["name"] = local.files.name>
        <cfset entry["size"] = local.files.size>
        <cfset arrayAppend(snippets, entry)>
    </cfif>
</cfloop>

<cfset response["success"] = true>
<cfset response["snippets"] = snippets>
<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
