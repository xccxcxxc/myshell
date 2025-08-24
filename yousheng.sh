#!/bin/bash

# 设置声音角色变量（可修改）
VOICE="zf_xiaoxiao"

# 清空旧日志，创建新日志文件
> r.log
> upload_fail.log

rclone copy --ignore-existing E5OneDrive:/to_vps/ .

# 遍历当前目录下所有 .epub 文件
for file in *.epub; do
  # 如果没有匹配文件，则跳过
  [ -e "$file" ] || continue

  echo "正在处理: $file" >> r.log
  audiblez "$file" -v "$VOICE" >> r.log 2>&1
  echo "完成: $file" >> r.log
  echo >> r.log
  
  # 可选：sleep 1  # 如果担心资源争抢，可添加间隔

done

# 遍历当前目录下所有 .wav 文件
for file in *.wav; do
  # 如果没有匹配文件，则跳过
  [ -e "$file" ] || continue

  echo "正在上传: $file" >> r.log

  success=false
  for attempt in {1..3}; do
    echo "尝试第 $attempt 次上传..." >> r.log
    if rclone copy --ignore-existing "$file" E5OneDrive:/vps_to/ >> r.log 2>&1; then
      echo "上传成功: $file" >> r.log
      success=true
      break
    else
      echo "第 $attempt 次上传失败" >> r.log
      sleep 2  # 可选：失败后延迟重试
    fi
  done

  if [ "$success" = false ]; then
    echo "上传失败（已重试3次，放弃）: $file" >> r.log
    echo "$file" >> upload_fail.log
  fi
  echo >> r.log

done

