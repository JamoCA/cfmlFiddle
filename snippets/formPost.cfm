<!--- Form Post Test - basic CFMLFiddle test --->
<cfoutput>
	<h2>Form Post Test</h2>
	<form action="" method="post">
		<div>
			<textarea name="textarea" style="width:95%; height:50px;" placeholder="Enter some text..." required><cfif form.keyexists("textarea")>#encodeforhtml(textarea)#</cfif></textarea>
		</div>
		<button type="submit">Submit</button>
	</form>
</cfoutput>

<cf_dump var="#FORM#" label="Form scope">
<cf_dump var="#URL#" label="URL scope">
