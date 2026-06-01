# JavaLibs/

Shared Java libraries (JARs) loaded by all CFML engine instances via the `libDirs` setting in each server config.

Place `.jar` files here that should be available to all engines. The path to this directory must be absolute in the server configs since CFML engines resolve it from their own working directory, not from the config file location.

Do not delete this directory unless you have no shared Java libraries to load.
