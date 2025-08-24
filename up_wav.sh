#!/bin/bash


# 遍历当前目录下所有 .wav 文件
for file in *.wav; do
  # 如果没有匹配文件，则跳过
  [ -e "$file" ] || continue

  echo "正在处理: $file" > r.log
  nohup rclone copy "$file" E5OneDrive:/to_vps/ >> r.log 2>&1 &
done
