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
CAMPAIGN_REPORT="$EVIDENCE_DIR/fault-campaign.json"
CHECKSUMS="$EVIDENCE_DIR/checksums.txt"

: >"$TEST_LOG"

run_test() {
  local filter="$1"
  (
    cd "$ROOT_DIR"
    swift test --filter "$filter"
  ) 2>&1 | tee -a "$TEST_LOG"
}

run_test "TextifyReleaseVerificationTests"
run_test "TextifyModelsTests.ModelInstallerTests"
run_test "TextifyModelsTests.ModelInstallQueueTests"
run_test "TextifyModelsTests.ModelStorageAdmissionTests"
run_test "TextifyModelsTests.ModelStorageInventoryTests"
run_test "TextifyModelsTests.ModelRevocationTests"
run_test "TextifyModelsTests.InstalledModelManagerTests"
run_test "TextifyAppTests.ModelInstallCoordinatorQueueTests"
run_test "TextifyDiagnosticsTests.DiagnosticsTests"

(
  cd "$ROOT_DIR"
  swift run TextifyModelFaultVerifier "$CAMPAIGN_REPORT"
)

(
  cd "$EVIDENCE_DIR"
  shasum -a 256 fault-campaign.json fault-tests.log >"$CHECKSUMS"
)

echo "Model fault evidence written to $EVIDENCE_DIR"
