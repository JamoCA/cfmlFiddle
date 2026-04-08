<!---
    _heartbeat-helper.cfm
    Included by Application.cfc onRequestStart when heartbeat interval has elapsed.
    Pings each registered server to determine online/offline status.
--->
<cfloop collection="#application.serverRegistry#" item="local.serverKey">
    <cfset var serverInfo = application.serverRegistry[local.serverKey]>
    <cfset var statusEntry = application.serverStatuses[local.serverKey]>
    <cfset var pingURL = "http://#serverInfo['host']#:#serverInfo['port']#/">

    <cftry>
        <cfhttp url="#pingURL#" method="HEAD" timeout="5" result="local.pingResult">
        </cfhttp>

        <cfif val(local.pingResult.statusCode) gte 200 and val(local.pingResult.statusCode) lt 500>
            <cfset statusEntry["status"] = "online">
        <cfelse>
            <cfset statusEntry["status"] = "offline">
        </cfif>
    <cfcatch type="any">
        <cfset statusEntry["status"] = "offline">
    </cfcatch>
    </cftry>

    <cfset statusEntry["lastChecked"] = dateTimeFormat(now(), "yyyy-MM-dd'T'HH:nn:ss.lllZ")>
</cfloop>
