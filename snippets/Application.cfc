<cfcomponent output="false">

    <cffunction name="onRequestStart" returntype="boolean" output="true">
        <cfargument name="targetPage" type="string" required="true">
        <cfcontent type="text/html" reset="true">
        <cfoutput>
            <h2>Access Denied</h2>
            <p>Direct access to this directory is not permitted.</p>
        </cfoutput>
        <cfreturn false>
    </cffunction>

</cfcomponent>
