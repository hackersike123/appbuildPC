---
name: pcbuild-docs
description: Look up version-aware library and API documentation when changing Flutter/Dart, Node.js, SQL Server, or their dependencies in PCBUILD.
---

# PCBUILD library documentation

Use this workflow when implementation depends on a framework API, package behavior, or version-specific configuration.

1. Read the relevant dependency version from `pubspec.yaml`, `backend/package.json`, or `training/requirements.txt`.
2. Use Context7 `resolve-library-id` to identify the exact library, then `query-docs` for the specific API or behavior. Ask a focused question that includes the installed version when possible.
3. Prefer official Flutter, Dart, Node.js, Microsoft SQL Server, or package-owner documentation for security-sensitive behavior. Context7 indexes community-maintained content; corroborate claims that affect data safety or compatibility.
4. Apply the result to the existing PCBUILD architecture. Flutter accesses backend APIs only; SQL remains authoritative; training models remain offline unless the runtime architecture is deliberately changed.
5. Do not send source code, credentials, `.env` values, user data, or private prompts to documentation services. Send only library names, versions, and concise technical questions.

If Context7 is unavailable, use the library's official documentation and state any version uncertainty.
