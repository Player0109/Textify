# Historical model benchmark evidence

This directory preserves the corpus definitions, rating policies, suite indexes,
and measured results used as provenance for the signed model catalog. These are
historical native-runtime measurements, not performance claims for the current
Electron desktop app.

- `Corpus/` contains the recorded suite inputs, policies, and provenance metadata.
- `results/` contains committed measurements.
- Existing local `.benchmark-results/` and `.benchmark-data/` directories may
  contain additional evidence and are retained without being committed.

The standalone Swift app, benchmark executable, and its runner scripts have been
retired. Their historical implementations remain available in Git history at the
source revisions recorded with the evidence. This directory has no current build
or run command. Do not rewrite preserved evidence or signed catalog metadata as
part of application cleanup.

For current desktop development and verification, see
[the Electron guide](../../electron/README.md).
