<cfset headers = getHttpRequestData().headers>

<cfsavecontent variable="menu"><div><a href="#server">Server</a> | <a href="#application">Application</a> | <a href="#cookie">Cookie</a> | <a href="#cgi">CGI</a> | <a href="#headers">Request Headers</a> | <a href="#form">Form</a> | <a href="#url">URL</a></div></cfsavecontent>

<h1>CFInfo</h1>

<h2 id="server">Server</h2>
<cfoutput>#menu#</cfoutput>
<cf_dump var="#server#" label="Server" expand="true">

<h2 id="application">Application</h2>
<cfoutput>#menu#</cfoutput>
<cf_dump var="#application#" label="Application" expand="true">

<h2 id="cookie">Cookie</h2>
<cfoutput>#menu#</cfoutput>
<cf_dump var="#cookie#" label="Cookie" expand="true">

<h2 id="cgi">CGI</h2>
<cfoutput>#menu#</cfoutput>
<cf_dump var="#cgi#" label="CGI" expand="true">

<h2 id="headers">Request Headers</h2>
<cfoutput>#menu#</cfoutput>
<cf_dump var="#headers#" label="HTTP Request Headers" expand="true">

<h2 id="form">Form</h2>
<cfoutput>#menu#</cfoutput>
<cf_dump var="#Form#" label="Form" expand="true">

<h2 id="url">URL</h2>
<cfoutput>#menu#</cfoutput>
<cf_dump var="#url#" label="URL" expand="true">