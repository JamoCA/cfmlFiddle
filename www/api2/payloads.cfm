<!---
	payloads.cfm
	Returns a list of payload files from the _payloads/ directory
	with name, timestamp (from filename), and size.
--->
<cfset _startTick = getTickCount()>
<cfset payloadsPath = application.config.payloadsPath>
<cfset response = [:]>

<cfif !directoryExists(payloadsPath)>
	<cfset response["success"] = application.jTrue>
	<cfset response["payloads"] = []>
	<cfset response["payloadCount"] = javacast("int", 0)>
	<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
	<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
	<cfabort>
</cfif>

<cfdirectory
	action="list"
	directory="#payloadsPath#"
	filter="*.cfm"
	name="fileQry"
	type="file"
	sort="dateLastModified desc">

<cfset payloads = []>
<cfloop query="fileQry">
	<cfset fName = fileQry.name>
	<!--- Parse timestamp from filename: yyyyMMddHHnnsslll-hash.cfm --->
	<cfset fTimestamp = "">
	<cfset dashPos = find("-", fName)>
	<cfif dashPos gte 18>
		<cfset tsRaw = left(fName, dashPos - 1)>
		<cftry>
			<cfset fTimestamp = dateTimeFormat(
				parseDateTime(
					mid(tsRaw,1,4) & "-" & mid(tsRaw,5,2) & "-" & mid(tsRaw,7,2) & " " &
					mid(tsRaw,9,2) & ":" & mid(tsRaw,11,2) & ":" & mid(tsRaw,13,2)
				),
				application.timestampMask
			)>
		<cfcatch>
			<cfset fTimestamp = dateTimeFormat(fileQry.dateLastModified, application.timestampMask)>
		</cfcatch>
		</cftry>
	<cfelse>
		<cfset fTimestamp = dateTimeFormat(fileQry.dateLastModified, application.timestampMask)>
	</cfif>

	<cfset entry = [
		"name": fName,
		"timestamp": fTimestamp,
		"size": javacast("int", fileQry.size)
	]>
	<cfset arrayAppend(payloads, entry)>
</cfloop>

<cfset response["success"] = application.jTrue>
<cfset response["payloads"] = payloads>
<cfset response["payloadCount"] = javacast("int", arrayLen(payloads))>
<cfset response["duration"] = javacast("int", getTickCount() - _startTick)>
<cfoutput>#application.jsonUtil.serializeJSON(var=response, strictMapping=true)#</cfoutput>
