#!/bin/bash
# onedrivectl: OneDrive + rclone 管理脚本（Debian 11/12）
# 用户：zg
# 目标：幂等安装(仅FUSE)、写/更systemd服务、自动挂载、状态查看、清理等

set -euo pipefail

USER_NAME="zg"
HOME_DIR="/home/${USER_NAME}"
MOUNT_DIR="${HOME_DIR}/OneDrive"
SERVICE_NAME="rclone-onedrive"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_DIR="${HOME_DIR}/.local/share/rclone/logs"
LOG_FILE="${LOG_DIR}/rclone-onedrive.log"
CACHE_DIR="${HOME_DIR}/.cache/rclone"

REMOTE_NAME="${REMOTE_NAME:-}"   # 可通过环境变量指定远程名
RCLONE_BIN="$(command -v rclone || true)"
FUSER3_BIN="$(command -v fusermount3 || true)"
FUSER2_BIN="$(command -v fusermount || true)"

die(){ echo "❌ $*" >&2; exit 1; }
msg(){ echo -e "$*"; }

need_rclone(){
  command -v rclone >/dev/null 2>&1 || die "未检测到 rclone，请先安装：sudo apt install -y rclone"
  RCLONE_BIN="$(command -v rclone)"
}

is_mounted(){
  if command -v findmnt >/dev/null 2>&1; then
    findmnt -rn -T "${MOUNT_DIR}" >/dev/null 2>&1
  else
    mount | grep -q " ${MOUNT_DIR} "
  fi
}

ensure_fuse(){
  # 若无 fusermount3，则尝试安装 fuse3
  if ! command -v fusermount3 >/dev/null 2>&1; then
    msg "=== 未发现 fusermount3，安装 fuse3 ==="
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends fuse3 || true
  fi

  # 兜底：仍没有 fusermount3，但有 fusermount 时做软链
  if ! command -v fusermount3 >/dev/null 2>&1; then
    if command -v fusermount >/dev/null 2>&1; then
      msg "=== 创建兼容软链：/usr/bin/fusermount3 -> $(command -v fusermount) ==="
      sudo ln -sf "$(command -v fusermount)" /usr/bin/fusermount3
    else
      die "未找到 fusermount/fusermount3，请手动安装：sudo apt-get install -y fuse3"
    fi
  fi

  # /dev/fuse 与 fuse 组
  sudo modprobe fuse 2>/dev/null || true
  getent group fuse >/dev/null 2>&1 || sudo groupadd fuse
  sudo usermod -aG fuse "${USER_NAME}" || true
}

ensure_allow_other(){
  msg "=== 检查 allow_other 设置 ==="
  if ! grep -qE '^\s*user_allow_other\s*$' /etc/fuse.conf 2>/dev/null; then
    echo "user_allow_other" | sudo tee -a /etc/fuse.conf >/dev/null
  fi
}

detect_remote(){
  if [ -n "${REMOTE_NAME}" ]; then
    return 0
  fi
  mapfile -t REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')
  for name in "${REMOTES[@]:-}"; do
    if rclone config show "$name" 2>/dev/null | grep -iqE '^\s*type\s*=\s*onedrive\s*$|type = onedrive'; then
      REMOTE_NAME="$name"
      break
    fi
  done
  [ -n "${REMOTE_NAME}" ] || die "未找到 type=onedrive 的远程。先执行：rclone config，或用 REMOTE_NAME=你的远程名 运行本命令。"
}

ensure_dirs(){
  msg "=== 创建挂载/缓存/日志目录（幂等） ==="
  sudo install -d -o "${USER_NAME}" -g "${USER_NAME}" -m 755 "${MOUNT_DIR}"
  sudo install -d -o "${USER_NAME}" -g "${USER_NAME}" -m 755 "${CACHE_DIR}"
  sudo install -d -o "${USER_NAME}" -g "${USER_NAME}" -m 755 "${LOG_DIR}"
}

