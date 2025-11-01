#!/bin/bash
# =========================================================
# BBR + 网络优化自动配置脚本 (v5.4)
# - 自动检测 IPv6 支持（若无则跳过）
# - 自动清理无效 IPv6 配置（防止 sysctl 报错）
# - 自动检测网卡
# - 修改目标：/etc/sysctl.conf
# - 支持系统：Debian / Ubuntu / CentOS / AlmaLinux / RockyLinux
# =========================================================
set -euo pipefail
trap 'echo "❌ 发生错误于第 $LINENO 行: $BASH_COMMAND"; exit 1' ERR
LOG_FILE="/var/log/bbr-optimize.log"
SYSCTL_CONF="/etc/sysctl.conf"
QDISC=${1:-fq}
VALID_QDISC=("fq" "fq_codel")

exec > >(tee -a "$LOG_FILE") 2>&1
echo "================ $(date) ================"
echo "🗒️ 日志记录到 $LOG_FILE"

# ---------------- 权限检查 ----------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用 root 权限运行"
  exit 1
fi

for cmd in curl ip lscpu sysctl awk sed grep tee; do
  command -v $cmd >/dev/null 2>&1 || { echo "❌ 缺少命令: $cmd"; exit 1; }
done

# ---------------- 参数检查 ----------------
if [[ ! " ${VALID_QDISC[*]} " =~ " ${QDISC} " ]]; then
  echo "❌ 参数错误，请使用: $0 [fq|fq_codel]"
  exit 1
fi

# ---------------- 系统信息 ----------------
source /etc/os-release 2>/dev/null || true
echo "==== 系统信息 ===="
echo "系统: ${PRETTY_NAME:-未知}"
echo "内核: $(uname -r)"
echo "CPU : $(lscpu | grep 'Model name' | awk -F ':' '{print $2}' | xargs)"

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
echo "公网 IP: $(get_public_ip)"
echo "默认路由:"
ip route show default || echo "无法获取路由信息"
echo "---------------------------------------"

kernel_major=$(uname -r | cut -d. -f1)
kernel_minor=$(uname -r | cut -d. -f2)
if [[ $kernel_major -lt 4 ]] || ([[ $kernel_major -eq 4 ]] && [[ $kernel_minor -lt 9 ]]); then
  echo "❌ 当前内核版本过低（$(uname -r)），BBR 需要 ≥ 4.9"
  exit 1
fi

# ---------------- 备份 sysctl.conf ----------------
BACKUP_FILE="/etc/sysctl.conf.bak-$(date +%Y%m%d-%H%M%S)"
cp -a "$SYSCTL_CONF" "$BACKUP_FILE" 2>/dev/null || true
echo "✅ 已备份原 sysctl.conf 到: $BACKUP_FILE"

# ---------------- 参数更新函数 ----------------
update_sysctl_param() {
  local key=$1 value=$2
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$SYSCTL_CONF"; then
    sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$SYSCTL_CONF"
    echo "更新: ${key} = ${value}"
  else
    echo "${key} = ${value}" >> "$SYSCTL_CONF"
    echo "添加: ${key} = ${value}"
  fi
}

# ---------------- 写入参数 ----------------
echo "==== 写入 BBR 及网络优化参数 ===="
PARAMS=(
  "fs.file-max=6815744"
  "net.ipv4.tcp_no_metrics_save=1"
  "net.ipv4.tcp_ecn=0"
  "net.ipv4.tcp_frto=0"
  "net.ipv4.tcp_mtu_probing=0"
  "net.ipv4.tcp_rfc1337=0"
  "net.ipv4.tcp_sack=1"
  "net.ipv4.tcp_fack=1"
  "net.ipv4.tcp_window_scaling=1"
  "net.ipv4.tcp_adv_win_scale=1"
  "net.ipv4.tcp_moderate_rcvbuf=1"
  "net.core.rmem_max=33554432"
  "net.core.wmem_max=33554432"
  "net.ipv4.tcp_rmem=4096 87380 33554432"
  "net.ipv4.tcp_wmem=4096 65536 33554432"
  "net.ipv4.udp_rmem_min=8192"
  "net.ipv4.udp_wmem_min=8192"
  "net.ipv4.ip_forward=1"
  "net.ipv4.conf.all.route_localnet=1"
  "net.ipv4.conf.all.forwarding=1"
  "net.ipv4.conf.default.forwarding=1"
  "net.core.default_qdisc=${QDISC}"
  "net.ipv4.tcp_congestion_control=bbr"
  # 附加优化
  "net.ipv4.tcp_fin_timeout=10"
  "net.ipv4.tcp_tw_reuse=1"
  "net.ipv4.tcp_max_syn_backlog=8192"
  "net.ipv4.tcp_synack_retries=2"
  "net.ipv4.tcp_syncookies=1"
  "net.ipv4.tcp_fastopen=3"
)

