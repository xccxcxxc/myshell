#!/usr/bin/env bash
set -euo pipefail

# 激活虚拟环境（存在才激活）
if [ -f myvenv/bin/activate ]; then
  # shellcheck disable=SC1091
  source myvenv/bin/activate
fi

# 遍历当前目录下所有 .epub 文件
for file in *.epub; do
  # 如果没有匹配文件，则跳过
  [ -e "$file" ] || continue

  echo "正在处理: $file" 
  audiblez "$file" -v zf_xiaoyi -s 0.8 
  echo "完成: $file" 

  # 可选：sleep 1  # 如果担心资源争抢，可添加间隔

done

for f in *.wav; do
  ffmpeg -i "$f" -c:a aac -b:a 64k "${f%.wav}.m4b"
done

