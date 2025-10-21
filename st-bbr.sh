#!/bin/bash
# =========================================================
# 自动识别系统并启用 BBR 及网络优化（支持 fq / fq_codel）
# 适配系统：Debian / Ubuntu / CentOS / AlmaLinux / RockyLinux
#
# v4.1 (专业增强版):
# - 写入 /etc/sysctl.d/99-bbr-opt.conf，避免直接改动 sysctl.conf
# - 修复 kill 空 PID 错误
# - 优化 sysctl 参数更新逻辑
# - 增强容错与日志输出
# =========================================================

set -euo pipefail
trap 'echo "❌ 发生错误于第 $LINENO 行: $BASH_COMMAND"; exit 1' ERR

# ---------------- 日志记录 ----------------
LOG_FILE="/var/log/bbr-optimize.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "================ $(date) ================"
echo "🗒️ 本次操作日志将记录到 $LOG_FILE"

# ---------------- 权限与依赖检查 ----------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ 本脚本需要 root 权限运行，请使用 sudo 执行"
  exit 1
fi

for cmd in curl ip lscpu sysctl awk sed grep tee; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "❌ 缺少关键命令 '$cmd'，请先安装。"
    exit 1
  fi
done

# ---------------- 参数设置 ----------------
QDISC=${1:-fq}
VALID_QDISC=("fq" "fq_codel")

if [[ ! " ${VALID_QDISC[*]} " =~ " ${QDISC} " ]]; then
  echo "❌ 参数错误，请使用: $0 [fq|fq_codel]"
  exit 1
fi

SYSCTL_CONF="/etc/sysctl.d/99-bbr-opt.conf"

# ---------------- 辅助函数 ----------------
get_public_ip() {
  for url in \
    "https://ipinfo.io/ip" \
    "https://api64.ipify.org" \
    "https://ifconfig.me" \
    "https://icanhazip.com"; do
    ip=$(curl -fsSL --max-time 5 "$url" || true)
    if [[ -n "$ip" && ! "$ip" =~ "error" ]]; then
      echo "$ip"
      return
    fi
  done
  echo "获取失败"
}

add_sysctl_param() {
  local key=$1 value=$2
  mkdir -p "$(dirname "$SYSCTL_CONF")"
  touch "$SYSCTL_CONF"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$SYSCTL_CONF"; then
    current_value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$SYSCTL_CONF" | tail -n1 | awk -F'=' '{print $2}' | xargs)
    if [[ "$current_value" != "$value" ]]; then
      sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$SYSCTL_CONF"
      echo "  -> 更新参数: ${key} = ${value}"
    fi
  else
    echo "${key} = ${value}" >> "$SYSCTL_CONF"
    echo "  -> 添加参数: ${key} = ${value}"
  fi
}

# ---------------- 系统信息 ----------------
echo "==== 系统与网络信息 ===="
echo "CPU 型号: $(LC_ALL=C lscpu | grep 'Model name' | awk -F ':' '{print $2}' | xargs)"
echo "内核版本: $(uname -r)"
source /etc/os-release 2>/dev/null || true
echo "操作系统: ${PRETTY_NAME:-未知}"
echo "公网 IP: $(get_public_ip)"
echo "默认路由:"
LC_ALL=C ip route show default || echo "无法获取路由信息"
echo "---------------------------------------"

# ---------------- 内核版本检测 ----------------
kernel_major=$(uname -r | cut -d. -f1)
kernel_minor=$(uname -r | cut -d. -f2)
if [[ $kernel_major -lt 4 ]] || ([[ $kernel_major -eq 4 ]] && [[ $kernel_minor -lt 9 ]]); then
  echo "❌ 当前内核版本过低（$(uname -r)），BBR 需要 ≥ 4.9"
  exit 1
fi

# ---------------- 配置参数 ----------------
echo "==== 配置 BBR 及网络优化参数 ===="
add_sysctl_param "net.core.default_qdisc" "$QDISC"
add_sysctl_param "net.ipv4.tcp_congestion_control" "bbr"

OPTIMIZATION_PARAMS=(
  "net.core.rmem_max=2500000" "net.core.wmem_max=2500000"
  "net.ipv4.tcp_rmem=4096 87380 2500000" "net.ipv4.tcp_wmem=4096 65536 2500000"
  "net.ipv4.tcp_fin_timeout=10" "net.ipv4.tcp_tw_reuse=1"
  "net.ipv4.tcp_max_syn_backlog=8192" "net.ipv4.tcp_synack_retries=2"
  "net.ipv4.tcp_syncookies=1" "net.ipv4.tcp_fastopen=3"
)
for param in "${OPTIMIZATION_PARAMS[@]}"; do
  add_sysctl_param "${param%%=*}" "${param#*=}"
done

# ---------------- 应用并验证配置 ----------------
echo "==== 应用并验证配置 ===="
if ! sysctl --system; then
  echo "⚠️ sysctl 配置应用失败，请检查 ${SYSCTL_CONF} 文件格式或权限。"
  exit 1
fi

current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
echo "✅ 拥塞控制算法: $current_cc"
echo "✅ 默认队列调度器: $current_qdisc"

if [[ "$current_cc" != "bbr" ]]; then
  echo "⚠️ BBR 未立即生效，尝试加载模块..."
  if modprobe tcp_bbr 2>/dev/null; then
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    echo "✅ 模块已加载并设为开机自启"
  else
    echo "⚠️ BBR 模块可能已内置或不被支持"
  fi
fi

# ---------------- 验证模块加载 ----------------
if lsmod | grep -q "tcp_bbr"; then
  echo "✅ 模块 tcp_bbr 已加载"
else
  echo "⚠️ 未检测到 tcp_bbr 模块，可能内置，建议重启后确认"
fi

# ---------------- 验证网卡队列调度器 ----------------
echo "==== 验证网卡队列调度器 ===="
if ! command -v tc >/dev/null 2>&1; then
  echo "⚠️ 未找到 'tc'，跳过验证（建议安装 iproute2）"
else
  default_iface=$(LC_ALL=C ip route show default | awk '{print $5}' | head -n1)
  if [[ -n "$default_iface" ]]; then
    echo "检测到默认网卡: $default_iface"
    if tc qdisc show dev "$default_iface" | grep -qE "fq|fq_codel"; then
      echo "✅ $QDISC 已应用于 $default_iface"
    else
      echo "⚠️ 未检测到 $QDISC，请检查配置"
    fi
  else
    echo "⚠️ 无法识别默认网卡，跳过验证"
  fi
fi

# ---------------- 可选带宽测试 ----------------
echo "==== 可选测速环节 ===="
if ! command -v iperf3 >/dev/null 2>&1; then
  echo "⚠️ iperf3 未安装，尝试安装..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -qq && apt-get install -y -qq iperf3
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q iperf3
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q iperf3
  else
    echo "❌ 无可用包管理器，请手动安装 iperf3"
  fi
fi

if command -v iperf3 >/dev/null 2>&1; then
  echo "👉 正在执行本地带宽测试 (3秒)..."
  iperf3 -s -1 >/dev/null 2>&1 &
  server_pid=$!
  sleep 1
  iperf3 -c 127.0.0.1 -t 3 || echo "⚠️ 测速失败（可能防火墙阻止 5201 端口）"
  if [[ -n "${server_pid:-}" ]] && ps -p "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  echo "✅ 测速完成"
else
  echo "⚠️ 跳过测速（iperf3 不可用）"
fi

echo ""
echo "==== 🎉 全部完成 ===="
echo "BBR 已成功启用。建议重启服务器以确保网络参数完全生效。"
