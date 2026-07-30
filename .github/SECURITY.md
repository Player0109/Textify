# Security Policy

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/Player0109/Textify/security/advisories/new)
to report a suspected vulnerability. Do not include exploit details, dictated
text, clipboard contents, credentials, or other sensitive data in a public
issue. A GitHub account is required to open a private report. If the private
report form is unavailable, do not fall back to a public issue.

Maintainers aim to acknowledge reports within about five business days. Textify
does not promise a fixed remediation timeline; severity, exploitability, and
release-safety requirements determine the response.

## Scope

Security reports may cover:

- Accessibility and keyboard-monitoring paths
- text insertion and clipboard restoration
- model downloads and manifest verification
- release download integrity
- signing, notarization, and release packaging
- vendored dependencies, including whisper.cpp

Documented spoken-punctuation command collisions and best-effort transient or
concealed clipboard marking are outside the vulnerability scope. Reports about
clipboard contents not being restored, unauthorized insertion, signature
verification bypasses, or exposure of dictated content remain in scope.
