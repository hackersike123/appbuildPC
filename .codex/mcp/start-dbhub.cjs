const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const projectRoot = path.resolve(__dirname, "../..");
const backendRoot = path.join(projectRoot, "backend");
const envPath = path.join(backendRoot, ".env");
const dotenvPath = path.join(backendRoot, "node_modules", "dotenv");

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

const [major, minor] = process.versions.node.split(".").map(Number);
if (major < 22 || (major === 22 && minor < 5)) {
  fail("The PCBUILD SQL MCP requires Node.js 22.5 or newer for DBHub.");
}

if (!fs.existsSync(envPath)) {
  fail("Create backend/.env from backend/.env.example before starting the SQL MCP.");
}

let dotenv;
try {
  dotenv = require(dotenvPath);
} catch {
  fail("Install backend dependencies with npm install before starting the SQL MCP.");
}

const values = dotenv.parse(fs.readFileSync(envPath));
const required = [
  "MSSQL_SERVER",
  "MSSQL_PORT",
  "MSSQL_DATABASE",
  "MSSQL_USER",
  "MSSQL_PASSWORD",
];
const missing = required.filter((key) => !values[key]);
if (missing.length > 0) {
  fail(`Set ${missing.join(", ")} in backend/.env before starting the SQL MCP.`);
}

const port = Number(values.MSSQL_PORT);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  fail("MSSQL_PORT in backend/.env must be a valid TCP port.");
}

const server = values.MSSQL_SERVER.includes(":") && !values.MSSQL_SERVER.startsWith("[")
  ? `[${values.MSSQL_SERVER}]`
  : values.MSSQL_SERVER;
const encrypt = String(values.MSSQL_ENCRYPT ?? "false").toLowerCase() === "true";
const trustCertificate =
  String(values.MSSQL_TRUST_SERVER_CERTIFICATE ?? "false").toLowerCase() === "true";
const sslMode = !encrypt ? "disable" : trustCertificate ? "require" : "verify-full";
const dsn =
  `sqlserver://${encodeURIComponent(values.MSSQL_USER)}:${encodeURIComponent(values.MSSQL_PASSWORD)}` +
  `@${server}:${port}/${encodeURIComponent(values.MSSQL_DATABASE)}?sslmode=${sslMode}`;

const executable = process.platform === "win32" ? "npx.cmd" : "npx";
const args = [
  "--yes",
  "@bytebase/dbhub@1.5.0",
  "--config",
  path.join(projectRoot, "dbhub.toml"),
];

const child = spawn(executable, args, {
  cwd: projectRoot,
  env: { ...process.env, PCBUILD_MSSQL_DSN: dsn },
  stdio: "inherit",
  windowsHide: true,
  shell: process.platform === "win32",
});

child.on("error", () => {
  fail("Unable to start DBHub. Confirm Node.js/npm are installed and available on PATH.");
});
child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});

