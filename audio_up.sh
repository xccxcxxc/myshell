#!/usr/bin/env bash
set -euo pipefail

# 进入脚本所在目录，确保相对路径正确
cd "$(dirname "$0")"

# 激活虚拟环境（存在才激活）
if [ -f myvenv/bin/activate ]; then
  # shellcheck disable=SC1091
  source myvenv/bin/activate
fi

# 清空旧日志，创建新日志文件
: > audio_up.log

# 遍历当前目录下所有 .epub 文件
for file in *.epub; do
  [ -e "$file" ] || continue

  echo "[$(date '+%F %T')] 正在处理: $file" >> audio_up.log


  # 设置声音选择和倍速
  audiblez "$file" -v zf_xiaoyi -s 1 >> audio_up.log 2>&1

  echo "[$(date '+%F %T')] 完成: $file" >> audio_up.log
  echo >> audio_up.log
done

# 转换及上传
./convert_m4b.sh
./up_m4b.sh

