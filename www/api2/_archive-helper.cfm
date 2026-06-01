<!---
	_archive-helper.cfm
	Included by session-clear.cfm.
	Archives .cfm files from _payloads/ into ZIP files in archive/.
	Groups files by yyyymm prefix; names ZIPs with current timestamp + group month.
--->
<cfset payloadsPath = application.config.payloadsPath>
<cfset archivePath = application.config.archivePath>

<!--- Scan for .cfm files in _payloads/ --->
<cfdirectory
	action="list"
	directory="#payloadsPath#"
	filter="*.cfm"
	name="payloadFilesQry"
	type="file"
	sort="name asc">

<cfif !payloadFilesQry.recordCount>
	<!--- Nothing to archive --->
<cfelse>
	<!--- Group files by yyyymm prefix (first 6 chars of filename) --->
	<cfset groups = [:]>
	<cfloop query="payloadFilesQry">
		<cfset fileName = payloadFilesQry.name>
		<cfset groupKey = left(fileName, 6)>
		<cfif !structKeyExists(groups, groupKey)>
			<cfset groups[groupKey] = []>
		</cfif>
		<cfset arrayAppend(groups[groupKey], fileName)>
	</cfloop>

	<!--- Create a ZIP for each group --->
	<cfset currentTimestamp = dateTimeFormat(now(), "yyyyMMddHHnnsslll")>
	<cfloop collection="#groups#" item="groupMonth">
		<cfset zipName = currentTimestamp & "-" & groupMonth & ".zip">
		<cfset zipPath = archivePath & "/" & zipName>

		<cfzip action="zip" file="#zipPath#" overwrite="true">
			<cfloop array="#groups[groupMonth]#" index="cfmFile">
				<cfzipparam source="#payloadsPath#/#cfmFile#" entrypath="#cfmFile#">
			</cfloop>
		</cfzip>

		<!--- Delete the source files after successful ZIP --->
		<cfloop array="#groups[groupMonth]#" index="cfmFile">
			<cfset fileDelete(payloadsPath & "/" & cfmFile)>
		</cfloop>
	</cfloop>
</cfif>
