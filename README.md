# Linux BBR + FQ/FQ_CoDel 网络优化脚本

## 功能简介

这是一个用于 Linux 系统的网络优化脚本，主要功能包括：

- 自动启用 BBR 拥塞控制算法
- 支持 FQ 和 FQ_CoDel 队列调度器
- 自动优化系统网络参数
- 提供可选的网络性能测试功能

## 系统要求

- Linux 内核版本 ≥ 4.9
- 需要 root 权限执行
- 支持 Debian/Ubuntu 或 CentOS/RHEL 系列系统

## 使用方法

快速开启bbr+fq_codel：
```bash
wget https://raw.githubusercontent.com/suxayii/bbr-fq_codel/refs/heads/master/bbr-fq.sh && chmod +x bbr-fq.sh && ./bbr-fq.sh -q fq_codel

```

快速开启bbr+fq：
```bash
wget https://raw.githubusercontent.com/suxayii/bbr-fq_codel/main/bbr-fq.sh && chmod +x bbr-fq.sh && ./bbr-fq.sh
```


## 脚本功能详解

### 1. 系统检测
- 显示 CPU 型号
- 显示内核版本
- 显示操作系统信息
- 显示公网 IP
- 显示当前默认路由网关

### 2. BBR 配置
- 检查内核版本兼容性
- 配置并启用 BBR 拥塞控制
- 设置队列调度器（FQ/FQ_CoDel）
- 验证 BBR 启用状态

### 3. 网络优化
自动优化以下网络参数：
- 接收/发送缓冲区大小
- TCP 连接超时设置
- TCP TIME-WAIT 复用
- TCP SYN backlog 大小
- TCP SYN cookie 设置
- TCP Fast Open 配置

### 4. 性能测试
- 自动安装 iperf3（如果不存在）
- 提供本地回环测试功能
- 支持远程服务器测试

## 注意事项

1. 建议在执行脚本后重启服务器以确保所有设置生效
2. 如果系统不支持 BBR，脚本会尝试加载必要的内核模块
3. 网络测试部分需要 iperf3，脚本会自动尝试安装
4. 修改系统参数需要 root 权限

## 常见问题

Q: 如何确认 BBR 是否成功启用？  
A: 可以通过以下命令查看：
```bash
sysctl net.ipv4.tcp_congestion_control
```

Q: 为什么要选择 FQ_CoDel？  
A: FQ_CoDel 相比 FQ 能更好地处理缓冲区膨胀问题，特别适合实时性要求高的应用。

## 技术支持

如有问题，请在 GitHub 上提交 Issue：
[https://github.com/suxayii/bbr-fq_codel/issues](https://github.com/suxayii/bbr-fq_codel/issues)

## 许可协议

本项目采用 MIT 许可证
