/**
 * CFMLFiddle - Configure
 * Run with: box task run configureCFMLFiddle
 *
 * Displays the current config.json values alongside hard-coded defaults,
 * flags anything that is missing, and lets you edit one setting at a
 * time. Changes are saved to config.json immediately after each edit.
 */
component {

	function run() {
		var configPath = resolvePath( "config.json" );
		var defaults = _getDefaults();
		var settings = _getSettings();

		var existing = _loadExisting( configPath );

		while ( true ) {
			_renderMenu( existing, defaults, settings, configPath );
			var choice = trim( ask( "Enter number to edit, or Q to quit: " ) );

			if ( !len( choice ) || listFindNoCase( "q,quit,exit,x", choice ) ) {
				print.line();
				print.greenLine( "Done." );
				return;
			}

			var idx = val( choice );
			if ( idx < 1 || idx > arrayLen( settings ) ) {
				print.redLine( "Invalid selection." );
				continue;
			}

			var s = settings[ idx ];
			var picked = _editSetting( s, existing, defaults );
			if ( !picked ) continue;

			// Save immediately after each edit
			_writeConfig( configPath, existing, defaults, settings );
			print.greenLine( "  saved." );
		}
	}

	/**
	 * Edit one setting via an arrow-key menu. Returns true if `existing`
	 * was mutated (caller should save), false to skip.
	 */
	private boolean function _editSetting(
		required struct setting,
		required struct existing,
		required struct defaults
	) {
		var s = arguments.setting;
		var hasCurrent = structKeyExists( arguments.existing, s.key );
		var curValue = hasCurrent ? arguments.existing[ s.key ] : "";
		var defValue = arguments.defaults[ s.key ];
		var curDisplay = hasCurrent ? _displayValue( curValue, s.type ) : "<missing>";
		var defDisplay = _displayValue( defValue, s.type );

		print.line();
		print.boldWhiteLine( s.key );
		print.greyLine( "  " & s.desc );

		// Build menu options: keep-current, use-default, enter-custom, cancel.
		// Omit redundant rows (e.g. "use default" when current already equals default).
		var options = [];
		if ( hasCurrent ) {
			arrayAppend( options, {
				display: "Keep current: " & curDisplay,
				value: "__keep__"
			} );
		}
		if ( !hasCurrent || curDisplay != defDisplay ) {
			arrayAppend( options, {
				display: ( hasCurrent ? "Reset to default: " : "Use default: " ) & defDisplay,
				value: "__default__"
			} );
		}
		// For booleans, offer a direct "toggle" shortcut
		if ( s.type == "boolean" && hasCurrent ) {
			arrayAppend( options, {
				display: "Set to " & ( _coerce( curValue, "boolean" ) ? "false" : "true" ),
				value: "__toggle__"
			} );
		}
		arrayAppend( options, {
			display: "Enter custom value...",
			value: "__custom__"
		} );
		arrayAppend( options, {
			display: "Cancel (no change)",
			value: "__cancel__"
		} );

		var pick = multiselect( "  Choose:" )
			.setOptions( options )
			.ask();

		switch ( pick ) {
			case "__keep__":
				print.greyLine( "  no change." );
				return false;
			case "__cancel__":
				print.greyLine( "  cancelled." );
				return false;
			case "__default__":
				arguments.existing[ s.key ] = defValue;
				return true;
			case "__toggle__":
				arguments.existing[ s.key ] = !_coerce( curValue, "boolean" );
				return true;
			case "__custom__":
				var answer = trim( ask( "  new value: " ) );
				if ( !len( answer ) ) {
					print.greyLine( "  no value entered, cancelled." );
					return false;
				}
				arguments.existing[ s.key ] = _coerce( answer, s.type );
				return true;
		}
		return false;
	}

	/**
	 * Load existing config.json into an ordered struct keyed in the same
	 * order as the defaults (unknown keys from the file are appended).
	 */
	private struct function _loadExisting( required string configPath ) {
		var out = structNew( "ordered" );
		if ( !fileExists( arguments.configPath ) ) return out;

		try {
			var raw = deserializeJSON( fileRead( arguments.configPath, "utf-8" ) );
			// Preserve whatever order the file has
			for ( var k in raw ) out[ k ] = raw[ k ];
		} catch ( any e ) {
			print.redLine( "Could not parse config.json: #e.message#" );
			print.yellowLine( "Starting from defaults." );
		}
		return out;
	}

	/**
	 * Render the main menu with current/default/missing indicators.
	 */
	private void function _renderMenu(
		required struct existing,
		required struct defaults,
		required array settings,
		required string configPath
	) {
		print.line();
		print.boldCyanLine( "=== CFMLFiddle - Configure ===" );
		print.greyLine( arguments.configPath );
		print.line();

		var missingCount = 0;
		var maxKeyLen = 0;
		for ( var s in arguments.settings ) {
			if ( len( s.key ) > maxKeyLen ) maxKeyLen = len( s.key );
		}

		for ( var i = 1; i <= arrayLen( arguments.settings ); i++ ) {
			var s = arguments.settings[ i ];
			var hasCurrent = structKeyExists( arguments.existing, s.key );
			var padNum = ( i < 10 ? " " : "" ) & i;
			var padKey = s.key & repeatString( " ", maxKeyLen - len( s.key ) );

			print.text( "  " );
			print.boldWhiteText( padNum );
			print.text( ") " );
			print.cyanText( padKey );
			print.text( "  " );

			if ( !hasCurrent ) {
				print.redText( "<missing>" );
				print.text( "  (default: " );
				print.yellowText( _displayValue( arguments.defaults[ s.key ], s.type ) );
				print.line( ")" );
				missingCount++;
			} else {
				var curDisplay = _displayValue( arguments.existing[ s.key ], s.type );
				var defDisplay = _displayValue( arguments.defaults[ s.key ], s.type );
				print.whiteText( curDisplay );
				if ( curDisplay != defDisplay ) {
					print.text( "  (default: " );
					print.yellowText( defDisplay );
					print.line( ")" );
				} else {
					print.line();
				}
			}
		}
		print.line();
		if ( missingCount > 0 ) {
			print.redLine( "#missingCount# setting(s) missing from config.json." );
			print.line();
		}
		print.boldWhiteText( "  Q" );
		print.line( ") Save and exit" );
		print.line();
	}

	/**
	 * Convert input value to the correct type.
	 */
	private any function _coerce( required any value, required string type ) {
		var v = arguments.value;
		switch ( arguments.type ) {
			case "number":
				return isNumeric( v ) ? javaCast( "long", v ) : val( v );
			case "boolean":
				var s = lCase( trim( toString( v ) ) );
				return ( listFindNoCase( "y,yes,true,1,on", s ) > 0 ) ? true : false;
			default:
				return toString( v );
		}
	}

	/**
	 * Format a value for display.
	 */
	private string function _displayValue( required any value, required string type ) {
		if ( arguments.type == "boolean" ) {
			return _coerce( arguments.value, "boolean" ) ? "true" : "false";
		}
		return toString( arguments.value );
	}

	/**
	 * Write config.json. Keys are emitted in the order defined by settings
	 * (_comment first). Unknown keys from the existing file are preserved
	 * and appended at the end.
	 */
	private void function _writeConfig(
		required string configPath,
		required struct existing,
		required struct defaults,
		required array settings
	) {
		var ordered = structNew( "ordered" );
		var types = { "_comment": "string" };

		// _comment always present at top (use existing if set, else default)
		ordered[ "_comment" ] = structKeyExists( arguments.existing, "_comment" )
			? arguments.existing[ "_comment" ]
			: arguments.defaults[ "_comment" ];

		// Known settings in canonical order
		for ( var s in arguments.settings ) {
			if ( structKeyExists( arguments.existing, s.key ) ) {
				ordered[ s.key ] = arguments.existing[ s.key ];
				types[ s.key ] = s.type;
			}
		}

		// Preserve any unknown keys the user may have added
		for ( var k in arguments.existing ) {
			if ( !structKeyExists( ordered, k ) ) {
				ordered[ k ] = arguments.existing[ k ];
				types[ k ] = "string";
			}
		}

		fileWrite( arguments.configPath, _toJSON( ordered, types ), "utf-8" );
	}

	/**
	 * Ordered list of settings to prompt for, with type and description.
	 */
	private array function _getSettings() {
		return [
			{ key: "allowedIPs", type: "string",
			  desc: "Comma-separated IP allowlist. Use * for any." },
			{ key: "executionTimeout", type: "number",
			  desc: "Seconds before a script is killed. 0 = no limit (adjustable in UI)." },
			{ key: "serverPollInterval", type: "number",
			  desc: "How often the server-side heartbeat runs (seconds)." },
			{ key: "clientPollInterval", type: "number",
			  desc: "How often the UI polls for updates (seconds). Ignored when SSE is active." },
			{ key: "startupTimeout", type: "number",
			  desc: "How long to wait for a server to come online (seconds)." },
			{ key: "editorTheme", type: "string",
			  desc: "Ace Editor theme name (e.g. monokai, chrome, twilight)." },
			{ key: "serverNamePrefix", type: "string",
			  desc: "Prefix used to identify CFMLFiddle servers (e.g. cfmlfiddle-)." },
			{ key: "boxExe", type: "string",
			  desc: "Full path to the CommandBox executable." },
			{ key: "payloadsDir", type: "string",
			  desc: "Directory for payload temp files (relative to www/ or absolute)." },
			{ key: "archiveDir", type: "string",
			  desc: "Directory for zipped old payloads." },
			{ key: "snippetsDir", type: "string",
			  desc: "Directory containing loadable code samples." },
			{ key: "customTagsDir", type: "string",
			  desc: "Directory containing shared CFML custom tags." },
			{ key: "javaLibsDir", type: "string",
			  desc: "Directory containing shared Java JARs." },
			{ key: "templateServersDir", type: "string",
			  desc: "Directory containing server.*.json templates." },
			{ key: "useLocalAssets", type: "boolean",
			  desc: "Load JS/CSS from local assets/vendor/ instead of CDN (y/n)." },
			{ key: "useSSE", type: "boolean",
			  desc: "Use Server-Sent Events instead of polling (y/n)." }
		];
	}

	/**
	 * Hard-coded default values for all settings.
	 */
	private struct function _getDefaults() {
		var d = structNew( "ordered" );
		d[ "_comment" ] = "CFMLFiddle configuration. Edit these values to customize the app. This file is read by Application.cfc on startup. Use Reinit to reload after changes.";
		d[ "allowedIPs" ] = "127.0.0.1,::1,0:0:0:0:0:0:0:1";
		d[ "executionTimeout" ] = 0;
		d[ "serverPollInterval" ] = 30;
		d[ "clientPollInterval" ] = 10;
		d[ "startupTimeout" ] = 60;
		d[ "editorTheme" ] = "monokai";
		d[ "serverNamePrefix" ] = "cfmlfiddle-";
		d[ "boxExe" ] = "c:\commandbox\box.exe";
		d[ "payloadsDir" ] = "_payloads";
		d[ "archiveDir" ] = "../archive";
		d[ "snippetsDir" ] = "../snippets";
		d[ "customTagsDir" ] = "../CustomTags";
		d[ "javaLibsDir" ] = "../JavaLibs";
		d[ "templateServersDir" ] = "../current-servers";
		d[ "useLocalAssets" ] = true;
		d[ "useSSE" ] = true;
		return d;
	}

	/**
	 * Serialize a flat config struct to pretty JSON matching the existing
	 * config.json layout: 4-space indent, blank line after _comment, and
	 * blank lines between logical groups. `types` maps each key to
	 * "string", "number", or "boolean" so values serialize unambiguously.
	 */
	private string function _toJSON( required struct config, required struct types ) {
		var lines = [ "{" ];
		var keys = structKeyArray( arguments.config );
		var lastIdx = arrayLen( keys );

		// Keys after which a blank line is inserted (logical grouping)
		var groupBreaks = "_comment,allowedIPs,executionTimeout,clientPollInterval,startupTimeout,editorTheme,serverNamePrefix,boxExe,templateServersDir,useLocalAssets";

		for ( var i = 1; i <= lastIdx; i++ ) {
			var key = keys[ i ];
			var type = structKeyExists( arguments.types, key ) ? arguments.types[ key ] : "string";
			var raw = arguments.config[ key ];
			var comma = ( i < lastIdx ) ? "," : "";
			arrayAppend( lines, "    " & serializeJSON( key ) & ": " & _jsonVal( raw, type ) & comma );
			if ( i < lastIdx && listFindNoCase( groupBreaks, key ) ) {
				arrayAppend( lines, "" );
			}
		}
		arrayAppend( lines, "}" );
		return arrayToList( lines, chr( 10 ) ) & chr( 10 );
	}

	private string function _jsonVal( required any v, required string type ) {
		switch ( arguments.type ) {
			case "boolean":
				return arguments.v ? "true" : "false";
			case "number":
				return toString( arguments.v );
			default:
				return serializeJSON( toString( arguments.v ) );
		}
	}

}
