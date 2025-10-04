#!/bin/bash
# 自动识别系统并启用BBR及网络优化（支持 fq / fq_codel + 可选测速）

set -euo pipefail

# 用户选择队列调度器（fq 或 fq_codel）
QDISC=${1:-fq}   # 默认 fq，可以执行时传参数切换，比如 ./bbr.sh fq_codel

if [[ "$QDISC" != "fq" && "$QDISC" != "fq_codel" ]]; then
  echo "❌ 参数错误，请使用: $0 [fq|fq_codel]"
  exit 1
fi

echo "==== 系统与网络信息 ===="
echo "CPU型号: $(lscpu | grep 'Model name' | awk -F ':' '{print $2}' | sed 's/^[ \t]*//')"
echo "内核版本: $(uname -r)"
echo "操作系统: $(source /etc/os-release && echo $PRETTY_NAME)"
echo "公网IP : $(curl -s --max-time 5 https://ipinfo.io/ip || echo '获取失败')"
echo "当前默认路由网关:"
ip route show default || echo "无法获取路由信息"
echo "-----------------------"

# 检查内核版本
kernel_version=$(uname -r | awk -F'.' '{print $1"."$2}')
if (( $(echo "$kernel_version < 4.9" | bc -l) )); then
  echo "内核版本过低（需要>=4.9），请先升级内核。"
  exit 1
fi

# 添加或更新 sysctl 参数函数
add_sysctl_param() {
  local key=$1
  local value=$2
  if grep -q "^${key}" /etc/sysctl.conf; then
    sed -i "s|^${key}.*|${key} = ${value}|" /etc/sysctl.conf
  else
    echo "${key} = ${value}" >> /etc/sysctl.conf
  fi
}

echo "==== 启用 BBR ===="
add_sysctl_param "net.core.default_qdisc" "$QDISC"
add_sysctl_param "net.ipv4.tcp_congestion_control" "bbr"

sysctl -p >/dev/null

# 验证 BBR
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

echo "==== 网络参数优化 ===="
# 优化参数
add_sysctl_param "net.core.rmem_max" "2500000"
add_sysctl_param "net.core.wmem_max" "2500000"
add_sysctl_param "net.ipv4.tcp_rmem" "4096 87380 2500000"
add_sysctl_param "net.ipv4.tcp_wmem" "4096 65536 2500000"
add_sysctl_param "net.ipv4.tcp_fin_timeout" "10"
add_sysctl_param "net.ipv4.tcp_tw_reuse" "1"
add_sysctl_param "net.ipv4.tcp_max_syn_backlog" "8192"
add_sysctl_param "net.ipv4.tcp_synack_retries" "2"
add_sysctl_param "net.ipv4.tcp_syncookies" "1"
add_sysctl_param "net.ipv4.tcp_fastopen" "3"

sysctl -p >/dev/null
echo "✅ 网络优化参数已应用。"

echo "==== 验证队列调度器 ===="
default_iface=$(ip route show default | awk '{print $5}' | head -n1)
if [[ -n "$default_iface" ]]; then
  echo "检测默认网卡: $default_iface"
  tc qdisc show dev "$default_iface" | grep -E "fq|fq_codel" || echo "⚠️ 未检测到 $QDISC，请检查"
else
  echo "⚠️ 未找到默认网卡，无法验证 qdisc"
fi

echo "==== 可选测速环节 ===="
if ! command -v iperf3 >/dev/null 2>&1; then
  echo "⚠️ 未检测到 iperf3，尝试安装..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y iperf3
  elif command -v yum >/dev/null 2>&1; then
    yum install -y iperf3
  else
    echo "❌ 无法自动安装 iperf3，请手动安装。"
  fi
fi

if command -v iperf3 >/dev/null 2>&1; then
  echo "👉 运行简单的本地测试: iperf3 -s -1 & iperf3 -c 127.0.0.1 -t 5"
  iperf3 -s -1 >/dev/null 2>&1 &
  sleep 1
  iperf3 -c 127.0.0.1 -t 5
  echo "✅ 本地带宽测试完成（可用 iperf3 -c <远程IP> 测跨机效果）"
else
  echo "⚠️ iperf3 不可用，跳过测速"
fi

echo "==== 完成 ===="
echo "建议重启服务器以确保全部设置生效。"
