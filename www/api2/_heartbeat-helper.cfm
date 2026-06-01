<!---
	_heartbeat-helper.cfm
	Included by Application.cfc onRequestStart when heartbeat interval has elapsed.
	Uses a fast Java socket connect (500ms timeout) instead of HTTP HEAD.
	Respects status locks set by start/stop to prevent premature flipping.
	Uses cflock to prevent overlapping heartbeats.
--->
<cflock name="cfmlfiddle_heartbeat" type="exclusive" timeout="1" throwontimeout="false">

<cfset heartbeatStart = getTickCount()>
<cfset jSocket = createObject("java", "java.net.Socket")>
<cfset jInetAddr = createObject("java", "java.net.InetSocketAddress")>

<cfloop collection="#application.serverRegistry#" item="serverKey">
	<cfset serverInfo = application.serverRegistry[serverKey]>
	<cfset statusEntry = application.serverStatuses[serverKey]>
	<cfset currentStatus = statusEntry["status"]>

	<!--- Fast TCP socket connect check (500ms timeout) --->
	<cfset detectedStatus = "offline">
	<cftry>
		<cfset sock = jSocket.init()>
		<cfset addr = jInetAddr.init("127.0.0.1", javacast("int", serverInfo["port"]))>
		<cfset sock.connect(addr, javacast("int", 500))>
		<cfset sock.close()>
		<cfset detectedStatus = "online">
	<cfcatch>
		<cftry><cfset sock.close()><cfcatch></cfcatch></cftry>
	</cfcatch>
	</cftry>

	<!--- Determine whether to update the status.
		Transitional states (starting/stopping) only change when the
		detected state confirms the transition completed, or the lock expires. --->
	<cfset hasLock = structKeyExists(statusEntry, "statusLockedUntil")
		&& dateCompare(now(), statusEntry["statusLockedUntil"]) lt 0>

	<cfif currentStatus eq "starting">
		<cfif detectedStatus eq "online">
			<cfset statusEntry["status"] = "online">
			<cfset structDelete(statusEntry, "statusLockedUntil")>
		<cfelseif !hasLock>
			<cfset statusEntry["status"] = "offline">
			<cfset structDelete(statusEntry, "statusLockedUntil")>
		</cfif>

	<cfelseif currentStatus eq "stopping">
		<cfif detectedStatus eq "offline">
			<cfset statusEntry["status"] = "offline">
			<cfset structDelete(statusEntry, "statusLockedUntil")>
		<cfelseif !hasLock>
			<cfset statusEntry["status"] = "online">
			<cfset structDelete(statusEntry, "statusLockedUntil")>
		</cfif>

	<cfelse>
		<cfset statusEntry["status"] = detectedStatus>
	</cfif>

	<!--- Track when server came online --->
	<cfif statusEntry["status"] eq "online" && currentStatus neq "online">
		<cfset statusEntry["onlineSince"] = dateTimeFormat(now(), application.timestampMask)>
	<cfelseif statusEntry["status"] neq "online">
		<cfset statusEntry["onlineSince"] = "">
	</cfif>

	<!--- Fetch version for newly-online servers that don't have it cached --->
	<cfif statusEntry["status"] eq "online"
		&& (!structKeyExists(statusEntry, "productVersion") || !len(statusEntry["productVersion"]))>
		<cftry>
			<cfhttp url="http://localhost:#serverInfo['port']#/api2/version.cfm"
				method="GET" timeout="3" result="verResult" userAgent="#application.userAgent#">
				<cfhttpparam type="header" name="X-Payload-Token" value="#application.config.payloadToken#">
			</cfhttp>
			<cfif val(verResult.statusCode) eq 200>
				<cfset verData = application.jsonUtil.deserializeJSON(JSONvar=verResult.fileContent, strictMapping=true)>
				<cfif structKeyExists(verData, "productVersion")>
					<cfset statusEntry["productVersion"] = verData["productVersion"]>
				</cfif>
				<cfif structKeyExists(verData, "productName")>
					<cfset statusEntry["productName"] = verData["productName"]>
				</cfif>
			</cfif>
		<cfcatch>
			<!--- Version fetch failed; will retry next heartbeat --->
		</cfcatch>
		</cftry>
	</cfif>

	<!--- Clear version when server goes offline --->
	<cfif statusEntry["status"] eq "offline">
		<cfset statusEntry["productVersion"] = "">
		<cfset statusEntry["productName"] = "">
	</cfif>

	<cfset statusEntry["lastChecked"] = dateTimeFormat(now(), application.timestampMask)>
</cfloop>

<cfset application.heartbeatDuration = javacast("int", getTickCount() - heartbeatStart)>

</cflock>
