#!/bin/bash
# 自动识别系统并启用BBR及网络优化（支持 fq / fq_codel + 可选测速）
# 增加菜单选择功能：启用 BBR + fq、启用 BBR + fq_codel、备份/还原 sysctl 配置、优化参数、验证、测速、系统信息、历史备份恢复

set -euo pipefail

SYSCTL_FILE="/etc/sysctl.conf"
BACKUP_PREFIX="/etc/sysctl.conf.bak_"
BACKUP_FILE="${BACKUP_PREFIX}$(date +%Y%m%d%H%M%S)"

# 添加或更新 sysctl 参数函数
add_sysctl_param() {
  local key=$1
  local value=$2
  if grep -q "^${key}" "$SYSCTL_FILE" 2>/dev/null; then
    sed -i "s|^${key}.*|${key} = ${value}|" "$SYSCTL_FILE"
  else
    echo "${key} = ${value}" >> "$SYSCTL_FILE"
  fi
}

enable_bbr() {
  local QDISC=$1
  echo "==== 启用 BBR ($QDISC) ===="
  add_sysctl_param "net.core.default_qdisc" "$QDISC"
  add_sysctl_param "net.ipv4.tcp_congestion_control" "bbr"
  sysctl -p >/dev/null

  current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
  current_qdisc=$(sysctl -n net.core.default_qdisc)
  echo "✅ 拥塞控制算法: $current_cc"
  echo "✅ 队列调度器   : $current_qdisc"

  if [[ "$current_cc" != "bbr" ]]; then
    echo "⚠️ BBR 未启用，尝试加载模块..."
    if modprobe tcp_bbr 2>/dev/null; then
      echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
      echo "✅ tcp_bbr 模块已加载，下次重启后生效"
    else
      echo "❌ 系统不支持或已内置 BBR，请手动检查。"
    fi
  fi
}

backup_config() {
  echo "==== 备份 sysctl 配置 ===="
  cp -a "$SYSCTL_FILE" "$BACKUP_FILE"
  echo "✅ 已备份到 $BACKUP_FILE"
}

restore_latest_config() {
  echo "==== 还原最近一次备份 ===="
  latest_backup=$(ls -t ${BACKUP_PREFIX}* 2>/dev/null | head -n1 || true)
  if [[ -f "$latest_backup" ]]; then
    cp -a "$latest_backup" "$SYSCTL_FILE"
    sysctl -p >/dev/null
    echo "✅ 已还原自 $latest_backup"
  else
    echo "⚠️ 未找到任何备份文件。"
  fi
}

