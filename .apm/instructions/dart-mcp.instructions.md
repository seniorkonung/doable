### Dart and Flutter MCP

Before the first Dart MCP call in a session, call `roots` (`command: add`) with the workspace `file://` URI.

Prefer Dart MCP over text search for Dart code:

- declarations: `lsp` `resolveWorkspaceSymbol` with the exact full name (matching is fuzzy and includes dependencies and the SDK);
- types, docs, call parameters: `lsp` `hover` or `signatureHelp` (positions are zero-based);
- pub dependency sources: `read_package_uris`, `rip_grep_packages`;
- diagnostics for specific files: `analyze_files`.

Use text search for usages and implementations; `lsp` cannot find them.

After changing Dart code, look for a running app via `dtd`. If one exists, hot reload or restart it and check `get_runtime_errors`; otherwise run the repository's CLI checks.
