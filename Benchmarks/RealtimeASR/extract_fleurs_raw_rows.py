#!/usr/bin/env python3
"""Extract the first audio files from an immutable raw FLEURS dev archive."""

import argparse
import csv
import hashlib
import io
import json
import tarfile
import urllib.error
import urllib.request
from pathlib import Path, PurePosixPath


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, url):
        return None


def verify_lfs_pointer(url: str, expected_sha256: str) -> None:
    request = urllib.request.Request(url, method="HEAD")
    opener = urllib.request.build_opener(NoRedirect())
    try:
        opener.open(request)
    except urllib.error.HTTPError as error:
        if error.code not in range(300, 400):
            raise
        linked_etag = error.headers.get("x-linked-etag", "").strip('"')
        if linked_etag != expected_sha256:
            raise RuntimeError("raw FLEURS archive SHA-256 metadata changed")
        return
    raise RuntimeError("expected the raw FLEURS LFS URL to redirect")


def download_tsv(url: str, expected_size: int, expected_sha256: str) -> bytes:
    with urllib.request.urlopen(url) as response:
        data = response.read()
    if len(data) != expected_size:
        raise RuntimeError("raw FLEURS TSV size changed")
    if hashlib.sha256(data).hexdigest() != expected_sha256:
        raise RuntimeError("raw FLEURS TSV SHA-256 changed")
    return data


def transcription_by_filename(tsv_data: bytes) -> dict[str, str]:
    rows = csv.reader(io.StringIO(tsv_data.decode("utf-8")), delimiter="\t")
    result = {}
    for row in rows:
        if len(row) < 4:
            raise RuntimeError("unexpected raw FLEURS TSV row")
        result[row[1]] = row[3]
    return result


def extract_rows(arguments: argparse.Namespace, references: dict[str, str]):
    rows = []
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(arguments.tar_url) as response:
        content_length = int(response.headers.get("Content-Length", "0"))
        if content_length != arguments.tar_size:
            raise RuntimeError("raw FLEURS archive size changed")
        with tarfile.open(fileobj=response, mode="r|gz") as archive:
            for member in archive:
                if not member.isfile() or not member.name.endswith(".wav"):
                    continue
                filename = PurePosixPath(member.name).name
                reference = references.get(filename)
                if reference is None:
                    raise RuntimeError(f"no TSV row for {filename}")
                source = archive.extractfile(member)
                if source is None:
                    raise RuntimeError(f"could not extract {filename}")
                audio_bytes = source.read()
                if not audio_bytes.startswith(b"RIFF"):
                    raise RuntimeError(f"unexpected WAV data for {filename}")
                index = len(rows)
                destination = arguments.output_directory / f"{index}.wav"
                destination.write_bytes(audio_bytes)
                rows.append(
                    {
                        "row_idx": index,
                        "row": {
                            "transcription": reference,
                            "source_filename": filename,
                            "audio": [
                                {
                                    "src": (
                                        "local://fleurs/--/"
                                        f"{arguments.revision}/--/{arguments.config}/"
                                        f"{arguments.split}/{index}/audio/audio.wav"
                                    ),
                                    "type": "audio/wav",
                                }
                            ],
                        },
                    }
                )
                if len(rows) == arguments.count:
                    break
    if len(rows) != arguments.count:
        raise RuntimeError(f"expected {arguments.count} rows, found {len(rows)}")
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tar-url", required=True)
    parser.add_argument("--tar-size", required=True, type=int)
    parser.add_argument("--tar-sha256", required=True)
    parser.add_argument("--tsv-url", required=True)
    parser.add_argument("--tsv-size", required=True, type=int)
    parser.add_argument("--tsv-sha256", required=True)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--rows-json", required=True, type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--split", required=True)
    parser.add_argument("--count", required=True, type=int)
    arguments = parser.parse_args()

    verify_lfs_pointer(arguments.tar_url, arguments.tar_sha256)
    references = transcription_by_filename(
        download_tsv(
            arguments.tsv_url,
            arguments.tsv_size,
            arguments.tsv_sha256,
        )
    )
    rows = extract_rows(arguments, references)
    arguments.rows_json.write_text(
        json.dumps(
            {
                "rows": rows,
                "num_rows_total": len(rows),
                "partial": False,
                "source_split": "dev",
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
