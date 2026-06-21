# Security Policy

## Supported versions

watchman is pre-1.0. Only the latest tagged release receives fixes.

| Version | Supported |
| ------- | --------- |
| latest release | ✅ |
| older tags | ❌ |

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

- Preferred: GitHub's [private vulnerability reporting](https://github.com/carvalhosauro/watchman/security/advisories/new)
  (Security tab → "Report a vulnerability").
- Alternative: email **gustavo.carvalho@pigz.com.br** with the details and, if
  possible, steps to reproduce.

You can expect an acknowledgement within **5 business days**. Once the issue is
confirmed and a fix is available, a patched release is tagged and the advisory is
published with credit to the reporter (unless anonymity is requested).

## Scope

watchman is a local, read-only CLI: it reads a plaintext wallet file and makes
outbound HTTPS GETs to public price/news endpoints. It stores no credentials and
opens no network listeners. Reports about the wallet file, request handling, or
the release/update path are in scope.
