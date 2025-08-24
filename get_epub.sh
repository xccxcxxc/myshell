#!/usr/bin/env bash

# 清空旧日志，创建新日志文件
> r.log
> get_fail.log

rclone copy --ignore-existing E5OneDrive:/to_vps/ .