# -------- 检测 IPv6 支持并动态配置 --------
if [[ -f /proc/net/if_inet6 ]] && [[ -s /proc/net/if_inet6 ]]; then
  echo "✅ 检测到系统支持 IPv6"
  iface=$(ip route show default | awk '{print $5}' | head -n1)
  if [[ -n "$iface" ]]; then
    echo "检测到默认网卡: $iface"
    PARAMS+=(
      "net.ipv6.conf.all.forwarding=1"
      "net.ipv6.conf.default.forwarding=1"
      "net.ipv6.conf.${iface}.autoconf=0"
      "net.ipv6.conf.${iface}.accept_ra=0"
    )
  else
    echo "⚠️ 未检测到默认网卡，跳过 IPv6 相关参数"
  fi
else
  echo "🚫 未检测到 IPv6 支持，跳过所有 IPv6 参数设置"
fi

for param in "${PARAMS[@]}"; do
  update_sysctl_param "${param%%=*}" "${param#*=}"
done

# ---------------- 自动清理无效 IPv6 配置 ----------------
echo "==== 清理无效 IPv6 sysctl 参数 ===="
CONF_FILES=(/etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf)
for conf in "${CONF_FILES[@]}"; do
  [[ -f $conf ]] || continue
  grep -nE '^[[:space:]]*net\.ipv6\.conf\.' "$conf" 2>/dev/null | while IFS=: read -r lineno line; do
    if [[ $line =~ net\.ipv6\.conf\.([a-zA-Z0-9:_.-]+)\.([a-zA-Z0-9_]+) ]]; then
      iface="${BASH_REMATCH[1]}"
      param="${BASH_REMATCH[2]}"
      proc_path="/proc/sys/net/ipv6/conf/${iface}/${param}"
      if [[ ! -e "$proc_path" ]]; then
        sed -i -E "${lineno}s|^|# |" "$conf"
        echo "🧹 注释: $conf 行 $lineno -> net.ipv6.conf.${iface}.${param} (不存在)"
      fi
    fi
  done
done
echo "✅ 清理完成"

# ---------------- 应用配置 ----------------
echo "==== 应用配置 ===="
if sysctl -p && sysctl --system; then
  echo "✅ sysctl 参数应用成功"
else
  echo "⚠️ sysctl 应用时出错，请检查文件格式或权限"
  exit 1
fi

# ---------------- 验证状态 ----------------
echo "==== 验证结果 ===="
cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
echo "拥塞控制算法: $cc"
echo "队列调度算法: $qdisc"

if [[ "$cc" != "bbr" ]]; then
  echo "⚠️ BBR 未立即生效，尝试加载模块..."
  if modprobe tcp_bbr 2>/dev/null; then
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null || true
    echo "✅ 模块已加载并设为开机自启"
  else
    echo "⚠️ BBR 模块可能已内置或不被支持"
  fi
fi

if lsmod | grep -q tcp_bbr; then
  echo "✅ BBR 模块已加载"
else
  echo "⚠️ 未检测到 tcp_bbr 模块，可能已内置或需重启"
fi

iface=$(ip route show default | awk '{print $5}' | head -n1)
if [[ -n "$iface" ]]; then
  echo "默认网卡: $iface"
  if command -v tc >/dev/null 2>&1 && tc qdisc show dev "$iface" | grep -qE "$QDISC"; then
    echo "✅ $QDISC 已应用"
  else
    echo "⚠️ $QDISC 未检测到，请检查配置"
  fi
else
  echo "⚠️ 无法识别默认网卡，跳过验证"
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
echo "🎉 BBR 网络优化完成！建议重启系统确保配置完全生效。"
echo "配置文件: ${SYSCTL_CONF}"
echo "备份文件: ${BACKUP_FILE}"
echo "日志: ${LOG_FILE}"
