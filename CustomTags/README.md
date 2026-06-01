# CustomTags/

Shared CFML custom tags available to all engine instances via `customTagPaths` (Adobe CF) and `customTagMappings` (Lucee) in each server config.

Place custom tag `.cfm`/`.cfc` files here. The path to this directory must be absolute in the server configs since CFML engines resolve it from their own working directory, not from the config file location.

Do not delete this directory unless you have no shared custom tags.
