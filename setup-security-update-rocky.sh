#!/usr/bin/env bash
# setup-security-update-rocky.sh
# 为 Rocky Linux 配置每日凌晨 3 点自动安装“安全更新”
# 仅安全补丁，不更新普通应用。不会影响手动 dnf upgrade。
set -euo pipefail

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "请以 root 身份运行：sudo bash $0" >&2
    exit 1
  fi
}

log() { echo -e "\n==> $*\n"; }

backup_file() {
  local f="$1"
  [[ -f "$f" ]] && cp -a "$f" "${f}.bak.$(date +%Y%m%d-%H%M%S)"
}

main() {
  need_root

  log "1) 安装 dnf-automatic（自动更新工具）"
  dnf install -y dnf-automatic

  local conf="/etc/dnf/automatic.conf"
  backup_file "$conf"

  log "2) 配置仅自动安装安全更新"
  cat >"$conf" <<'EOF'
[commands]
upgrade_type = security
random_sleep = 0
download_updates = yes
apply_updates = yes

[emitters]
system_name = yes
emit_via = motd

[base]
debuglevel = 1
EOF

  log "3) 启用并设定定时任务为每日 03:00 执行"
  mkdir -p /etc/systemd/system/dnf-automatic.timer.d
  cat >/etc/systemd/system/dnf-automatic.timer.d/override.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:00
RandomizedDelaySec=0
EOF

  systemctl daemon-reload
  systemctl enable --now dnf-automatic.timer

  log "4) 验证服务状态与下次执行时间"
  systemctl status dnf-automatic.timer --no-pager || true
  systemctl list-timers dnf-automatic* --all || true

  log "5) 立即模拟一次安全更新（仅查看，不安装）"
  dnf updateinfo list security || true
  echo
  echo "可手动测试自动更新命令（实际执行）：sudo dnf-automatic --timer"
  echo "手动完整更新仍使用：sudo dnf upgrade"
  echo "配置完成 ✅"
}

main "$@"

