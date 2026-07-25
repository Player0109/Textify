# Release-Candidate Evidence Bundle

Textify signs off a release candidate only from a validated evidence
declaration and the exact attachment bytes it names. Start from
`docs/release/release-evidence-template.json`; the template is intentionally
incomplete and must fail validation until genuine evidence replaces every
placeholder. Use `docs/release/release-evidence-record-template.json` for each
categorized evidence record.

Each attachment uses a contained relative path, a lowercase SHA-256, a manual
or automated kind, and at most one closed evidence category. Categorized
attachments must decode as a structured `ReleaseEvidenceRecord` binding that
category, the release commit, recorder, time, notes, and one or more separately
hashed subject attachments. The validator rejects generic label-only files,
missing or changed files, symlinks, hard links, and path escapes. Every build
artifact also names its attachment ID, so its declared digest must match
retained bytes.

The declaration must cover:

- schema, property, transition, malformed-input, migration, and fault tests;
- hierarchy, selection, comparison, actions, scopes, query, pinned reveal,
  inspector, Downloads, onboarding, trust states, revocation, and deletion;
- manual VoiceOver, Full Keyboard Access, text scaling, Reduce Motion,
  Increase Contrast, and Reduce Transparency results;
- performance with at least 30 warm iterations and three cold launches on a
  real oldest-supported M1-class device, plus a later supported real device;
- every catalog Compute Route on a real device;
- security review, publication report, soak log, diagnostics review, packaging
  validation, and rollback rehearsal;
- the release commit, build hashes, catalog/revocation revisions and signers,
  unchanged parent-specification hash, defect disposition, independent
  trust/migration/revocation/destructive-filesystem reviews, and two distinct
  human approvals.

Performance records carry the complete warm and cold measurement arrays rather
than self-declared counts. They also bind the real-device flag and
oldest-supported-M1 classification to the recorded device identity; the
oldest-supported entry must name an Apple M1-class device. Compute Routes are
derived from the attached v3 manifest and must match route records from real
devices. Device classes use Apple M-series names such as `Apple M1` or
`Apple M4 Max`, and macOS versions use numeric components beginning at 14.
Catalog and revocation identity is decoded from the attached
publication evidence and bound to the exact manifest and release executable
hash. Review and approval records must match their declared reviewer, scope,
approver, and timestamp.

Critical or High defects always block. Medium defects in trust, migration,
activation, deletion, queue durability, recovery, privacy, or primary
accessibility always block. Any other Medium defect needs a retained waiver
and non-empty safe workaround. Low defects remain listed.

After placing all attachments below one evidence root, run:

```bash
script/release/assemble_release_evidence.sh \
  dist/release-evidence/declaration.json \
  dist/release-evidence \
  dist/release-evidence/release-evidence-bundle.json
```

The command binds the declaration to the current Git commit and current
`docs/SPEC.md`, hashes every attachment, and writes the validated bundle
atomically. A successful bundle means the declared evidence is internally
complete; it does not replace notarization, publication, or the recorded human
approvals.
