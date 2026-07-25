# Catalog Publication And V3 Rollback

This is the release contract for publishing a model catalog after manifest v3
state has shipped. It supplements `docs/RELEASING.md`; it does not authorize an
unsigned catalog, a lower revision, or an arbitrary application downgrade.

## Signing Identities

Catalog and revocation inputs have separate signature domains and separately
recorded identities:

- Catalog: `io.github.Player0109.Textify.model-manifest`
- Revocations: `io.github.Player0109.Textify.model-revocations`

Each detached envelope must name an exact `keyId` from the bridge build's
embedded allowlist. The two domains may currently use entries backed by the same
maintainer key, but publication still records and validates both key IDs. A key
rotation must first ship in a trusted app build; a remotely supplied key is
never accepted. The publication verifier imports the same
`ProductionModelCatalogTrust` table as the application and has no environment
override for keys or key IDs. Private keys remain outside the repository and
CI.

## Revision Rules

`generatedAt` is the signed revision for both inputs.

- A candidate older than retained publication evidence is rejected.
- Repeating one revision is idempotent only when the exact signed content hash
  is unchanged.
- A catalog correction uses a higher catalog revision.
- A security withdrawal uses a higher revocation revision. Previously accepted
  records remain sticky even if a later body omits them.
- A restoration uses a higher revocation revision and the exact restoration
  rules in `docs/SPEC.md`; it does not reactivate an artifact.
- Never publish a lower revision as rollback or recovery.

Keep each successful evidence JSON with the release records. It binds catalog
revision/hash/signer, revocation revision/hash/signer, exact app build identity,
artifact count, endpoint, and verification time.

## Prepublication Gate

Build and sign the exact candidate application first. The gate requires its
code signature to pass strict verification, requires the production bundle
identifier, and reads its short version, build version, and executable SHA-256
rather than accepting an operator-supplied build label.

```bash
script/models/prepublish_model_catalog.sh \
  candidate/manifest.json \
  candidate/manifest.json.sig \
  candidate/revocations.json \
  candidate/revocations.json.sig \
  build/release/Textify.app \
  build/release/catalog-publication-evidence.json \
  previous/catalog-publication-evidence.json
```

Normal publication requires the immediately prior retained evidence, so
anti-rollback and sticky-revocation checks cannot be skipped accidentally. For
the one-time first v3 publication only, replace the final previous-evidence
argument with an explicit leading `--bootstrap`; the resulting evidence marks
that it establishes the authority baseline and must be retained permanently.

This gate reuses the application verifiers and then requires manifest v3. It
validates every production Exact Artifact's approved immutable URL, lowercase
typed SHA-256, exact leaf and aggregate sizes, bounded peak installation space,
nonempty HTTPS-backed license metadata, pinned provenance, supported Runtime
and Compute Route, and one signed presentation owner.

Before making the endpoint live, run the same check against its staging URL:

```bash
script/models/smoke_model_catalog_endpoint.sh \
  'https://staging.example.invalid/Textify/models' \
  build/release/Textify.app \
  build/release/catalog-endpoint-evidence.json \
  previous/catalog-publication-evidence.json
```

The smoke fetches and verifies only the catalog, catalog signature, revocation
body, and revocation signature. It deliberately does not download model
artifacts and is not an ordinary CI dependency. Final artifact-byte smokes stay
in the credentialed release checklist.

## Additive Migration Contract

The v3 migration keeps existing application-support files and adds information
through decode-compatible fields:

- Installation Receipts keep their operational `ModelEntry`, storage identity,
  local file ownership, Curated history, import history, and restoration
  acknowledgments.
- Queue Attempts keep stable attempt identity, authorized Exact Artifact,
  typed digest targets, expected file layout, FIFO history, and retained-data
  attribution.
- Placements are derived from the retained trusted v3 graph and receipt
  history; catalog withdrawal does not turn Curated content into Custom or
  Legacy.
- Transcription and Voice Cleaning active Exact Artifact IDs stay distinct.
- The trusted catalog archive retains the highest accepted revision and exact
  signed bytes. The revocation archive retains exact signed snapshots and alias
  evidence.

Migration must not delete, rename, or reinterpret managed bytes merely because
a new app or catalog no longer presents them. Copy the complete Textify
Application Support directory before a rollback rehearsal and compare receipt,
queue, and attributed-byte inventories afterward.

## Designated Rollback Bridge

The designated bridge is the exact signed build identity recorded in
publication evidence and tested by
`ModelV3RollbackBridge.rehearsePersistedWithdrawal`. It loads the persisted v3
settings, receipt, Queue Attempt, trusted-catalog archive, and sticky-revocation
archive using the embedded production trust table. It strictly verifies the
bridge app's code signature and requires its derived identity to match the
publication evidence before recording state-file and owned-byte SHA-256
evidence. The rehearsal represents an unavailable/withdrawn remote catalog
while continuing to use retained signed authority. It must prove:

- every receipt and storage identity remains owned;
- every Queue Attempt remains attributable;
- active identities are not replaced or silently reactivated;
- matching revoked active content remains blocked;
- retained Curated placement is not reinterpreted; and
- no state or managed bytes are mutated by rehearsal.

Run the focused persisted-state rehearsal and retain its test log beside the
publication evidence. Its receipt, queue, and active-identity inputs are frozen
pre-bridge JSON fixtures rather than data encoded by the test under review:

```bash
swift test \
  --filter ModelCatalogPublicationTests.testRollbackBridgeRetainsOwnedStateAndBlocksRevokedActiveContent \
  | tee build/release/v3-rollback-rehearsal.log
```

If a shipped application must be withdrawn, redistribute only a notarized
designated bridge build whose exact build identity has this evidence. A build
from before manifest v3 is explicitly unsupported as recovery: it cannot
understand the authority or ownership contract and must not be presented to
users as a rollback path.
