#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 BASELINE_RATING CANDIDATE_RATING OUTPUT_REPORT" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY="$SCRIPT_DIR/Corpus/english-catalog-rating-v1.regression-policy.json"
BASELINE="$1"
CANDIDATE="$2"
OUTPUT="$3"

for input in "$POLICY" "$BASELINE" "$CANDIDATE"; do
  if [[ ! -f "$input" ]]; then
    echo "Required rating input does not exist: $input" >&2
    exit 1
  fi
done

if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$PWD/$OUTPUT"
fi
mkdir -p "$(dirname "$OUTPUT")"

/usr/bin/jq -n \
  --slurpfile policy "$POLICY" \
  --slurpfile baseline "$BASELINE" \
  --slurpfile candidate "$CANDIDATE" '
  def relative_increase($before; $after):
    if $before <= 0 then
      if $after > $before then 1e9 else 0 end
    else
      (($after - $before) / $before)
    end;
  def issue($metric; $before; $after; $limit):
    {metric: $metric, baseline: $before, candidate: $after, limit: $limit};

  ($policy[0]) as $p
  | ($baseline[0]) as $b
  | ($candidate[0]) as $c
  | if ($p | keys | sort) != ([
      "maximumComponentWERAbsoluteIncrease",
      "maximumComponentWERRelativeIncrease",
      "maximumNoSpeechFalsePositiveRateIncrease",
      "maximumP95LatencyRelativeIncrease",
      "maximumP95RealTimeFactorRelativeIncrease",
      "qualityMaximumScoreDrop",
      "schemaVersion",
      "speedMaximumScoreDrop"
    ] | sort) or $p.schemaVersion != 1 then
      error("invalid regression policy")
    elif $b.modelID != $c.modelID
      or $b.policyID != $c.policyID
      or $b.suiteIndexSHA256 != $c.suiteIndexSHA256 then
      error("baseline and candidate are not comparable")
    else
      [
        if ($b.quality.score - $c.quality.score) > $p.qualityMaximumScoreDrop then
          issue("quality.score"; $b.quality.score; $c.quality.score; $p.qualityMaximumScoreDrop)
        else empty end,
        if $c.quality.level < $b.quality.level then
          issue("quality.level"; $b.quality.level; $c.quality.level; "must not decrease")
        else empty end,
        ($b.quality.components[] as $before
          | $c.quality.components[]
          | select(.id == $before.id) as $after
          | (.wordErrorRate - $before.wordErrorRate) as $absolute
          | relative_increase($before.wordErrorRate; $after.wordErrorRate) as $relative
          | if $absolute > $p.maximumComponentWERAbsoluteIncrease
              and $relative > $p.maximumComponentWERRelativeIncrease then
              issue(
                ("quality.wer." + $before.id);
                $before.wordErrorRate;
                $after.wordErrorRate;
                {
                  absolute: $p.maximumComponentWERAbsoluteIncrease,
                  relative: $p.maximumComponentWERRelativeIncrease
                }
              )
            else empty end),
        if ($c.quality.noSpeechFalsePositiveRate - $b.quality.noSpeechFalsePositiveRate)
            > $p.maximumNoSpeechFalsePositiveRateIncrease then
          issue(
            "quality.noSpeechFalsePositiveRate";
            $b.quality.noSpeechFalsePositiveRate;
            $c.quality.noSpeechFalsePositiveRate;
            $p.maximumNoSpeechFalsePositiveRateIncrease
          )
        else empty end,
        if $b.speed != null and $c.speed == null then
          issue("speed.stability"; "rated"; "unrated"; "must remain rated")
        elif $b.speed != null and $c.speed != null
          and $c.speed.level < $b.speed.level then
          issue("speed.level"; $b.speed.level; $c.speed.level; "must not decrease")
        elif $b.speed != null and $c.speed != null
          and ($b.speed.score - $c.speed.score) > $p.speedMaximumScoreDrop then
          issue("speed.score"; $b.speed.score; $c.speed.score; $p.speedMaximumScoreDrop)
        else empty end,
        if $b.speed != null and $c.speed != null
          and relative_increase(
            $b.speed.p95ReleaseToFinalMs;
            $c.speed.p95ReleaseToFinalMs
          ) > $p.maximumP95LatencyRelativeIncrease then
          issue(
            "speed.p95ReleaseToFinalMs";
            $b.speed.p95ReleaseToFinalMs;
            $c.speed.p95ReleaseToFinalMs;
            $p.maximumP95LatencyRelativeIncrease
          )
        else empty end,
        if $b.speed != null and $c.speed != null
          and relative_increase(
            $b.speed.p95RealTimeFactor;
            $c.speed.p95RealTimeFactor
          ) > $p.maximumP95RealTimeFactorRelativeIncrease then
          issue(
            "speed.p95RealTimeFactor";
            $b.speed.p95RealTimeFactor;
            $c.speed.p95RealTimeFactor;
            $p.maximumP95RealTimeFactorRelativeIncrease
          )
        else empty end
      ] as $issues
      | {
          schemaVersion: 1,
          modelID: $c.modelID,
          baselineArtifactFingerprint: $b.artifactFingerprint,
          candidateArtifactFingerprint: $c.artifactFingerprint,
          passed: ($issues | length == 0),
          issues: $issues
        }
    end
  ' > "$OUTPUT"

if [[ "$(/usr/bin/jq -r '.passed' "$OUTPUT")" != "true" ]]; then
  echo "Catalog rating regression detected; see $OUTPUT" >&2
  exit 1
fi

echo "$OUTPUT"
