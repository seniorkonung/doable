### Dart and Flutter MCP

When Dart and Flutter MCP is available, inspect the tools exposed by the client.
Before the first `lsp` or other root-dependent call, use an exposed fallback
`roots` tool (`command: add`) with the workspace's absolute `file://` URI;
clients that supply MCP Roots automatically need no fallback.

Use Dart MCP first for targeted code investigation:

- use `lsp` for workspace-symbol search, hover information, and signature
  help;
- use `read_package_uris` and `rip_grep_packages` when investigating package
  dependencies;
- use `analyze_files` for targeted Dart analysis.

Use DTD, hot reload or restart, and runtime-error tools when validating a
running Flutter application. Retain the repository's CLI commands for build,
test, generation, and any verification without an applicable MCP tool.

After changing Dart or Flutter code, check DTD for an active application. If
one is available, connect, apply the appropriate hot reload or restart, and
inspect runtime errors. If no application is active, record that fact and run
the repository's normal CLI verification instead.
