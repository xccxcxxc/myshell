#!/usr/bin/env bash
set -euo pipefail

./get_epub.sh > get_epub.log 2>&1
./convert_m4b.sh > convert_m4b.log 2>&1
./up_m4b.sh > up_m4b.log 2>&1

