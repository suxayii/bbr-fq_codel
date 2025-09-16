#!/bin/bash
# 自动识别系统并启用BBR及网络优化（支持 fq / fq_codel + 可选测速）
# 增加错误处理、参数验证、系统兼容性检查、配置备份等功能

# 严格模式和错误处理
set -euo pipefail
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# 日志功能
LOG_FILE="/var/log/bbr_setup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# 错误处理函数
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    echo "❌ 错误发生在第 $line_no 行"
    echo "命令: $last_command"
    echo "错误代码: $exit_code"
    echo "函数调用栈: $func_trace"
    exit "$exit_code"
}

# 帮助信息
show_help() {
    cat << EOF
用法: $0 [选项]

选项:
    -q, --qdisc <fq|fq_codel>     设置队列调度器 (默认: fq)
    -b, --backup                   备份当前网络配置
    -t, --test-servers "ip1 ip2"   指定测速服务器IP列表
    -h, --help                     显示此帮助信息
EOF
    exit 0
}

# 配置备份函数
backup_config() {
    local backup_dir="/root/network_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp /etc/sysctl.conf "$backup_dir/sysctl.conf.bak"
    sysctl -a > "$backup_dir/sysctl_params.bak"
    echo "✅ 配置已备份到: $backup_dir"
}

# 系统兼容性检查
check_system_compatibility() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        echo "❌ 必须以root用户运行此脚本"
        exit 1
    }

    # 检查系统类型
    if ! command -v lsb_release >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y lsb-release
        elif command -v yum >/dev/null 2>&1; then
            yum install -y redhat-lsb-core
        fi
    fi

    local os_type=$(lsb_release -si 2>/dev/null || echo "Unknown")
    local os_version=$(lsb_release -sr 2>/dev/null || echo "Unknown")
    
    echo "检测到的系统: $os_type $os_version"
    
    # 检查必需工具
    local required_tools=("bc" "curl" "ip" "awk" "sed" "grep")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "❌ 缺少必需工具: $tool"
            echo "正在尝试安装..."
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y "$tool"
            elif command -v yum >/dev/null 2>&1; then
                yum install -y "$tool"
            else
                echo "❌ 无法自动安装 $tool，请手动安装"
                exit 1
            fi
        fi
    done
}

# 解析命令行参数
QDISC="fq"
BACKUP=0
TEST_SERVERS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--qdisc)
            QDISC="$2"
            shift 2
            ;;
        -b|--backup)
            BACKUP=1
            shift
            ;;
        -t|--test-servers)
            TEST_SERVERS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "❌ 未知参数: $1"
            show_help
            ;;
    esac
done

# 验证队列调度器参数
if [[ "$QDISC" != "fq" && "$QDISC" != "fq_codel" ]]; then
    echo "❌ 无效的队列调度器: $QDISC"
    show_help
fi

# 执行系统兼容性检查
check_system_compatibility

# 如果需要备份，先进行备份
if [[ $BACKUP -eq 1 ]]; then
    backup_config
fi

# 显示系统信息（美化输出）
echo -e "\n📊 ==== 系统与网络信息 ===="
printf "%-20s: %s\n" "CPU型号" "$(lscpu | grep 'Model name' | awk -F ':' '{print $2}' | sed 's/^[ \t]*//')"
printf "%-20s: %s\n" "内核版本" "$(uname -r)"
printf "%-20s: %s\n" "操作系统" "$(source /etc/os-release && echo "$PRETTY_NAME")"
printf "%-20s: %s\n" "公网IP" "$(curl -s --max-time 5 https://ipinfo.io/ip || echo '获取失败')"

# 网络参数优化（更全面的配置）
declare -A SYSCTL_PARAMS=(
    ["net.core.rmem_max"]="16777216"              # 增大接收缓冲区最大值
    ["net.core.wmem_max"]="16777216"              # 增大发送缓冲区最大值
    ["net.core.netdev_max_backlog"]="16384"       # 网卡数据包队列长度
    ["net.core.somaxconn"]="8192"                 # TCP连接队列长度
    ["net.ipv4.tcp_rmem"]="4096 87380 16777216"   # TCP接收缓冲区
    ["net.ipv4.tcp_wmem"]="4096 65536 16777216"   # TCP发送缓冲区
    ["net.ipv4.tcp_fin_timeout"]="10"             # FIN超时时间
    ["net.ipv4.tcp_tw_reuse"]="1"                 # 启用timewait复用
    ["net.ipv4.tcp_max_syn_backlog"]="8192"       # SYN队列长度
    ["net.ipv4.tcp_max_tw_buckets"]="5000"        # timewait最大数量
    ["net.ipv4.tcp_synack_retries"]="2"           # SYNACK重试次数
    ["net.ipv4.tcp_syncookies"]="1"               # 启用SYN Cookie
    ["net.ipv4.tcp_fastopen"]="3"                 # 启用TCP Fast Open
    ["net.ipv4.tcp_mtu_probing"]="1"              # 启用MTU探测
    ["net.ipv4.tcp_slow_start_after_idle"]="0"    # 禁用空闲后慢启动
    ["net.ipv4.ip_local_port_range"]="1024 65535" # 本地端口范围
)

# 应用网络参数
echo -e "\n🔧 ==== 应用网络优化参数 ===="
for param in "${!SYSCTL_PARAMS[@]}"; do
    echo "设置 $param = ${SYSCTL_PARAMS[$param]}"
    add_sysctl_param "$param" "${SYSCTL_PARAMS[$param]}"
done

# 改进的测速功能
if [[ -n "$TEST_SERVERS" ]]; then
    echo -e "\n🚀 ==== 多服务器测速 ===="
    if ! command -v iperf3 >/dev/null 2>&1; then
        echo "正在安装 iperf3..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y iperf3
        elif command -v yum >/dev/null 2>&1; then
            yum install -y iperf3
        fi
    fi

    for server in $TEST_SERVERS; do
        echo "测试服务器: $server"
        if iperf3 -c "$server" -t 10 -P 3; then
            echo "✅ $server 测速完成"
        else
            echo "❌ $server 测速失败"
        fi
    done
fi

echo -e "\n✨ ==== 配置完成 ===="
echo "📝 日志已保存到: $LOG_FILE"
echo "⚠️  建议重启服务器以确保所有设置生效"
