#!/usr/bin/env bash
set -euo pipefail

./get_epub.sh > get_epub.log 2>&1
./convert_audio.sh > convert_audio.log 2>&1
./up_audio.sh > up_audio.log 2>&1
sudo mv output_audio/* /home/zg/docker/shelf/audiobooks/
