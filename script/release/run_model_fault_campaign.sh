#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <evidence-directory>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="$1"
mkdir -p "$EVIDENCE_DIR"
EVIDENCE_DIR="$(cd "$EVIDENCE_DIR" && pwd)"
TEST_LOG="$EVIDENCE_DIR/fault-tests.log"
TEST_RESULTS="$EVIDENCE_DIR/fault-tests.tsv"
CAMPAIGN_REPORT="$EVIDENCE_DIR/fault-campaign.json"
CHECKSUMS="$EVIDENCE_DIR/checksums.txt"

: >"$TEST_LOG"

TEST_FILTER='TextifyReleaseVerificationTests|TextifyModelsTests.DownloadTests|TextifyModelsTests.ManifestV3Tests|TextifyModelsTests.ModelInstallerTests|TextifyModelsTests.ModelInstallQueueTests|TextifyModelsTests.ModelStorageAdmissionTests|TextifyModelsTests.ModelStorageInventoryTests|TextifyModelsTests.ModelRevocationTests|TextifyModelsTests.InstalledModelManagerTests|TextifyAppTests.ModelInstallCoordinatorQueueTests|TextifyDiagnosticsTests.DiagnosticsTests'
(
  cd "$ROOT_DIR"
  swift test --filter "$TEST_FILTER"
) 2>&1 | tee "$TEST_LOG"

awk -F"'" '/^Test Case .* passed/ {
  print $2 "\tpassed"
}' "$TEST_LOG" >"$TEST_RESULTS"
test -s "$TEST_RESULTS"

(
  cd "$ROOT_DIR"
  swift run TextifyModelFaultVerifier "$CAMPAIGN_REPORT"
)

(
  cd "$EVIDENCE_DIR"
  shasum -a 256 \
    fault-campaign.json \
    fault-tests.log \
    fault-tests.tsv >"$CHECKSUMS"
)

echo "Model fault evidence written to $EVIDENCE_DIR"
