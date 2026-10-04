#!/usr/bin/env python3
"""Pipe xcodebuild output through this script: echoes input and converts
error lines into GitHub Actions annotations so failures are publicly visible."""

import os
import re
import sys

MAX_ANNOTATIONS = 40
WORKSPACE = os.environ.get("GITHUB_WORKSPACE", "")
ERROR_PATTERN = re.compile(r"^(?P<path>[^:]+\.swift):(?P<line>\d+):(?P<col>\d+): (?P<kind>error|fatal error): (?P<msg>.*)$")
GENERIC_PATTERN = re.compile(r"(error:|fatal error:|xcodebuild: error)")


def escape(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main() -> int:
    seen = set()
    emitted = 0
    truncated = False

    for line in sys.stdin:
        sys.stdout.write(line)
        sys.stdout.flush()

        stripped = line.rstrip("\n")
        if stripped.lstrip().startswith("::"):
            continue
        if not GENERIC_PATTERN.search(stripped):
            continue

        key = stripped.strip()
        if key in seen:
            continue
        seen.add(key)

        if emitted >= MAX_ANNOTATIONS:
            if not truncated:
                truncated = True
                print("::error::additional errors truncated", flush=True)
            continue

        match = ERROR_PATTERN.match(stripped.strip())
        if match:
            path = match.group("path")
            if WORKSPACE and path.startswith(WORKSPACE):
                path = path[len(WORKSPACE):].lstrip("/")
            annotation = (
                f"::error file={escape(path)},line={match.group('line')},"
                f"col={match.group('col')}::{escape(match.group('msg'))}"
            )
        else:
            annotation = f"::error::{escape(key)}"
        print(annotation, flush=True)
        emitted += 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
