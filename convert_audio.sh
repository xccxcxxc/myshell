#!/usr/bin/env bash
set -euo pipefail

# 激活虚拟环境（存在才激活）
if [ -f myvenv/bin/activate ]; then
  # shellcheck disable=SC1091
  source myvenv/bin/activate
fi

for file in *.epub; do
    [ -e "$file" ] || continue        # 没有匹配文件则跳过

    echo "正在处理: $file"

    output_dir="${file%.epub}"        # 去掉扩展名
    printf 'y\n' | python3 main.py "$file" "$output_dir" \
        --tts edge \
        --language zh-CN \
        --worker_count 4 \
        --voice_name zh-CN-XiaoxiaoNeural \
        --chapter_start 1 \
        --chapter_end -1

    echo "完成: $file"
done


