---
name: pcbuild-workflow
description: Use when implementing, debugging, or documenting this PCBUILD repository; route work across Flutter, Node.js/SQL Server, and offline model training while preserving the runtime boundaries.
---

# PCBUILD project workflow

1. Read the root and nearest `AGENTS.md`, then inspect the current implementation and its README before choosing a layer to change.
2. Trace client behavior through Flutter REST calls into the Node API. Treat SQL Server as authoritative for catalog, prices, compatibility, builds, and accounts.
3. Keep LM Studio calls in the backend. Training adapters and checkpoints are offline artifacts and are not loaded by the app.
4. For database exploration, use the project's read-only DBHub MCP. Do not run a migration or schema script against the remote SQL Server unless the user explicitly requests it and identifies the target.
5. Keep secrets and personal data out of code, logs, MCP prompts, and documentation. Avoid modifying training outputs unless the task asks for training.
6. Use the existing Flutter/backend commands only when the user requests verification; do not launch training as a check.

For framework API lookups, use the `pcbuild-docs` skill when the Context7 plugin is available. The full architecture and command reference remains in the repository README.
