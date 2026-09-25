# Bundled catalog releases and recovery

This guide covers the signed catalogs used by the Electron desktop app. Use the
[desktop release procedure](../../electron/RELEASING.md) for application
packaging and distribution. The retired Swift application's bundle-publication
and rollback-bridge tools are not part of the current release flow.

## Inputs and trust

Retain each exact input with its detached signature:

- `models/manifest.json` and `models/manifest.json.sig`;
- `models/revocations.json` and `models/revocations.json.sig`;
- `electron/models/manifest.json` and its signature for desktop-specific
  supplementary artifacts.

Catalog and revocation signatures use separate domains:
`io.github.Player0109.Textify.model-manifest` and
`io.github.Player0109.Textify.model-revocations`. These protocol identifiers
remain unchanged. Trusted public keys are embedded in the desktop verifier and
retained catalog tools. A remotely supplied key is never a trust anchor. Keep
private keys outside the repository and CI.

Do not reformat signed JSON, prune unused catalog entries, or replace signatures
as part of application cleanup. The desktop app exposes only its implemented
subset; retaining other exact artifacts preserves signed provenance.

## Review a catalog change

1. Review exact model source revisions, files, sizes, SHA-256 values, licenses,
   language capabilities, and runtime compatibility. A valid catalog record
   does not add a new desktop runtime.
2. Keep `generatedAt` revisions monotonic. A correction or security withdrawal
   requires a higher revision. Do not change content under an existing revision.
3. Sign and verify the candidate pairs using the retained
   [signing and verification tools](model-manifest-signing.md). Keep previous
   signed inputs and their hashes with release evidence.
4. Run the desktop checks and verify the packaged resources contain the exact
   reviewed pairs. Exercise the affected download/import, revocation, and
   restoration behavior with isolated data.
5. Publish the catalog only as part of a verified desktop app release. There is
   no runtime catalog feed, and no separate catalog endpoint updates installed
   applications.

The retained Swift command-line verifiers check catalog signatures and policy;
they do not validate an Electron installer or replace its packaging checks.
Historical benchmark results may establish provenance but are not Electron
accuracy, performance, or platform-support claims.

## Recovery boundaries

Previously accepted security revocations stay enforced locally. A restoration
requires explicit artifact verification and must not silently reactivate a
selection. Never rewrite the trusted signed inputs or lower a revision to bypass
a revocation.

Preserve installed model bytes, preferences, trust records, and the current
application identity during updates. There is no supported migration back to
the retired Swift application. Investigate a release regression against the
current desktop storage and trust rules before distributing a recovery build.
