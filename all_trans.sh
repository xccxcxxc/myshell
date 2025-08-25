#!/usr/bin/env bash
set -euo pipefail

./get_epub.sh > get_epub.log 2>&1
./trans_epub.sh > trans_epub.log 2>&1
./up_epub.sh > up_epub.log 2>&1

