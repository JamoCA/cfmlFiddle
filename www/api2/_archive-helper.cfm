<!---
    _archive-helper.cfm
    Included by Application.cfc onApplicationStart (if archiveOnStartup)
    and by session-clear.cfm.
    Archives .cfm files from _payloads/ into ZIP files in archive/.
    Groups files by yyyymm prefix; names ZIPs with current timestamp + group month.
--->
<cfset var payloadsPath = expandPath(application.config.payloadsDir)>
<cfset var archivePath = expandPath(application.config.archiveDir)>

<!--- Scan for .cfm files in _payloads/ --->
<cfdirectory
    action="list"
    directory="#payloadsPath#"
    filter="*.cfm"
    name="local.payloadFiles"
    type="file"
    sort="name asc">

<cfif local.payloadFiles.recordCount eq 0>
    <!--- Nothing to archive --->
<cfelse>
    <!--- Group files by yyyymm prefix (first 6 chars of filename) --->
    <cfset var groups = [:]>
    <cfloop query="local.payloadFiles">
        <cfset var fileName = local.payloadFiles.name>
        <cfset var groupKey = left(fileName, 6)>
        <cfif not structKeyExists(groups, groupKey)>
            <cfset groups[groupKey] = []>
        </cfif>
        <cfset arrayAppend(groups[groupKey], fileName)>
    </cfloop>

    <!--- Create a ZIP for each group --->
    <cfset var currentTimestamp = dateTimeFormat(now(), "yyyyMMddHHnnsslll")>
    <cfloop collection="#groups#" item="local.groupMonth">
        <cfset var zipName = currentTimestamp & "-" & local.groupMonth & ".zip">
        <cfset var zipPath = archivePath & "/" & zipName>

        <cfzip action="zip" file="#zipPath#" overwrite="true">
            <cfloop array="#groups[local.groupMonth]#" index="local.cfmFile">
                <cfzipparam source="#payloadsPath#/#local.cfmFile#" entrypath="#local.cfmFile#">
            </cfloop>
        </cfzip>

        <!--- Delete the source files after successful ZIP --->
        <cfloop array="#groups[local.groupMonth]#" index="local.cfmFile">
            <cfset fileDelete(payloadsPath & "/" & local.cfmFile)>
        </cfloop>
    </cfloop>
</cfif>
