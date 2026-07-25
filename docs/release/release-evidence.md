# Release-Candidate Evidence Bundle

Textify signs off a release candidate only from a validated evidence
declaration and the exact attachment bytes it names. Start from
`docs/release/release-evidence-template.json`; the template is intentionally
incomplete and must fail validation until genuine evidence replaces every
placeholder.

Each attachment uses a contained relative path, a lowercase SHA-256, a manual
or automated kind, and one or more closed evidence categories. The validator
rejects missing, changed, symlinked, hard-linked, or escaping attachment paths.
Every build artifact also names its attachment ID, so its declared digest must
match retained bytes.

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