write_service(){
  local FUSER_BIN
  FUSER_BIN="$(command -v fusermount3 || command -v fusermount || echo /bin/fusermount3)"
  local REMOTE_REF="${REMOTE_NAME%:}:"
  msg "=== 写入/更新 systemd 服务文件 ==="
  sudo tee "${SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=Mount OneDrive (rclone) for ${USER_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
# 确保拥有 fuse 组权限（无需重新登录）
SupplementaryGroups=fuse
# 确保 PATH 完整
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${RCLONE_BIN} mount ${REMOTE_REF} ${MOUNT_DIR} \\
  --vfs-cache-mode writes \\
  --vfs-cache-max-age 336h \\
  --vfs-cache-max-size 10G \\
  --cache-dir ${CACHE_DIR} \\
  --dir-cache-time 72h \\
  --poll-interval 15s \\
  --umask 022 \\
  --allow-other \\
  --log-level INFO \\
  --log-file ${LOG_FILE}
ExecStop=${FUSER_BIN} -u ${MOUNT_DIR}
Restart=on-failure
RestartSec=10
TimeoutStopSec=20
KillMode=control-group

[Install]
WantedBy=default.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable "${SERVICE_NAME}" >/dev/null
}

cmd_install(){
  need_rclone
  ensure_fuse
  ensure_allow_other
  detect_remote
  msg "✅ 使用远程：${REMOTE_NAME}"
  ensure_dirs
  write_service
  if is_mounted; then
    msg "✅ 已检测到已挂载 ${MOUNT_DIR}，跳过启动。"
  else
    msg "=== 未挂载，启动服务 ==="
    sudo systemctl restart "${SERVICE_NAME}" || sudo systemctl start "${SERVICE_NAME}"
    sleep 2
    if is_mounted; then
      msg "✅ OneDrive 已成功挂载到 ${MOUNT_DIR}"
    else
      msg "⚠️ 挂载失败，查看：systemctl status ${SERVICE_NAME} 以及 ${LOG_FILE}"
      sudo systemctl status "${SERVICE_NAME}" --no-pager || true
      sudo tail -n 100 "${LOG_FILE}" || true
      exit 1
    fi
  fi
}

cmd_status(){
  local mnt="未挂载"
  is_mounted && mnt="已挂载"
  echo "挂载状态：${mnt} -> ${MOUNT_DIR}"
  echo "服务状态："
  systemctl --no-pager --full status "${SERVICE_NAME}" || true
}

cmd_start(){ sudo systemctl start "${SERVICE_NAME}"; }
cmd_stop(){ sudo systemctl stop "${SERVICE_NAME}" || true; }
cmd_restart(){ sudo systemctl restart "${SERVICE_NAME}" || sudo systemctl start "${SERVICE_NAME}"; }
cmd_logs(){ sudo tail -n 100 "${LOG_FILE}" || echo "暂无日志 ${LOG_FILE}"; }
cmd_unmount(){
  if is_mounted; then
    local fb="$(command -v fusermount3 || command -v fusermount || echo)"
    [ -n "$fb" ] && "$fb" -u "${MOUNT_DIR}" || sudo umount -l "${MOUNT_DIR}" || true
  fi
}

cmd_reconnect(){
  need_rclone
  detect_remote
  "${RCLONE_BIN}" config reconnect "${REMOTE_NAME}:" || die "reconnect 失败"
  echo "✅ 远程 ${REMOTE_NAME} 已尝试重新授权"
}

cmd_doctor(){
  echo "=== rclone 版本 ==="
  command -v rclone && rclone version || echo "未找到 rclone"
  echo "=== fusermount 可用性 ==="
  command -v fusermount3 || echo "fusermount3 不存在"
  command -v fusermount || echo "fusermount 不存在"
  echo "=== /dev/fuse ==="
  ls -l /dev/fuse || true
  echo "=== fuse 组与用户 ==="
  getent group fuse || echo "无 fuse 组"
  id "${USER_NAME}" || true
  echo "=== rclone 远程列表 ==="
  rclone listremotes || true
  echo "=== 服务状态 ==="
  systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || echo "服务未启用"
  systemctl is-active "${SERVICE_NAME}" 2>/dev/null || echo "服务未运行"
  echo "=== 挂载状态 ==="
  if is_mounted; then echo "已挂载 ${MOUNT_DIR}"; else echo "未挂载"; fi
}

cmd_cleanup(){
  # 解析可选参数
  local PURGE_CACHE=0 PURGE_MOUNT_DIR=0 PURGE_MOUNT_DIR_IF_EMPTY=0 PURGE_LOGS=0 PURGE_FUSE_SOFTLINK=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --purge-cache) PURGE_CACHE=1 ;;
      --purge-mount-dir) PURGE_MOUNT_DIR=1 ;;
      --purge-mount-dir-if-empty) PURGE_MOUNT_DIR_IF_EMPTY=1 ;;
      --purge-logs) PURGE_LOGS=1 ;;
      --purge-fuse-softlink) PURGE_FUSE_SOFTLINK=1 ;;
      -h|--help)
        cat <<H
