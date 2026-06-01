<!--- Hello World - basic CFMLFiddle test --->
<cfoutput>
	<h2>Hello from CFMLFiddle!</h2>
	<p><b>Engine:</b> <cfif structKeyExists(server,"coldfusion")>#server.coldfusion.productname# #server.coldfusion.productversion#<cfelseif structKeyExists(server,"boxlang")>BoxLang #server.boxlang.version#<cfelse>Unknown</cfif></p>
	<p><b>Timestamp:</b> #dateTimeFormat(now(), "iso")#</p>
	<p><b>IP Address:</b> #CGI.REMOTE_ADDR#</p>
</cfoutput>
