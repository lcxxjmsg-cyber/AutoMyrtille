# AutoMyrtille

一键部署 [Myrtille](https://github.com/cedrozor/myrtille)（HTML5 RDP 网关），交互式 CLI 菜单，支持安装/卸载/自定义端口/自签名 HTTPS。

## 一键安装

```powershell
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r 'https://github.com/lcxxjmsg-cyber/AutoMyrtille/blob/main/AutoMyrtille.ps1'"
```

内存运行，无需下载，无需管理员权限预先准备。

## 兼容性

### 服务端（运行此脚本的机器）

| 系统 | 兼容性 |
|------|--------|
| Windows 11 Pro/Enterprise | ✅ 完全支持 |
| Windows 11 Home | ❌ 无 IIS，不支持 |
| Windows 10 Pro/Enterprise | ✅ 完全支持（注意：IIS 默认站点硬限制 10 并发） |
| Windows 10 Home | ❌ 无 IIS，不支持 |
| Windows Server 2022/2019/2016 | ✅ 完全支持 |
| Windows Server 2012 R2 | ✅ 支持 |
| Windows 8.1 Pro | ✅ 支持 |
| 其他 .NET 依赖 | .NET Framework 4.5+（脚本自动安装 4.8） |

### 客户端（访问 RDP 的浏览器）

| 浏览器 | HTML5 模式 | HTML4 兼容模式 |
|--------|-----------|---------------|
| Chrome 90+ | ✅ | ✅ |
| Firefox 90+ | ✅ | ✅ |
| Edge 90+ | ✅ | ✅ |
| Safari 14+ | ✅ | ✅ |
| IE 11 | ❌ | ✅ |
| IE 6–10 | ❌ | ✅ |

HTML5 模式使用 WebSocket，性能更好；HTML4 使用长轮询，兼容老旧系统。

## 功能特性

- **交互式菜单** — 安装/卸载/连接信息查看
- **自定义 HTTP/HTTPS 端口**（默认 11111 / 12345）
- **自签名 HTTPS** — 输入域名自动生成
- **自动检测目标 RDP 端口** — 非 3389 时 URL 自动添加端口号
- **自动适应分辨率** — 无需在 URL 指定宽高，浏览器自动适配
- **下载加速** — 通过 ghproxy.net 代理所有下载
- **断点续装** — 重启后自动恢复安装状态
- **防火墙规则** — 自动开放端口
- **全部卸载** — 一键清理文件/服务/IIS 配置/证书

## 手动运行

```powershell
# 交互模式
.\AutoMyrtille.ps1

# CLI 静默安装
.\AutoMyrtille.ps1 -Install -Domain example.com -HttpPort 11111 -HttpsPort 12345 -RdpPort 3390

# 卸载
.\AutoMyrtille.ps1 -Uninstall
```

## 目录结构

```
AutoMyrtille/
├── AutoMyrtille.ps1   # 主部署脚本
├── README.md
└── plug/
    └── dotNetFx45_Full_setup.exe  # .NET 离线安装包（ghproxy 加速）
```

## Credits

Built on [Myrtille-RDP](https://github.com/cedrozor/myrtille) — HTML5 RDP gateway by cedrozor.
