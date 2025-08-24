#!/bin/bash

# 清空旧日志，创建新日志文件
> tran_up.log

# 激活虚拟环境
source myvenv/bin/activate

# 遍历当前目录下所有 .epub 文件
for file in *.epub; do
  # 如果没有匹配文件，则跳过
  [ -e "$file" ] || continue

  echo "正在处理: $file" >> tran_up.log
  python3 make_book.py --book_name "$file" --openai_key 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  --model gpt4omini  --language zh-hans --use_context --context_paragraph_limit 6 --batch >> tran_up.log 2>&1 
  echo "完成: $file" >> tran_up.log
  echo >> tran_up.log
  
  # 可选：sleep 1  # 如果担心资源争抢，可添加间隔

done

/home/zg/bilingual_book_maker/up_epub.sh