restore_select_config() {
  echo "==== 历史备份列表 ===="
  backups=( $(ls -t ${BACKUP_PREFIX}* 2>/dev/null || true) )
  if [[ ${#backups[@]} -eq 0 ]]; then
    echo "⚠️ 未找到任何备份文件。"
    return
  fi

  local i=1
  for f in "${backups[@]}"; do
    echo "$i) $f"
    ((i++))
  done

  read -rp "请输入要还原的编号: " idx
  if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#backups[@]} )); then
    chosen=${backups[$((idx-1))]}
    cp -a "$chosen" "$SYSCTL_FILE"
    sysctl -p >/dev/null
    echo "✅ 已还原自 $chosen"
  else
    echo "❌ 无效选择"
  fi
}

optimize_network() {
  echo "==== 网络参数优化 ===="
  add_sysctl_param "net.core.rmem_max" "2500000"
  add_sysctl_param "net.core.wmem_max" "2500000"
  add_sysctl_param "net.ipv4.tcp_rmem" "4096 87380 2500000"
  add_sysctl_param "net.ipv4.tcp_wmem" "4096 65536 2500000"
  add_sysctl_param "net.ipv4.tcp_fin_timeout" "10"
  add_sysctl_param "net.ipv4.tcp_max_syn_backlog" "8192"
  add_sysctl_param "net.ipv4.tcp_synack_retries" "2"
  add_sysctl_param "net.ipv4.tcp_syncookies" "1"
  add_sysctl_param "net.ipv4.tcp_fastopen" "3"
  if sysctl -a 2>/dev/null | grep -q "net.ipv4.tcp_tw_reuse"; then
    add_sysctl_param "net.ipv4.tcp_tw_reuse" "1"
  fi
  sysctl -p >/dev/null
  echo "✅ 网络优化参数已应用。"
}

verify_qdisc() {
  echo "==== 验证队列调度器 ===="
  default_iface=$(ip route show default | awk '{print $5}' | head -n1)
  if [[ -n "$default_iface" ]]; then
    echo "检测默认网卡: $default_iface"
    tc qdisc show dev "$default_iface" | grep -E "fq|fq_codel" || echo "⚠️ 未检测到队列调度器，请检查"
  else
    echo "⚠️ 未找到默认网卡，无法验证 qdisc"
  fi
}

run_speedtest() {
  echo "==== 简单测速（iperf3） ===="
  if ! command -v iperf3 >/dev/null 2>&1; then
    echo "⚠️ 未检测到 iperf3，尝试安装..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update && apt-get install -y iperf3 || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y iperf3 || true
    else
      echo "❌ 无法自动安装 iperf3，请手动安装。"
    fi
  fi

  if command -v iperf3 >/dev/null 2>&1; then
    echo "👉 运行本地 loopback 测试: iperf3 -s -1 & iperf3 -c 127.0.0.1 -t 5"
    iperf3 -s -1 >/dev/null 2>&1 &
    sleep 1
    iperf3 -c 127.0.0.1 -t 5
    echo "✅ 本地测试完成（建议使用 speedtest-cli 或 iperf3 -c <远程IP> 测公网带宽）"
  else
    echo "⚠️ iperf3 不可用，跳过测速"
  fi
}

show_sysinfo() {
  echo "==== 系统与网络信息 ===="
  echo "CPU型号   : $(lscpu | grep 'Model name' | awk -F ':' '{print $2}' | sed 's/^[ \t]*//')"
  echo "内核版本  : $(uname -r)"
  echo "操作系统  : $(source /etc/os-release && echo $PRETTY_NAME)"
  echo "公网IP    : $(curl -s --max-time 5 https://ipinfo.io/ip || echo '获取失败')"
  echo "默认路由  :"
  ip route show default || echo "无法获取路由信息"
  echo "拥塞算法  : $(sysctl -n net.ipv4.tcp_congestion_control)"
  echo "默认 qdisc: $(sysctl -n net.core.default_qdisc)"
  echo "-----------------------"
}

# 菜单栏
while true; do
  clear
  echo "============================"
  echo "   BBR & 网络优化工具菜单   "
  echo "============================"
  echo "1) 启用 BBR + fq_codel"
  echo "2) 启用 BBR + fq"
  echo "3) 备份 sysctl 配置"
  echo "4) 还原最近一次备份"
  echo "5) 应用网络优化参数"
  echo "6) 验证当前队列调度器"
  echo "7) 运行测速 (iperf3)"
  echo "8) 显示系统与网络信息"
  echo "9) 选择历史备份文件还原"
  echo "0) 退出"
  echo "============================"
  read -rp "请输入选项: " choice

  case "$choice" in
    1) enable_bbr "fq_codel"; read -rp "按回车返回菜单..." ;;
    2) enable_bbr "fq"; read -rp "按回车返回菜单..." ;;
    3) backup_config; read -rp "按回车返回菜单..." ;;
    4) restore_latest_config; read -rp "按回车返回菜单..." ;;
    5) optimize_network; read -rp "按回车返回菜单..." ;;
    6) verify_qdisc; read -rp "按回车返回菜单..." ;;
    7) run_speedtest; read -rp "按回车返回菜单..." ;;
    8) show_sysinfo; read -rp "按回车返回菜单..." ;;
    9) restore_select_config; read -rp "按回车返回菜单..." ;;
    0) echo "已退出."; exit 0 ;;
    *) echo "❌ 无效选项"; sleep 1 ;;
  esac
done
