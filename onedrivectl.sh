#!/bin/bash
# onedrivectl.sh: OneDrive + rclone 管理脚本（Debian 11/12）
# 用户：zg（可通过 USER_NAME 覆盖）
# 说明：不安装 rclone；按需安装/修复 FUSE；严格但兼容地检测是否真的挂载

set -euo pipefail

USER_NAME="${USER_NAME:-zg}"
HOME_DIR="/home/${USER_NAME}"
MOUNT_DIR="${HOME_DIR}/OneDrive"
SERVICE_NAME="rclone-onedrive"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_DIR="${HOME_DIR}/.local/share/rclone/logs"
LOG_FILE="${LOG_DIR}/rclone-onedrive.log"
CACHE_DIR="${HOME_DIR}/.cache/rclone"

REMOTE_NAME="${REMOTE_NAME:-}"   # 可通过环境变量指定远程名，如：REMOTE_NAME=E5OneDrive ./onedrivectl.sh install

die(){ echo "❌ $*" >&2; exit 1; }
msg(){ echo -e "$*"; }

need_rclone(){
  command -v rclone >/dev/null 2>&1 || die "未检测到 rclone，请先安装：sudo apt install -y rclone"
}

# 更稳健的已挂载判断：
# 1) mountpoint -q 先看该目录是否是挂载点
# 2) /proc/mounts 精确匹配挂载点的行，检查 fstype 以 fuse 开头
# 3) 若能匹配到 SOURCE 含 <REMOTE_NAME>: 更佳；否则只要 fuse 类型也算已挂载（兼容某些发行版/版本）
is_mounted(){
  local remote="${REMOTE_NAME%:}:"
  mountpoint -q -- "${MOUNT_DIR}" || return 1
  local line fstype src
  line="$(awk -v m="${MOUNT_DIR}" '$2==m{print $0}' /proc/mounts | tail -n1)"
  [[ -n "$line" ]] || return 1
  fstype="$(awk -v m="${MOUNT_DIR}" '$2==m{print $3}' /proc/mounts | tail -n1)"
  src="$(awk -v m="${MOUNT_DIR}" '$2==m{print $1}' /proc/mounts | tail -n1)"
  [[ "$fstype" == fuse* ]] || return 1
  # 如果远程名已知，尽量要求 SOURCE 包含远程名；否则放宽（有些系统此处不是远程名）
  if [[ -n "${REMOTE_NAME:-}" ]]; then
    [[ "$src" == *"${remote}"* ]] || true
  fi
  return 0
}

