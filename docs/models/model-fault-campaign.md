# Model Workflow Fault Campaign

The release-only model fault campaign proves recovery behavior without using
the public catalog endpoint or downloading production model artifacts.

Run it from a clean checkout:

```bash
script/release/run_model_fault_campaign.sh dist/release-evidence/model-faults
```

The command retains:

- `fault-campaign.json`: the fixed-seed 1,000-operation model, durable-boundary
  matrix, localhost transfer results, security probes, privacy assertions, and
  invariant results.
- `fault-tests.log`: focused production-path results for the installer, queue,
  storage admission and inventory, revocation/restoration, deletion,
  coordinator recovery, and diagnostics redaction.
- `checksums.txt`: SHA-256 hashes binding both artifacts.

The localhost service covers redirects, valid and invalid range responses,
validator changes, disconnect/retry, cancellation, relaunch recovery, offline
queue durability, and catalog-freshness expiry. It binds only to loopback and
serves generated fixture bytes.

The campaign fails if any active identity lacks an Installation Receipt, a
revoked identity remains active, owned byte accounting becomes negative, or
managed bytes cannot be attributed. Process-termination injection covers every
declared durable installation, queue, activation, restoration, and deletion
boundary; the remaining specified faults are also injected and recovered.

This command is intentionally outside ordinary CI. Keep its JSON, log, seed,
and checksums with the release-candidate evidence bundle.
