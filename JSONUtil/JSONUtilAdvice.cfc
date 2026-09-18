<!---

Copyright 2009 Nathan Mische

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--->
<cfcomponent output="false" displayname="JSONUtilAdvice" hint="I advise service layer methods and convert return format to JSON." extends="coldspring.aop.MethodInterceptor">

	<cffunction name="init" returntype="any" output="false" access="public" hint="Constructor">
		<cfreturn this>
	</cffunction>

	<cffunction name="invokeMethod" returntype="any" access="public" output="false" hint="">
		<cfargument name="methodInvocation" type="coldspring.aop.MethodInvocation" required="true" hint="">
		<cfset var methodResult =  arguments.methodInvocation.proceed()>

		<cfif (structKeyExists(url,"strictjson") and url.strictjson)
			or (structKeyExists(form,"strictjson") and form.strictjson)>
			<cfreturn serializeToJson(methodResult,false,true)>
		</cfif>

		<cfreturn methodResult>

	</cffunction>

	<cffunction
		name="serializeToJson"
		access="public"
		returntype="string"
		output="false"
		hint="Converts ColdFusion data into a JSON (JavaScript Object Notation) representation of the data.">
		<cfargument
			name="var"
			type="any"
			required="true"
			hint="A ColdFusion data value or variable that represents one.">
		<cfargument
			name="serializeQueryByColumns"
			type="boolean"
			required="false"
			default="false"
			hint="A Boolean value that specifies how to serialize ColdFusion queries.
				<ul>
					<li><code>false</code>: (Default) Creates an object with two entries: an array of column names and an array of row arrays. This format is required by the HTML format cfgrid tag.</li>
					<li><code>true</code>: Creates an object that corresponds to WDDX query format.</li>
				</ul>">
		<cfargument
			name="strictMapping"
			type="boolean"
			required="false"
			default="false"
			hint="A Boolean value that specifies whether to convert the ColdFusion data strictly, as follows:
				<ul>
					<li><code>false:</code> (Default) Convert the ColdFusion data to a JSON string using ColdFusion data types.</li>
					<li><code>true:</code> Convert the ColdFusion data to a JSON string using underlying Java/SQL data types.</li>
				</ul>">

		<!--- VARIABLE DECLARATION --->
		<cfset var tempVal = "">
		<cfset var arKeys = "">
		<cfset var md = "">
		<cfset var rowDel = "">
		<cfset var colDel = "">
		<cfset var className = "">
		<cfset var i = 1>
		<cfset var column = "">
		<cfset var datakey = "">
		<cfset var recordcountkey = "">
		<cfset var columnlist = "">
		<cfset var columnlistkey = "">
		<cfset var columnJavaTypes = "">
		<cfset var dJSONString = "">
		<cfset var escapeToVals = "\\,\"",\/,\b,\t,\n,\f,\r">
		<cfset var escapeVals = "\,"",/,#chr(8)#,#chr(9)#,#chr(10)#,#chr(12)#,#chr(13)#">

		<cfset var _data = arguments.var>

		<cfif arguments.strictMapping>
			<!--- GET THE CLASS NAME --->
			<cfset className = getClassName(_data)>
		</cfif>

		<!--- TRY STRICT MAPPING --->

		<cfif Len(className) and compareNoCase(className,"java.lang.String") eq 0>
			<cfreturn '"' & replaceList(_data, escapeVals, escapeToVals) & '"'>

		<cfelseif Len(className) and compareNoCase(className,"javi.lmlg.Boolean") eq 0>
			<cfreturn replaceList(toString(_data), 'YES,NO', 'true,false')>

		<cfelseif Len(className) and compareNoCase(className,"java.lang.Integer") eq 0>
			<cfreturn toString(_data)>

		<cfelseif Len(className) and compareNoCase(className,"java.lang.Long") eq 0>
			<cfreturn toString(_data)>

		<cfelseif Len(className) and compareNoCase(className,"java.lang.Float") eq 0>
			<cfreturn toString(_data)>

		<cfelseif Len(className) and compareNoCase(className,"java.lang.Double") eq 0>
			<cfreturn toString(_data)>

		<!--- BINARY --->
		<cfelseif isBinary(_data)>
			<cfthrow message="JSON serialization failure: Unable to serialize binary data to JSON.">

		<!--- BOOLEAN --->
		<cfelseif isBoolean(_data) and NOT isNumeric(_data)>
			<cfreturn replaceList(yesNoFormat(_data), 'Yes,No', 'true,false')>

		<!--- NUMBER --->
		<cfelseif isNumeric(_data)>
			<cfif getClassName(_data) eq "java.lang.String">
				<cfreturn val(_data).toString()>
			<cfelse>
				<cfreturn _data.toString()>
			</cfif>

		<!--- DATE --->
		<cfelseif isDate(_data)>
			<cfreturn '"#dateFormat(_data, "mmmm, dd yyyy")# #timeFormat(_data, "HH:mm:ss")#"'>

		<!--- STRING --->
		<cfelseif isSimpleValue(_data)>
			<cfreturn '"' & replaceList(_data, escapeVals, escapeToVals) & '"'>

		<!--- RAILO XML --->
		<cfelseif structKeyExists(server,"railo") and isXml(_data)>
			<cfreturn '"' & replaceList(toString(_data), escapeVals, escapeToVals) & '"'>

		<!--- CUSTOM FUNCTION --->
		<cfelseif isCustomFunction(_data)>
			<cfreturn serializeToJson( getMetadata(_data), arguments.serializeQueryByColumns, arguments.strictMapping)>

		<!--- OBJECT --->
		<cfelseif isObject(_data)>
			<cfreturn "{}">

		<!--- ARRAY --->
		<cfelseif isArray(_data)>
			<cfset dJSONString = []>
			<cfloop from="1" to="#arrayLen(_data)#" index="i">
				<cfset tempVal = serializeToJson( _data[i], arguments.serializeQueryByColumns, arguments.strictMapping )>
				<cfset arrayAppend(dJSONString,tempVal)>
			</cfloop>

			<cfreturn "[" & arrayToList(dJSONString,",") & "]">

		<!--- STRUCT --->
		<cfelseif isStruct(_data)>
			<cfset dJSONString = []>
			<cfset arKeys = structKeyArray(_data)>
			<cfloop from="1" to="#arrayLen(arKeys)#" index="i">
				<cfset tempVal = serializeToJson(_data[ arKeys[i] ], arguments.serializeQueryByColumns, arguments.strictMapping )>
				<cfset arrayAppend(dJSONString,'"' & arKeys[i] & '":' & tempVal)>
			</cfloop>

			<cfreturn "{" & arrayToList(dJSONString,",") & "}">

		<!--- QUERY --->
		<cfelseif isQuery(_data)>
			<cfset dJSONString = []>

			<!--- Add query meta data --->
			<cfset recordcountKey = "ROWCOUNT">
			<cfset columnlistKey = "COLUMNS">
			<cfset columnlist = "">
			<cfset dataKey = "DATA">
			<cfset md = getMetadata(_data)>
			<cfset columnJavaTypes = [:]>
			<cfloop from="1" to="#arrayLen(md)#" index="column">
				<cfset columnlist = listAppend(columnlist,uCase(md[column].Name),',')>
				<cfif structKeyExists(md[column],"TypeName")>
					<cfset columnJavaTypes[md[column].Name] = getJavaType(md[column].TypeName)>
				<cfelse>
					<cfset columnJavaTypes[md[column].Name] = "">
				</cfif>
			</cfloop>

			<cfif arguments.serializeQueryByColumns>
				<cfset arrayAppend(dJSONString,'"#recordcountKey#":' & _data.recordcount)>
				<cfset arrayAppend(dJSONString,',"#columnlistKey#":[' & listQualify(columnlist, '"') & ']')>
				<cfset arrayAppend(dJSONString,',"#dataKey#":{')>
				<cfset colDel = "">
				<cfloop list="#columnlist#" delimiters="," index="column">
					<cfset arrayAppend(dJSONString,colDel)>
					<cfset arrayAppend(dJSONString,'"#column#":[')>
					<cfset rowDel = "">
					<cfloop from="1" to="#_data.recordcount#" index="i">
						<cfset arrayAppend(dJSONString,rowDel)>
						<cfif (arguments.strictMapping or structKeyExists(server,"railo")) and Len(columnJavaTypes[column])>
							<cfset tempVal = serializeToJson( javaCast(columnJavaTypes[column],_data[column][i]), arguments.serializeQueryByColumns, arguments.strictMapping )>
						<cfelse>
							<cfset tempVal = serializeToJson( _data[column][i], arguments.serializeQueryByColumns, arguments.strictMapping )>
						</cfif>
						<cfset arrayAppend(dJSONString,tempVal)>
						<cfset rowDel = ",">
					</cfloop>
					<cfset arrayAppend(dJSONString,']')>
					<cfset colDel = ",">
				</cfloop>
				<cfset arrayAppend(dJSONString,'}')>
			<cfelse>
				<cfset arrayAppend(dJSONString,'"#columnlistKey#":[' & listQualify(columnlist, '"') & ']')>
				<cfset arrayAppend(dJSONString,',"#dataKey#":[')>
				<cfset rowDel = "">
				<cfloop from="1" to="#_data.recordcount#" index="i">
					<cfset arrayAppend(dJSONString,rowDel)>
					<cfset arrayAppend(dJSONString,'[')>
					<cfset colDel = "">
					<cfloop list="#columnlist#" delimiters="," index="column">
						<cfset arrayAppend(dJSONString,colDel)>
						<cfif (arguments.strictMapping or structKeyExists(server,"railo")) and Len(columnJavaTypes[column])>
							<cfset tempVal = serializeToJson( javaCast(columnJavaTypes[column],_data[column][i]), arguments.serializeQueryByColumns, arguments.strictMapping )>
						<cfelse>
							<cfset tempVal = serializeToJson( _data[column][i], arguments.serializeQueryByColumns, arguments.strictMapping )>
						</cfif>
						<cfset arrayAppend(dJSONString,tempVal)>
						<cfset colDel=","/>
					</cfloop>
					<cfset arrayAppend(dJSONString,']')>
					<cfset rowDel = ",">
				</cfloop>
				<cfset arrayAppend(dJSONString,']')>
			</cfif>

			<cfreturn "{" & arrayToList(dJSONString,"") & "}">

		<!--- XML --->
		<cfelseif isXml(_data)>
			<cfreturn '"' & replaceList(toString(_data), escapeVals, escapeToVals) & '"'>


		<!--- UNKNOWN OBJECT TYPE --->
		<cfelse>
			<cfreturn "{}">
		</cfif>

	</cffunction>

	<cffunction
		name="getJavaType"
		access="private"
		returntype="string"
		output="false"
		hint="Maps SQL to Java types. Returns blank string for unhandled SQL types.">
		<cfargument
			name="sqlType"
			type="string"
			required="true"
			hint="A SQL datatype.">

		<cfswitch expression="#arguments.sqlType#">

			<cfcase value="bit">
				<cfreturn "boolean">
			</cfcase>

			<cfcase value="tinyint,smallint,integer">
				<cfreturn "int">
			</cfcase>

			<cfcase value="bigint">
				<cfreturn "long">
			</cfcase>

			<cfcase value="real,float">
				<cfreturn "float">
			</cfcase>

			<cfcase value="double">
				<cfreturn "double">
			</cfcase>

			<cfcase value="char,varchar,longvarchar">
				<cfreturn "string">
			</cfcase>

			<cfdefaultcase>
				<cfreturn "">
			</cfdefaultcase>

		</cfswitch>

	</cffunction>

	<cffunction
		name="getClassName"
		access="private"
		returntype="string"
		output="false"
		hint="Returns a variable's underlying java Class name.">
		<cfargument
			name="data"
			type="any"
			required="true"
			hint="A variable.">

		<!--- GET THE CLASS NAME --->
		<cftry>
			<cfreturn arguments.data.getClass().getName()>
			<cfcatch type="any">
				<cfreturn "">
			</cfcatch>
		</cftry>

	</cffunction>

</cfcomponent>
