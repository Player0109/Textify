# Model Workflow Fault Evidence

The release-only command combines production-path XCTest results, a real
loopback transfer exercise, and a deterministic property campaign without
using the public catalog endpoint or downloading production model artifacts.

Run it from a clean checkout:

```bash
script/release/run_model_fault_campaign.sh dist/release-evidence/model-faults
```

The command retains:

- `fault-campaign.json`: the fixed-seed 1,000-operation property model, a
  1,000-operation production `ModelInstallQueueStore` relaunch soak, localhost
  production-transport results, security probes, privacy assertions, and
  invariant results.
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
as production fault injection. Production behavior is evidenced by the
retained focused test log, while the separate durable queue soak repeatedly
persists, reconstructs, relaunch-recovers, cancels, and removes retained
partial data through the shipping stores and removers.

This evidence does not yet satisfy the full issue #24 production boundary ×
fault requirement. Installer, activation, revocation/restoration, deletion,
and reconciliation still need shared production failpoints plus forced
process-crash/relaunch coverage. Keep issue #24 open until that matrix exists;
do not use the property-model matrix as a substitute.

This command is intentionally outside ordinary CI. Keep its JSON, log, seed,
and checksums with the release-candidate evidence bundle.
