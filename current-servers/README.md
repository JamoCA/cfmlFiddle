# current-servers/

Server configuration templates for CFMLFiddle. Each `server.*.json` file defines a CommandBox server instance (engine type, port, JVM settings, etc.).

These configs are read by the application on startup to build the server registry. Do not delete this directory or its files unless you intend to reconfigure which engines are available.

To add a new engine, copy an existing config, change the name/port/cfengine, and Reinit.
