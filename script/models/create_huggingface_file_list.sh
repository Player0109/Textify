#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 owner/repository 40-hex-revision local-model-directory filename-prefix" >&2
  exit 64
fi

repository="$1"
revision="$2"
model_directory="${3%/}"
filename_prefix="$4"

if [[ ! "$repository" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "Repository must be an owner/name Hugging Face identifier." >&2
  exit 65
fi
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Revision must be an immutable lowercase 40-character Git commit." >&2
  exit 65
fi
if [[ ! -d "$model_directory" ]]; then
  echo "Model directory does not exist: $model_directory" >&2
  exit 66
fi

file_list="$(mktemp)"
trap 'rm -f "$file_list"' EXIT

find "$model_directory" -type f ! -path "$model_directory/.cache/*" -print \
  | LC_ALL=C sort > "$file_list"

if [[ ! -s "$file_list" ]]; then
  echo "Model directory contains no artifact files: $model_directory" >&2
  exit 66
fi

while IFS= read -r file_path; do
  relative_path="${file_path#"$model_directory"/}"
  if [[ ! "$relative_path" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "Artifact path contains unsupported URL characters: $relative_path" >&2
    exit 65
  fi

  filename="$filename_prefix-${relative_path//\//-}"
  size_bytes="$(stat -f '%z' "$file_path")"
  sha256="$(shasum -a 256 "$file_path" | awk '{print $1}')"
  url="https://huggingface.co/$repository/resolve/$revision/$relative_path"

  jq -n \
    --arg filename "$filename" \
    --arg relativePath "$relative_path" \
    --arg url "$url" \
    --arg sha256 "$sha256" \
    --argjson sizeBytes "$size_bytes" \
    '{filename: $filename, relativePath: $relativePath, url: $url, sha256: $sha256, sizeBytes: $sizeBytes}'
done < "$file_list" | jq -s '{sizeBytes: (map(.sizeBytes) | add), files: .}'