ensure_fuse(){
  if ! command -v fusermount3 >/dev/null 2>&1; then
    msg "=== 未发现 fusermount3，安装 fuse3 ==="
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends fuse3 || true
  fi
  if ! command -v fusermount3 >/dev/null 2>&1; then
    if command -v fusermount >/dev/null 2>&1; then
      msg "=== 创建兼容软链：/usr/bin/fusermount3 -> $(command -v fusermount) ==="
      sudo ln -sf "$(command -v fusermount)" /usr/bin/fusermount3
    else
      die "未找到 fusermount/fusermount3，请手动安装：sudo apt-get install -y fuse3"
    fi
  fi
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
  if [ -n "${REMOTE_NAME}" ]; then return 0; fi
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
SupplementaryGroups=fuse
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$(command -v rclone) mount ${REMOTE_REF} ${MOUNT_DIR} \\
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

retry_wait_mount(){
  # 启动后等待挂载就绪（最多 10 次 × 0.5s）
  for i in {1..10}; do
    if is_mounted; then return 0; fi
    sleep 0.5
  done
  return 1
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
    if retry_wait_mount; then
      msg "✅ OneDrive 已成功挂载到 ${MOUNT_DIR}"
    else
      msg "⚠️ 仍未挂载成功。下面显示服务状态与日志末尾："
      sudo systemctl status "${SERVICE_NAME}" --no-pager || true
      sudo tail -n 100 "${LOG_FILE}" || true
      exit 1
    fi
  fi
  # 展示实际挂载信息，帮助核对
  echo "—— 实际挂载信息 ——"
  findmnt -rn -T "${MOUNT_DIR}" -o TARGET,SOURCE,FSTYPE,OPTIONS || true
}

cmd_status(){
  detect_remote || true
  local fm
  fm="$(findmnt -rn -T "${MOUNT_DIR}" -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true)"
  echo "挂载点：${MOUNT_DIR}"
  echo "挂载信息：${fm:-未挂载}"
  echo
  echo "服务状态："
  systemctl --no-pager --full status "${SERVICE_NAME}" || true
}

cmd_start(){ sudo systemctl start "${SERVICE_NAME}"; }
cmd_stop(){ sudo systemctl stop "${SERVICE_NAME}" || true; }
cmd_restart(){ sudo systemctl restart "${SERVICE_NAME}" || sudo systemctl start "${SERVICE_NAME}"; }
cmd_logs(){ sudo tail -n 100 "${LOG_FILE}" || echo "暂无日志：${LOG_FILE}"; }

cmd_unmount(){
  detect_remote || true
  if is_mounted; then
    local fb="$(command -v fusermount3 || command -v fusermount || echo)"
    if [ -n "$fb" ]; then "$fb" -u "${MOUNT_DIR}" || true; fi
    is_mounted && sudo umount -l "${MOUNT_DIR}" || true
    echo "已卸载（如服务仍启动，可执行：systemctl stop ${SERVICE_NAME}）"
  else
    echo "未挂载，无需卸载。"
  fi
}

cmd_reconnect(){
  need_rclone
  detect_remote
  rclone config reconnect "${REMOTE_NAME}:" || die "reconnect 失败"
  echo "✅ 远程 ${REMOTE_NAME} 已尝试重新授权"
}

cmd_doctor(){
  echo "=== rclone 版本 ==="
  command -v rclone && rclone version || echo "未找到 rclone"
  echo "=== fusermount 可用性 ==="
  command -v fusermount3 || echo "fusermount3 不存在"
  command -v fusermount  || echo "fusermount 不存在"
  echo "=== /dev/fuse ==="
  ls -l /dev/fuse || true
  echo "=== fuse 组与用户 ==="
  getent group fuse || echo "无 fuse 组"
  id "${USER_NAME}" || true
  echo "=== 远程列表 ==="
  rclone listremotes || true
  echo "=== findmnt 检查 ==="
  findmnt -rn -T "${MOUNT_DIR}" -o TARGET,SOURCE,FSTYPE,OPTIONS || true
  echo "=== 服务启用/运行 ==="
  systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || echo "服务未启用"
  systemctl is-active "${SERVICE_NAME}" 2>/dev/null || echo "服务未运行"
}

cmd_cleanup(){
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
    esac; shift
  done

  msg "=== 停止服务并卸载挂载 ==="
  systemctl is-active --quiet "${SERVICE_NAME}" && sudo systemctl stop "${SERVICE_NAME}" || true
  if mountpoint -q -- "${MOUNT_DIR}"; then
    local fb="$(command -v fusermount3 || command -v fusermount || echo)"
    [ -n "$fb" ] && "$fb" -u "${MOUNT_DIR}" || true
    mountpoint -q -- "${MOUNT_DIR}" && sudo umount -l "${MOUNT_DIR}" || true
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
  if [ "${PURGE_FUSE_SOFTLINK}" -eq 1 ] && [ -L /usr/bin/fusermount3 ]; then
    local TARGET="$(readlink -f /usr/bin/fusermount3 || true)"
    local REAL_FUSER="$(command -v fusermount || true)"
    if [ -n "$REAL_FUSER" ] && [ "$TARGET" = "$REAL_FUSER" ]; then
      sudo rm -f /usr/bin/fusermount3
    fi
  fi

  msg "=== 清理完成 ==="
}

cmd_ls(){
  need_rclone
  detect_remote
  echo "Remote: ${REMOTE_NAME}"
  rclone lsd "${REMOTE_NAME}:"
}

usage(){
  cat <<EOF
用法: $0 <command> [args]

命令：
  install        安装/修复 FUSE、写/更服务，并挂载（严格但兼容；已挂载则跳过）
  status         显示挂载与服务状态（含 findmnt 信息）
  start|stop|restart  控制 systemd 服务
  logs           显示最近100行日志
  unmount        卸载挂载点（不禁用服务）
  reconnect      rclone 远程重连授权（token 过期时使用）
  doctor         自检 rclone/fuse/remote/服务/挂载
  cleanup        清理服务与日志；可加参数删除缓存/挂载目录/软链
                 可选：--purge-cache --purge-mount-dir | --purge-mount-dir-if-empty --purge-logs --purge-fuse-softlink
  ls             直接列远程根目录

示例：
  $0 install
  REMOTE_NAME=E5OneDrive $0 install
  $0 status
  $0 ls
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
    ls)        cmd_ls ;;
    ""|-h|--help) usage ;;
    *) die "未知命令：${cmd}. 运行 --help 查看用法。" ;;
  esac
}

main "$@"

