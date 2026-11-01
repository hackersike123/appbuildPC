let input = "";

process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  input += chunk;
});

process.stdin.on("end", () => {
  let event;
  try {
    event = JSON.parse(input);
  } catch {
    process.exit(0);
    return;
  }

  const command = event?.tool_input?.command;
  if (typeof command !== "string") {
    process.exit(0);
    return;
  }

  const legacyMigrations = [
    /\bmigrate-json-to-sql\.js\b/i,
    /\bmigrate_from_json\.js\b/i,
    /\bmigrate_to_tables\.js\b/i,
    /\bnpm\s+(?:run|exec)\s+migrate:json-to-sql\b/i,
  ];

  if (legacyMigrations.some((pattern) => pattern.test(command))) {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason:
            "This legacy migration does not match the current SQL runtime model. Review backend/README.md and choose a compatible, backed-up migration path before running it.",
        },
      }),
    );
    return;
  }

  if (/\bensure_schema\.js\b/i.test(command)) {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext:
            "ensure_schema.js prepares the configured SQL Server schema. Confirm the target database and explicit user request before running it.",
        },
      }),
    );
  }
});

