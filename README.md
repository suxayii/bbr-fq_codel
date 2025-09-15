# 🐂 BBR 自动启用 & 网络优化脚本

[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)  
[![Linux](https://img.shields.io/badge/Linux-Compatible-blue)](https://www.kernel.org/)  
[![BBR](https://img.shields.io/badge/BBR-Enabled-orange)](https://www.kernel.org/doc/html/latest/networking/tcp_congestion_control.html)  

一键识别系统并启用 **BBR 拥塞控制算法**，同时进行 **网络参数优化**，支持 **fq / fq_codel** 队列调度器，并可选进行本地带宽测速。  

适用于 Debian/Ubuntu、CentOS 等常见 Linux 发行版。  

---
## ⚡ 快速开始

### 1️⃣ 下载脚本

```bash
bash <(curl -Ls https://raw.githubusercontent.com/yourusername/bbr-optimizer/main/bbr.sh)

## ✨ 功能亮点

- 自动检测系统信息：CPU 型号、内核版本、操作系统、公网 IP、默认路由。  
- 启用 BBR 拥塞控制算法，并自动加载模块（如未启用）。  
- 支持 `fq` 和 `fq_codel` 队列调度器，可通过参数切换。  
- 调整 TCP 缓冲区、连接超时、TIME-WAIT 重用、SYN backlog 等网络参数。  
- 自动检测默认网卡并验证队列调度器是否生效。  
- 可选使用 `iperf3` 进行本地或远程带宽测试。  

---

## 🖥 系统要求

- Linux 内核版本 >= 4.9  
- Debian/Ubuntu 或 CentOS 系统  
- root 权限（或使用 `sudo` 执行脚本）  

---
