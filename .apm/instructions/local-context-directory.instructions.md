### Local context directory

The entire `.context/` directory is local, ignored, and unstable across machines.

Agents may read `.context/` files only as user-provided temporary input for the current task. Do not treat any `.context/` path as a stable project source, do not reference `.context/` paths in committed planning/docs/specs, and do not assume those files exist for other users or future sessions.
