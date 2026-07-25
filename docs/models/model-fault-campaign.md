# Model Workflow Fault Evidence

The release-only command combines production-path XCTest results, a real
loopback transfer exercise, and a deterministic property campaign without
using the public catalog endpoint or downloading production model artifacts.
It also runs every declared production durability observer against every
required fault in isolated subprocesses, then launches a fresh process to
reload and audit the shipping stores.

Run it from a clean checkout:

```bash
script/release/run_model_fault_campaign.sh dist/release-evidence/model-faults
```

The command retains:

- `fault-campaign.json`: the fixed-seed 1,000-operation property model and
  declared transition/invariant hit counts, a
  1,000-operation production `ModelInstallQueueStore` relaunch soak, localhost
  production-transport results, the 13-boundary by 11-fault production
  subprocess matrix, a seeded 1,000-operation production lifecycle soak with
  scheduled crashes, security probes, privacy assertions, and invariant
  results.
- `fault-tests.log`: focused production-path results for the installer, queue,
  storage admission and inventory, revocation/restoration, deletion,
  coordinator recovery, and diagnostics redaction.
- `fault-tests.tsv`: the passed production XCTest case identifiers in
  machine-readable tab-separated form.
- `checksums.txt`: SHA-256 hashes binding all retained artifacts.

The localhost service drives `URLSessionDownloadTransport` through redirects,
valid and invalid range responses, validator changes, disconnect/retry,
cancellation, relaunch recovery, offline queue durability, and
catalog-freshness expiry. It binds only to loopback and serves generated
fixture bytes.

The property campaign fails if any active identity lacks an Installation
Receipt, a revoked identity remains active, owned byte accounting becomes
negative, or modeled managed bytes cannot be attributed. It is not represented
as production fault injection.

Production fault injection uses the shipping durability-observer seam and the
same resume-metadata, Installation Receipt, settings, catalog, compatibility,
revocation, and queue persistence implementations as the app at queue
authorization/start, resumable metadata, installation staging/receipt,
activation preparation/preference, revocation/restoration persistence,
restoration acknowledgment, deletion rename/bytes/receipt, and receipt
reconciliation. The shipping adapter is inert; only the release worker mutates
real managed payload, metadata, catalog, compatibility, or revocation state,
returns a specific filesystem error, or terminates a process. Marker-only
cells are rejected. Each of the 143 cells runs in an isolated first process
and a fresh recovery process. All 13 process-termination cells must exit with
the reserved forced-termination status.

The separate seed-24 production soak performs all 1,000 install, reinstall,
cancel, delete, and catalog-refresh operations. It persists progress after
every operation, schedules 20 forced process exits after deterministic
50-operation batches, and reloads and audits the shipping stores before the
next batch.

The verifier rejects any missing failpoint, wrong activation, lost receipt,
unrecoverable Queue Attempt, unconfirmed deletion, metadata/filesystem
disagreement, invariant violation, or unexplained managed byte. The release
script validates these conditions from the retained JSON before checksumming
the evidence.

Textify has no archive installation layout or extractor. The archive security
probe verifies that archive, zip, and tar layouts are rejected. It also drives
the shipping installation-expansion policy used by staged directory models
past its entry-count, expanded-size, and path-depth bounds; the same policy is
required before any future archive extractor can stage entries.

This command is intentionally outside ordinary CI. Keep its JSON, log, seed,
and checksums with the release-candidate evidence bundle.
