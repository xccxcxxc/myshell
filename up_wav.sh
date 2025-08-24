#!/usr/bin/env bash
set -euo pipefail

# 清空历史上传日志
: > up_wav.log


# 只上传当前目录及其子目录中的 .wav 文件
rclone copy . E5OneDrive:/vps_to \
  --include '*.wav' \
  --max-depth 1 \
  --cache-chunk-size 500M >> up_wav.log
