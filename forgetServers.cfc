/**
 * CFMLFiddle - Forget Servers
 * Run with: box task run forgetServers
 *
 * Lists all CFMLFiddle server configs, shows which are registered
 * and running, and lets you stop and forget individual servers or all.
 */
component {

	function run() {
		var configDir = resolvePath( "current-servers" );

		// Read server names from our config files
		var configFiles = directoryList( configDir, false, "name", "server.*.json" );
		if ( !arrayLen( configFiles ) ) {
			print.redLine( "No server configs found in current-servers/" );
			return;
		}

		var ourNames = [];
		var engineMap = {};
		for ( var fileName in configFiles ) {
			var config = deserializeJSON( fileRead( configDir & "/" & fileName, "utf-8" ) );
			var serverName = config.name ?: fileName;
			arrayAppend( ourNames, serverName );
			engineMap[ serverName ] = config.app.cfengine ?: "unknown";
		}

		// Get all registered servers (plain text, parse name + status)
		print.yellowLine( "Checking CommandBox server registrations..." );
		var registeredMap = _getRegisteredServers();

		// Match our config names against registered servers
		var servers = [];
		for ( var serverName in ourNames ) {
			var info = {
				"name": serverName,
				"cfengine": engineMap[ serverName ],
				"registered": false,
				"status": "not registered"
			};

			// Case-insensitive lookup
			for ( var regName in registeredMap ) {
				if ( compareNoCase( regName, serverName ) == 0 ) {
					info.registered = true;
					info.status = registeredMap[ regName ];
					break;
				}
			}

			arrayAppend( servers, info );
		}

		// Display all servers with status
		print.line();
		print.boldCyanLine( "=== CFMLFiddle - Server Status ===" );
		print.line();

		var hasRegistered = false;
		for ( var i = 1; i <= arrayLen( servers ); i++ ) {
			var s = servers[ i ];
			print.text( "  " );
			print.boldWhiteText( "#i#" );
			print.text( ") " );
			print.cyanText( s.name );
			print.text( "  " );
			print.yellowText( s.cfengine );
			print.text( "  " );
			if ( s.registered && s.status == "running" ) {
				print.greenLine( "running" );
				hasRegistered = true;
			} else if ( s.registered ) {
				print.whiteLine( "registered (#s.status#)" );
				hasRegistered = true;
			} else {
				print.greyLine( "not registered" );
			}
		}
		print.line();

		if ( !hasRegistered ) {
			print.yellowLine( "No CFMLFiddle servers are registered in CommandBox. Nothing to forget." );
			return;
		}

		// Build menu of registered servers
		var registeredServers = [];
		for ( var s in servers ) {
			if ( s.registered ) arrayAppend( registeredServers, s );
		}

		print.boldCyanLine( "Registered servers:" );
		print.line();
		for ( var i = 1; i <= arrayLen( registeredServers ); i++ ) {
			var s = registeredServers[ i ];
			print.text( "  " );
			print.boldWhiteText( "#i#" );
			print.text( ") " );
			print.cyanText( s.name );
			if ( s.status == "running" ) {
				print.text( "  " );
				print.greenText( "(running - will be stopped first)" );
			}
			print.line();
		}
		print.line();
		print.boldWhiteText( "  A" );
		print.line( ") Forget ALL registered" );
		print.boldWhiteText( "  Q" );
		print.line( ") Cancel" );
		print.line();

		var choice = ask( "Enter number (1-#arrayLen( registeredServers )#), A for all, or Q to cancel: " );

		if ( uCase( choice ) == "Q" ) {
			print.line( "Cancelled." );
			return;
		}

		if ( uCase( choice ) == "A" ) {
			_forgetServers( registeredServers );
		} else {
			var idx = val( choice );
			if ( idx < 1 || idx > arrayLen( registeredServers ) ) {
				print.redLine( "Invalid selection." );
				return;
			}
			_forgetServers( [ registeredServers[ idx ] ] );
		}
	}

	/**
	 * Parse plain-text `server list` output to get name -> status map.
	 * Each server starts with "name (status)" on its own line.
	 */
	private struct function _getRegisteredServers() {
		var result = {};
		try {
			var output = command( "server list" )
				.run( returnOutput = true );
			// Strip ANSI color/escape codes (e.g. chr(27)[1m, chr(27)[32m)
			output = reReplace( output, chr( 27 ) & "\[[0-9;]*m", "", "all" );
			// Each server block starts with "serverName (status)"
			// e.g. "cfmlfiddle-cf2016 (running)"
			var lines = listToArray( output, chr( 10 ) );
			for ( var line in lines ) {
				line = trim( line );
				// Match lines like "someName (running)" or "someName (stopped)"
				var match = reFind( "^([^\s(]+)\s+\(([^)]+)\)", line, 1, true );
				if ( match.pos[ 1 ] > 0 && arrayLen( match.pos ) >= 3 ) {
					var sName = mid( line, match.pos[ 2 ], match.len[ 2 ] );
					var sStatus = mid( line, match.pos[ 3 ], match.len[ 3 ] );
					result[ sName ] = sStatus;
				}
			}
		} catch ( any e ) {
			print.redLine( "Error reading server list: #e.message#" );
		}
		return result;
	}

	/**
	 * Stop (if running) and forget the given servers.
	 */
	private function _forgetServers( required array servers ) {
		for ( var s in arguments.servers ) {
			if ( s.status == "running" ) {
				print.yellowText( "Stopping #s.name#... " );
				command( "server stop" )
					.params( s.name )
					.run();
				print.greenLine( "stopped" );
				// Wait for the server to fully release before forgetting
				sleep( 3000 );
			}

			print.yellowText( "Forgetting #s.name#... " );
			command( "server forget" )
				.params( s.name )
				.flags( "force" )
				.run();
			print.greenLine( "done" );
		}
		print.line();
		print.greenLine( "#arrayLen( arguments.servers )# server(s) forgotten." );
	}

}
