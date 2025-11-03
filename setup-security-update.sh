#!/usr/bin/env bash
# setup-security-update.sh
# 将 Ubuntu 配置为每天凌晨 3 点仅自动安装“安全更新”（security），
# 不更新普通应用层包；不改变手动 apt upgrade 的行为。
# 执行 sudo bash setup-security-update.sh
set -euo pipefail

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "请用 root 运行：sudo bash $0" >&2
    exit 1
  fi
}

log() { echo -e "\n==> $*\n"; }

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak.$(date +%Y%m%d-%H%M%S)"
  fi
}

main() {
  need_root

  # 检测发行版代号（focal, jammy, noble 等），供提示用（脚本逻辑不依赖此变量）
  local codename="unknown"
  if command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -sc)"
  elif [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-unknown}"
  fi

  log "1) 安装 unattended-upgrades（仅自动安装安全补丁所需）"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y unattended-upgrades apt-listchanges

  # 启用自动升级（不限定安全与否，限定由 50unattended-upgrades 控制）
  log "2) 启用自动升级周期参数（每天检查 & 执行；随机延时为 0）"
  backup_file /etc/apt/apt.conf.d/20auto-upgrades
  cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::RandomSleep "0";
EOF

  # 只允许“security”来源的补丁被自动安装
  # 做法：编辑 50unattended-upgrades，把 security 这一行取消注释，其它 updates/backports/proposed/esm 统统注释
  log "3) 限定自动安装的来源为 security（不含 updates/backports/proposed/esm）"
  local cfg="/etc/apt/apt.conf.d/50unattended-upgrades"
  backup_file "$cfg"

  # 确保文件存在（部分极简系统可能没有）
  if [[ ! -f "$cfg" ]]; then
    unattended-upgrades --print-conf >"$cfg" || true
  fi

  # 取消注释 security 行
  sed -i \
    's#^\s*//\s*"\s*origin=Ubuntu,archive=\${distro_codename}-security";#        "origin=Ubuntu,archive=${distro_codename}-security";#' \
    "$cfg"

  # 注释掉 Origins-Pattern 块里除 security 以外的常见通道
  sed -i '/Unattended-Upgrade::Origins-Pattern {/,/};/ {
    s#^\s*"\(.*updates.*\)";#        // "\1";#;
    s#^\s*"\(.*proposed.*\)";#        // "\1";#;
    s#^\s*"\(.*backports.*\)";#        // "\1";#;
    s#^\s*"\(.*esm.*\)";#        // "\1";#;
  }' "$cfg"

  #（可选稳妥项）开启自动清理旧内核/自动移除不再需要的依赖
  if ! grep -q 'Unattended-Upgrade::Remove-Unused-Kernel-Packages' "$cfg"; then
    cat >>"$cfg" <<'EOF'

Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
  fi

  # systemd 定时器：
  # - apt-daily.timer 负责每日刷新包列表（apt update）
  # - apt-daily-upgrade.timer 负责每日执行 unattended-upgrades
  # 我们把“刷新列表”放 03:00，“执行升级”放 03:15，且不做随机延迟，确保顺序与可预期性
  log "4) 将 systemd 定时器固定到每天 03:00（刷新列表）与 03:15（自动安装安全补丁）"
  mkdir -p /etc/systemd/system/apt-daily.timer.d
  cat >/etc/systemd/system/apt-daily.timer.d/override.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:00
RandomizedDelaySec=0
EOF

  mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
  cat >/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:15
RandomizedDelaySec=0
EOF

  systemctl daemon-reload
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer

  log "5) 立即做一次“安全更新（dry-run）”以验证只针对 security"
  unattended-upgrade --dry-run --debug | grep -E 'Allowed origins|Packages that will be upgraded' || true

  log "6) 查看相关定时器（下次触发时间）"
  systemctl list-timers 'apt-daily*' --all || true

  log "完成！当前系统：${codename}。自动任务将在每天 03:00 更新列表、03:15 安装安全补丁。"
  echo "手动执行完整更新仍使用：sudo apt update && sudo apt upgrade"
}

main "$@"

