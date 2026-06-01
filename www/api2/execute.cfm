<!---
	execute.cfm
	Receives CFML payload and target engine(s), executes via cfhttp.
	Expects:
	form.code        - the CFML source code (required unless payloadFile is provided)
	form.payloadFile - existing payload filename to re-execute (alternative to code)
	form.engine      - target engine key (e.g., "cf2025") or "all" for all online
	Returns JSON with execution results.
--->

<!--- Helper: extract meaningful error from HTML error pages (defined before use for cross-engine compatibility) --->
<cffunction name="_normalizeError" access="private" returntype="string" output="false">
	<cfargument name="errorHTML" type="string" required="true">
	<cfset var msg = arguments.errorHTML>

	<!--- Try to extract text from common error page patterns --->
	<cfset var titleMatch = reFind("<title[^>]*>([^<]+)</title>", msg, 1, true)>
	<cfif titleMatch.pos[1] gt 0 && arrayLen(titleMatch.pos) gte 2 && titleMatch.pos[2] gt 0>
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

<cfset _startTick = getTickCount()>
<cfset response = [:]>

<!--- Validate engine --->
<cfif !structKeyExists(form, "engine") || !len(trim(form.engine))>
	<cfset response["success"] = application.jFalse>
	<cfset response["error"] = "No engine specified.">
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfset engineParam = trim(form.engine)>
<cfset payloadsPath = application.config.payloadsPath>

<!--- Support re-running an existing payload file (refresh) --->
<cfif structKeyExists(form, "payloadFile") && len(trim(form.payloadFile))>
	<cfset fileName = trim(form.payloadFile)>
	<!--- Validate filename format and existence --->
	<cfif reFind("[^a-zA-Z0-9_\-\.]", fileName) || !fileExists(payloadsPath & "/" & fileName)>
		<cfset response["success"] = application.jFalse>
		<cfset response["error"] = "Payload file not found.">
		<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
		<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
		<cfabort>
	</cfif>
	<cfset requestId = getTickCount()>
<cfelse>
	<!--- Validate code input --->
	<cfif !structKeyExists(form, "code") || !len(trim(form.code))>
		<cfset response["success"] = application.jFalse>
		<cfset response["error"] = "No code provided.">
		<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
		<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
		<cfabort>
	</cfif>

	<cfset code = form.code>

	<!--- Validate that payload contains only text content (reject null bytes and binary control chars) --->
	<cfif reFind("[\x00-\x08\x0E-\x1F]", code)>
		<cfset response["success"] = application.jFalse>
		<cfset response["error"] = "BINARY_CONTENT">
		<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
		<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
		<cfabort>
	</cfif>

	<!--- Prepend server-side request timeout to the payload so the target
			engine aborts execution if it exceeds the configured limit. --->
	<cfset execTimeout = application.config.executionTimeout>
	<cfif execTimeout gt 0>
		<cfset code = '<cfsetting requesttimeout="#execTimeout#">' & chr(10) & code>
	</cfif>

	<!--- Generate content hash from code (includes timeout prefix, so
			same code with different timeout = different hash/file) --->
	<cfset codeHash = abs(trim(code).hashCode())>

	<!--- Check if a file with this hash already exists --->
	<cfset fileName = "">
	<cfset existingFiles = directoryList(payloadsPath, false, "name", "*-#codeHash#.cfm")>
	<cfif arrayLen(existingFiles)>
		<!--- Reuse existing file --->
		<cfset fileName = existingFiles[1]>
	<cfelse>
		<!--- Create new file: yyyymmddhhNNsslll-hashCode.cfm --->
		<cfset timestamp = dateTimeFormat(now(), "yyyyMMddHHnnsslll")>
		<cfset fileName = timestamp & "-" & codeHash & ".cfm">
		<cfset fileWrite(payloadsPath & "/" & fileName, code, "utf-8")>
	</cfif>

	<cfset requestId = getTickCount()>
</cfif>

<!--- Determine target engines --->
<cfset targetEngines = []>
<cfif engineParam eq "all">
	<cfloop collection="#application.serverStatuses#" item="sKey">
		<cfif application.serverStatuses[sKey]["status"] eq "online">
			<cfset arrayAppend(targetEngines, sKey)>
		</cfif>
	</cfloop>
<cfelse>
	<cfif structKeyExists(application.serverRegistry, engineParam)>
		<cfset arrayAppend(targetEngines, engineParam)>
	<cfelse>
		<cfset response["success"] = application.jFalse>
		<cfset response["error"] = "Unknown engine: " & encodeForHTML(engineParam)>
		<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
		<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
		<cfabort>
	</cfif>
</cfif>

<!--- Execute on each target engine --->
<cfset results = []>
<cfset execTimeout = application.config.executionTimeout>
<cfif execTimeout eq 0>
	<cfset execTimeout = 300><!--- default cfhttp timeout when disabled --->
</cfif>

<cfset signedToken = hash(fileName & application.config.payloadToken, "SHA-256")>

<cfloop array="#targetEngines#" index="engineKey">
	<cfset engineInfo = application.serverRegistry[engineKey]>
	<cfset execURL = "http://#engineInfo['host']#:#engineInfo['port']#/#application.config.payloadsDir#/#fileName#">
	<cfset interactiveURL = execURL & "?_tk=" & signedToken>

	<cfset result = [
		"requestId": requestId,
		"timestamp": dateTimeFormat(now(), application.timestampMask),
		"interactiveURL": interactiveURL,
		"payloadFile": fileName,
		"engine": engineKey,
		"cfengine": engineInfo["cfengine"]
	]>

	<cfset startTick = getTickCount()>

	<cftry>
		<cfhttp url="#execURL#" method="GET" timeout="#execTimeout#" result="httpResult" userAgent="#application.userAgent#">
			<cfhttpparam type="header" name="X-Payload-Token" value="#application.config.payloadToken#">
		</cfhttp>

		<cfset duration = getTickCount() - startTick>
		<cfset result["duration"] = javacast("int", duration)>

		<cfif val(httpResult.statusCode) gte 200 && val(httpResult.statusCode) lt 400>
			<cfset result["success"] = application.jTrue>
			<cfset result["output"] = httpResult.fileContent>
		<cfelse>
			<!--- Uncaught error: normalize --->
			<cfset result["success"] = application.jFalse>
			<cfset errorBody = httpResult.fileContent>
			<cfset result["error"] = [
				"statusCode": httpResult.statusCode,
				"message": _normalizeError(errorBody),
				"raw": errorBody
			]>
		</cfif>
	<cfcatch type="any">
		<cfset duration = getTickCount() - startTick>
		<cfset result["duration"] = javacast("int", duration)>
		<cfset result["success"] = application.jFalse>
		<cfset result["error"] = [
			"statusCode": "0",
			"message": cfcatch.message
		]>
		<cfif structKeyExists(cfcatch, "detail")>
			<cfset result["error"]["detail"] = cfcatch.detail>
		</cfif>
	</cfcatch>
	</cftry>

	<cfset arrayAppend(results, result)>
</cfloop>

<cfset response["success"] = application.jTrue>
<cfset response["results"] = results>
<cfset response["payloadCount"] = javacast("int", arrayLen(directoryList(payloadsPath, false, "name", "*.cfm")))>
<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
