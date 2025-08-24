#!/usr/bin/env bash
#set -euo pipefail

# 进入脚本所在目录，确保相对路径正确
cd "$(dirname "$0")"

# 加载本地环境变量（不会提交到 Git）
if [ -f .env ]; then
  # set -a 让 .env 里的变量自动 export
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# 校验必须的环境变量是否存在
: "${OPENAI_API_KEY:?请在 .env 中设置 OPENAI_API_KEY=你的密钥}"
# 可选变量，提供默认值
: "${MODEL:=gpt4omini}"
: "${LANGUAGE:=zh-hans}"

# 激活虚拟环境（存在才激活）
if [ -f myvenv/bin/activate ]; then
  # shellcheck disable=SC1091
  source myvenv/bin/activate
fi

# 清空旧日志，创建新日志文件
: > trans_up.log
: > nohup.out


# 遍历当前目录下所有 .epub 文件
for file in *.epub; do
  [ -e "$file" ] || continue

  echo "[$(date '+%F %T')] 正在处理: $file" >> trans_up.log


 # 把上面的调用注释掉，改用下面这段（注意这样 key 会短暂出现在进程列表中）：
  python3 make_book.py \
  --book_name "$file" \
  --openai_key "$OPENAI_API_KEY" \
  --model "$MODEL" \
  --language "$LANGUAGE" \
  --use_context \
  --context_paragraph_limit 6  >> trans_up.log 2>&1

  echo "[$(date '+%F %T')] 完成: $file" >> trans_up.log
  echo >> trans_up.log
done

# 后续上传步骤
/home/zg/bilingual_book_maker/up_epub.sh

