<cfcomponent extends="Application" output="false">

    <cffunction name="onRequestStart" returntype="boolean" output="false">
        <cfargument name="targetPage" type="string" required="true">

        <!--- Call parent onRequestStart for IP check and path blocking --->
        <cfset var parentResult = super.onRequestStart(arguments.targetPage)>
        <cfif not parentResult>
            <cfreturn false>
        </cfif>

        <!--- Skip helper files (prefixed with underscore) — they are cfinclude only --->
        <cfif left(listLast(arguments.targetPage, "/\"), 1) eq "_">
            <cfcontent type="text/html" reset="true">
            <cfoutput>
                <h2>Access Denied</h2>
                <p>Direct access to this file is not permitted.</p>
            </cfoutput>
            <cfreturn false>
        </cfif>

        <!--- Set JSON content type for all api2 responses --->
        <cfcontent type="application/json" reset="true">

        <cfreturn true>
    </cffunction>

</cfcomponent>
