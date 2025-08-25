#!/usr/bin/env bash
set -euo pipefail

# 清空历史上传日志
: > up_m4b.log


# 只上传当前目录及其子目录中的 .m4b 文件
rclone copy . E5OneDrive:/vps_to \
  --include '*.m4b' \
  --max-depth 1 \
  --cache-chunk-size 500M >> up_m4b.log
