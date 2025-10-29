# BBR + 网络优化自动配置脚本
## 语言选择 | Language Selection

- [English Version](README_EN.md)

![GitHub stars](https://img.shields.io/github/stars/yourusername/bbr-optimizer?style=social)
![GitHub forks](https://img.shields.io/github/forks/yourusername/bbr-optimizer?style=social)
![GitHub license](https://img.shields.io/github/license/yourusername/bbr-optimizer)
![Shell Script](https://img.shields.io/badge/language-Shell%20Script-blue)

一个强大的一键式BBR网络优化脚本，支持Linux系统自动配置BBR拥塞控制算法和网络参数，提升服务器网络性能。

## 🌟 功能特点

### 核心功能
- **自动检测系统**：支持Debian/Ubuntu/CentOS/AlmaLinux/RockyLinux等主流Linux系统
- **BBR加速**：自动配置并启用BBR拥塞控制算法
- **网络参数优化**：自动TCP/UDP/IP栈进行全面优化
- **队列调度算法**：支持fq和fq_codel两种队列调度算法
- **自动备份**：修改前自动备份原始配置文件
- **权限检查**：确保以root权限运行
- **依赖检查**：自动检查并提示缺失的依赖命令

### 增强特性
- **详细日志**：操作过程记录到`/var/log/bbr-optimize.log`
- **时间戳备份**：配置文件备份包含时间戳，避免覆盖
- **自动模块加载**：检测并加载tcp_bbr模块
- **带宽测试**：可选的iperf3带宽测试功能
- **全面诊断**：显示系统信息、网络配置和优化结果
- **错误处理**：完善的错误处理和用户提示

## 🚀 快速开始

### 下载并运行脚本
```bash
wget -O bbr.sh https://raw.githubusercontent.com/suxayii/bbr-fq_codel/main/bbr-fq.sh
chmod +x bbr.sh
sudo ./bbr.sh fq_codel
```

### 回滚备份
```bash
sudo cp /etc/sysctl.conf.bak-YYYYMMDD-HHMMSS /etc/sysctl.conf
sudo sysctl -p
```
## ⚙️ 系统要求

- **内核版本**：Linux内核4.9或更高版本（BBR需要）
- **系统支持**：
  - Debian 9+
  - Ubuntu 16.04+
  - CentOS 7+
  - AlmaLinux 8+
  - RockyLinux 8+
- **权限要求**：必须以root权限运行
- **网络要求**：需要互联网连接（用于依赖安装和IP检测）

## 📋 优化参数说明

脚本优化的主要参数包括：

### 文件描述符
- `fs.file-max=6815744` - 提高系统文件描述符限制

### TCP优化
- `tcp_no_metrics_save=1` - 不保存TCP连接的 metrics
- `tcp_sack=1` - 启用选择性确认
- `tcp_fack=1` - 启用转发确认
- `tcp_window_scaling=1` - 启用窗口缩放
- `tcp_adv_win_scale=1` - 优化窗口缩放
- `tcp_moderate_rcvbuf=1` - 启用TCP接收缓冲区自动调节
- `tcp_fin_timeout=10` - 缩短FIN等待时间
- `tcp_tw_reuse=1` - 允许重用TIME-WAIT sockets
- `tcp_max_syn_backlog=8192` - 增加SYN队列大小
- `tcp_synack_retries=2` - 减少SYN-ACK重试次数
- `tcp_syncookies=1` - 启用SYN cookies防御SYN攻击
- `tcp_fastopen=3` - 启用TCP快速打开

### 缓冲区优化
- `rmem_max=33554432` - 接收缓冲区最大值
- `wmem_max=33554432` - 发送缓冲区最大值
- `tcp_rmem=4096 87380 33554432` - TCP接收缓冲区范围
- `tcp_wmem=4096 65536 33554432` - TCP发送缓冲区范围
- `udp_rmem_min=8192` - UDP接收缓冲区最小值
- `udp_wmem_min=8192` - UDP发送缓冲区最小值

### BBR相关
- `default_qdisc=fq` - 设置默认队列调度算法
- `tcp_congestion_control=bbr` - 设置TCP拥塞控制算法为BBR

## 📊 测试结果

优化后，您可以期待：
- 网络吞吐量提升30%-200%（取决于网络环境）
- 延迟降低10%-50%
- 丢包率显著改善
- 连接稳定性提高

## 🔍 验证方法

优化完成后，可以通过以下命令验证BBR是否正常工作：

```bash
# 查看拥塞控制算法
sysctl net.ipv4.tcp_congestion_control

# 查看队列调度算法
sysctl net.core.default_qdisc

# 查看BBR模块是否加载
lsmod | grep tcp_bbr

# 查看网络接口队列配置
tc qdisc show dev $(ip route show default | awk '{print $5}' | head -n1)
```

## 📝 注意事项

1. **配置文件**：脚本直接修改`/etc/sysctl.conf`文件
2. **备份文件**：原始配置会备份到`/etc/sysctl.conf.bak-<timestamp>`
3. **日志文件**：操作日志保存在`/var/log/bbr-optimize.log`
4. **重启建议**：优化完成后建议重启系统以确保所有配置生效
5. **恢复方法**：如需恢复原始配置，可使用备份文件覆盖`/etc/sysctl.conf`

## ❗ 风险提示

- 本脚本会修改系统核心网络配置，请在生产环境谨慎使用
- 建议在非高峰期执行，并做好系统备份
- 不同网络环境可能需要不同的优化参数，默认配置适用于大多数场景

## 🤝 贡献指南

欢迎提交PR和Issue来帮助改进这个项目！

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交您的更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 打开一个Pull Request

## 📄 许可证

本项目采用MIT许可证 - 详见 [LICENSE](LICENSE) 文件

## 📞 支持

如有任何问题或建议，请提交Issue或联系我们。

---

*脚本版本：v5.1*
*最后更新：2025年*
