#!/usr/bin/env bash
set -euo pipefail

cd /home/zg/bilingual_book_maker

# 只上传当前目录及其子目录中的 .epub 文件
rclone copy . E5OneDrive:/vps_to \
  --include '*.epub' \
  --max-depth 1 \
  --cache-chunk-size 500M 
