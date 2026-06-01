/**
 * CFMLFiddle Task Runner
 * Run with: box task run
 *
 * Lists available server configs and lets you choose which to start
 * as the primary host server.
 */
component {

	function run() {
		var configDir = resolvePath( "current-servers" );

		// Scan for server config files
		var configs = directoryList( configDir, false, "name", "server.*.json" );
		if ( !arrayLen( configs ) ) {
			print.redLine( "No server configs found in current-servers/" );
			return;
		}

		// Parse each config and build menu
		var servers = [];
		for ( var fileName in configs ) {
			var filePath = configDir & "/" & fileName;
			var config = deserializeJSON( fileRead( filePath, "utf-8" ) );
			arrayAppend( servers, {
				"fileName": fileName,
				"filePath": filePath,
				"name": config.name ?: fileName,
				"cfengine": config.app.cfengine ?: "unknown",
				"port": config.web.HTTP.port ?: 0
			} );
		}

		// Display menu
		print.line();
		print.boldCyanLine( "=== CFMLFiddle - Select Host Server ===" );
		print.line();
		for ( var i = 1; i <= arrayLen( servers ); i++ ) {
			var s = servers[ i ];
			print.text( "  " );
			print.boldWhiteText( "#i#" );
			print.text( ") " );
			print.cyanText( s.name );
			print.text( "  " );
			print.yellowText( s.cfengine );
			print.text( "  port " );
			print.whiteLine( s.port );
		}
		print.line();

		// Prompt for choice
		var choice = ask( "Enter number (1-#arrayLen( servers )#): " );
		var idx = val( choice );
		if ( idx < 1 || idx > arrayLen( servers ) ) {
			print.redLine( "Invalid selection." );
			return;
		}

		var selected = servers[ idx ];
		print.line();
		print.greenLine( "Starting #selected.name# (#selected.cfengine#) on port #selected.port#..." );
		print.line();

		// Start the server
		command( "server start" )
			.params( serverConfigFile = selected.filePath )
			.run();

		// Open the homepage in the default browser
		var homeURL = "http://localhost:#selected.port#/";
		print.greenLine( "Opening #homeURL#" );
		command( "browse" )
			.params( homeURL )
			.run();
	}

}
