#!/usr/bin/env bash
set -euo pipefail

for f in *.wav; do
  ffmpeg -i "$f" -c:a aac -b:a 64k "${f%.wav}.m4b"
done

