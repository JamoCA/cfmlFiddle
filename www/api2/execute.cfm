<!---
    execute.cfm
    Receives CFML payload and target engine(s), executes via cfhttp.
    Expects:
      form.code    — the CFML source code
      form.engine  — target engine key (e.g., "cf2025") or "all" for all online
    Returns JSON with execution results.
--->
<cfset var jsonUtil = application.jsonUtil>
<cfset var response = [:]>

<!--- Validate inputs --->
<cfif not structKeyExists(form, "code") or not len(trim(form.code))>
    <cfset response["success"] = false>
    <cfset response["error"] = "No code provided.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfif not structKeyExists(form, "engine") or not len(trim(form.engine))>
    <cfset response["success"] = false>
    <cfset response["error"] = "No engine specified.">
    <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
    <cfabort>
</cfif>

<cfset var code = form.code>
<cfset var engineParam = trim(form.engine)>
<cfset var payloadsPath = expandPath(application.config.payloadsDir)>

<!--- Generate the payload filename: yyyymmddhhNNsslll-UUID.cfm --->
<cfset var timestamp = dateTimeFormat(now(), "yyyyMMddHHnnsslll")>
<cfset var requestId = createUUID()>
<cfset var fileName = timestamp & "-" & requestId & ".cfm">
<cfset var filePath = payloadsPath & "/" & fileName>

<!--- Write the payload file --->
<cfset fileWrite(filePath, code, "utf-8")>

<!--- Determine target engines --->
<cfset var targetEngines = []>
<cfif engineParam eq "all">
    <cfloop collection="#application.serverStatuses#" item="local.sKey">
        <cfif application.serverStatuses[local.sKey]["status"] eq "online">
            <cfset arrayAppend(targetEngines, local.sKey)>
        </cfif>
    </cfloop>
<cfelse>
    <cfif structKeyExists(application.serverRegistry, engineParam)>
        <cfset arrayAppend(targetEngines, engineParam)>
    <cfelse>
        <cfset response["success"] = false>
        <cfset response["error"] = "Unknown engine: " & encodeForHTML(engineParam)>
        <cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>
        <cfabort>
    </cfif>
</cfif>

<!--- Execute on each target engine --->
<cfset var results = []>
<cfset var execTimeout = application.config.executionTimeout>
<cfif execTimeout eq 0>
    <cfset execTimeout = 300><!--- default cfhttp timeout when disabled --->
</cfif>

<cfloop array="#targetEngines#" index="local.engineKey">
    <cfset var engineInfo = application.serverRegistry[local.engineKey]>
    <cfset var execURL = "http://#engineInfo['host']#:#engineInfo['port']#/#application.config.payloadsDir#/#fileName#?_pt=#application.config.payloadToken#">

    <cfset var result = [:]>
    <cfset result["requestId"] = requestId>
    <cfset result["timestamp"] = dateTimeFormat(now(), "yyyy-MM-dd'T'HH:nn:ss.lllZ")>
    <cfset result["engine"] = local.engineKey>
    <cfset result["cfengine"] = engineInfo["cfengine"]>

    <cfset var startTick = getTickCount()>

    <cftry>
        <cfhttp url="#execURL#" method="GET" timeout="#execTimeout#" result="local.httpResult">
            <cfhttpparam type="header" name="X-Payload-Token" value="#application.config.payloadToken#">
        </cfhttp>

        <cfset var duration = getTickCount() - startTick>
        <cfset result["duration"] = duration>

        <cfif val(local.httpResult.statusCode) gte 200 and val(local.httpResult.statusCode) lt 400>
            <cfset result["success"] = true>
            <cfset result["output"] = local.httpResult.fileContent>
        <cfelse>
            <!--- Uncaught error: normalize --->
            <cfset result["success"] = false>
            <cfset var errorBody = local.httpResult.fileContent>
            <cfset result["error"] = [:]>
            <cfset result["error"]["statusCode"] = local.httpResult.statusCode>
            <cfset result["error"]["message"] = _normalizeError(errorBody)>
            <cfset result["error"]["raw"] = errorBody>
        </cfif>
    <cfcatch type="any">
        <cfset var duration = getTickCount() - startTick>
        <cfset result["duration"] = duration>
        <cfset result["success"] = false>
        <cfset result["error"] = [:]>
        <cfset result["error"]["statusCode"] = "0">
        <cfset result["error"]["message"] = cfcatch.message>
        <cfif structKeyExists(cfcatch, "detail")>
            <cfset result["error"]["detail"] = cfcatch.detail>
        </cfif>
    </cfcatch>
    </cftry>

    <cfset arrayAppend(results, result)>
</cfloop>

<cfset response["success"] = true>
<cfset response["results"] = results>
<cfoutput>#jsonUtil.serializeJSON(response)#</cfoutput>

<!--- Helper: extract meaningful error from HTML error pages --->
<cffunction name="_normalizeError" access="private" returntype="string" output="false">
    <cfargument name="errorHTML" type="string" required="true">
    <cfset var msg = arguments.errorHTML>

    <!--- Try to extract text from common error page patterns --->
    <!--- Adobe CF: look for <title> or <b> with error message --->
    <cfset var titleMatch = reFind("<title[^>]*>([^<]+)</title>", msg, 1, true)>
    <cfif titleMatch.pos[1] gt 0 and arrayLen(titleMatch.pos) gte 2 and titleMatch.pos[2] gt 0>
        <cfreturn mid(msg, titleMatch.pos[2], titleMatch.len[2])>
    </cfif>

    <!--- Strip HTML tags as fallback --->
    <cfset msg = reReplace(msg, "<[^>]+>", " ", "all")>
    <cfset msg = reReplace(msg, "\s+", " ", "all")>
    <cfset msg = trim(msg)>

    <!--- Truncate if too long --->
    <cfif len(msg) gt 500>
        <cfset msg = left(msg, 500) & "...">
    </cfif>

    <cfreturn msg>
</cffunction>