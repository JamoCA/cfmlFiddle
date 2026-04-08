<cfscript>
// Hello World — basic CFFiddle test
writeOutput("<h2>Hello from CFFiddle!</h2>");
writeOutput("<p>Engine: " & server.coldfusion.productname & " " & server.coldfusion.productversion & "</p>");
writeOutput("<p>Timestamp: " & dateTimeFormat(now(), "yyyy-MM-dd HH:nn:ss") & "</p>");
</cfscript>