用法: $0 cleanup [--purge-cache] [--purge-mount-dir | --purge-mount-dir-if-empty] [--purge-logs] [--purge-fuse-softlink]
H
        exit 0;;
      *) die "未知参数: $1" ;;
    esac
    shift
  done

  msg "=== 停止服务并卸载挂载 ==="
  systemctl is-active --quiet "${SERVICE_NAME}" && sudo systemctl stop "${SERVICE_NAME}" || true
  if is_mounted; then
    local fb="$(command -v fusermount3 || command -v fusermount || echo)"
    if [ -n "$fb" ]; then "$fb" -u "${MOUNT_DIR}" || true; fi
    is_mounted && sudo umount -l "${MOUNT_DIR}" || true
  fi

  msg "=== 禁用并删除 systemd 服务 ==="
  if [ -f "${SERVICE_FILE}" ]; then
    sudo systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
    sudo rm -f "${SERVICE_FILE}"
    sudo systemctl daemon-reload
  fi

  msg "=== 清理日志（默认仅删除文件）==="
  [ -f "${LOG_FILE}" ] && rm -f "${LOG_FILE}" || true
  if [ "${PURGE_LOGS}" -eq 1 ] && [ -d "${LOG_DIR}" ]; then
    rm -rf "${LOG_DIR}" || true
  fi

  msg "=== 清理缓存（可选）==="
  if [ "${PURGE_CACHE}" -eq 1 ] && [ -d "${CACHE_DIR}" ]; then
    rm -rf "${CACHE_DIR}" || true
  fi

  msg "=== 处理挂载目录（默认保留）==="
  if [ "${PURGE_MOUNT_DIR}" -eq 1 ]; then
    rm -rf "${MOUNT_DIR}" || true
  elif [ "${PURGE_MOUNT_DIR_IF_EMPTY}" -eq 1 ]; then
    if [ -d "${MOUNT_DIR}" ] && [ -z "$(ls -A "${MOUNT_DIR}" 2>/dev/null || true)" ]; then
      rmdir "${MOUNT_DIR}" || true
    fi
  fi

  msg "=== 处理 fusermount3 软链（可选）==="
  if [ "${PURGE_FUSE_SOFTLINK}" -eq 1 ]; then
    if [ -L /usr/bin/fusermount3 ]; then
      local TARGET="$(readlink -f /usr/bin/fusermount3 || true)"
      local REAL_FUSER="$(command -v fusermount || true)"
      if [ -n "$REAL_FUSER" ] && [ "$TARGET" = "$REAL_FUSER" ]; then
        sudo rm -f /usr/bin/fusermount3
      fi
    fi
  fi

  msg "=== 清理完成 ==="
}

usage(){
  cat <<EOF
用法: $0 <command> [args]

命令：
  install        安装/修复 FUSE、写/更服务，并挂载（已挂载则跳过启动）
  status         显示挂载与服务状态
  start|stop|restart  控制 systemd 服务
  logs           显示最近100行日志
  unmount        卸载挂载点（不禁用服务）
  reconnect      rclone 远程重连授权（token 过期时使用）
  doctor         自检 rclone/fuse/remote/服务/挂载
  cleanup        清理服务与日志；可加参数删除缓存/挂载目录/软链
                 可选参数：--purge-cache --purge-mount-dir | --purge-mount-dir-if-empty --purge-logs --purge-fuse-softlink

示例：
  $0 install
  REMOTE_NAME=E5OneDrive $0 install
  $0 status
  $0 cleanup --purge-cache --purge-mount-dir --purge-fuse-softlink --purge-logs
EOF
}

main(){
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    install)   cmd_install "$@" ;;
    status)    cmd_status ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    logs)      cmd_logs ;;
    unmount)   cmd_unmount ;;
    reconnect) cmd_reconnect ;;
    doctor)    cmd_doctor ;;
    cleanup)   cmd_cleanup "$@" ;;
    ""|-h|--help) usage ;;
    *) die "未知命令：${cmd}. 运行 --help 查看用法。" ;;
  esac
}

main "$@"

