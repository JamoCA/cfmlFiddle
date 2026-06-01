<!---
	version.cfm
	Returns the running engine's version info.
	Used by the heartbeat to detect actual patch versions.
	Kept standalone (no application scope dependencies) so it works
	even before the child server's application has fully initialized.
--->
<cfif structKeyExists(server, "coldfusion")>
	<cfset pName = server.coldfusion.productname>
	<cfset pVersion = server.coldfusion.productversion>
<cfelseif structKeyExists(server, "boxlang")>
	<cfset pName = "BoxLang">
	<cfset pVersion = server.boxlang.version>
<cfelse>
	<cfset pName = "Unknown">
	<cfset pVersion = "">
</cfif>
<cfset response = [
	"success": true,
	"productName": pName,
	"productVersion": pVersion
]>
<cfcontent type="application/json" reset="true">
<cfoutput>#serializeJSON(response)#</cfoutput>
