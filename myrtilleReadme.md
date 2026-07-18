# Myrtille URL 查询参数完整参考文档

> 基于 Myrtille v2.8.0+（[官方源码](https://github.com/cedrozor/myrtille)），覆盖所有 URL 参数、Cookie 控制项、工具栏功能映射。

---

## 基础访问格式

```
http://<网关IP>:<端口>/myrtille/?参数1=值&参数2=值&参数3=值
```

所有参数值**必须 URL 编码**，可用 [url-encode-decode.com](http://www.url-encode-decode.com/) 转码。

---

## 目录

- [一、连接核心参数](#一连接核心参数)
- [二、RemoteApp 专用参数](#二remoteapp-专用参数)
- [三、分辨率与画面显示](#三分辨率与画面显示)
- [四、外设重定向](#四外设重定向)
- [五、界面控制](#五界面控制)
- [六、性能与带宽](#六性能与带宽)
- [七、安全与认证](#七安全与认证)
- [八、高级与会话](#八高级与会话)
- [九、工具栏按钮全映射](#九工具栏按钮全映射)
- [十、Cookie 控制项](#十cookie-控制项)
- [十一、完整示例模板](#十一完整示例模板)
- [十二、注意事项](#十二注意事项)

---

## 一、连接核心参数

| 参数 | 取值示例 | 说明 |
|------|----------|------|
| `server` | `192.168.1.100` / `hostname` | 远程主机地址（支持 `:port` 后缀） |
| `user` | `administrator` | 远程登录用户名 |
| `password` | `P@ssw0rd` | 明文密码（仅内网建议，外网用 `passwordHash`） |
| `passwordHash` | 492 位哈希值 | 加密密码，通过 `GetHash.aspx?password=xxx` 或 `password51.ps1` 生成 |
| `domain` | `MYDOMAIN` / 留空 | 企业 AD 域名，家庭电脑留空 |
| `hostType` | `0` / `1` | 协议：`0` = RDP（默认），`1` = SSH |
| `securityProtocol` | `0` / `1` / `2` / `3` / `4` | RDP 安全层：`0`=自动, `1`=RDP, `2`=TLS, `3`=NLA, `4`=NLA-EXT |
| `program` | `calc.exe` | 自动启动的远程程序路径（RemoteApp，需 RDS 环境） |
| `connect` | `Connect%21` | 触发自动连接（不带此参数则显示登录表单） |
| `__EVENTTARGET` | （空） | ASP.NET WebForms 回发目标，固定为空 |
| `__EVENTARGUMENT` | （空） | ASP.NET WebForms 回发参数，固定为空 |

---

## 二、RemoteApp 专用参数

| 参数 | 取值 | 说明 |
|------|------|------|
| `remoteapp` | `\|\|C:\Windows\System32\cmd.exe` | RemoteApp 程序完整路径，**必须前缀 `\|\|`** |
| `remoteappcmd` | 文本 | 程序启动参数（cmd 留空） |
| `remoteappdir` | `C:\Users\%USERNAME%` | 程序工作目录（一般留空） |
| `program` | `notepad.exe` | 替代 `remoteapp`，简单路径无需 `\|\|` |

> `program` 和 `remoteapp` 功能类似；`remoteapp` 是 Myrtille 自定义扩展参数，`program` 来自官方文档标准语法。

---

## 三、分辨率与画面显示

| 参数 | 取值 | 说明 |
|------|------|------|
| `width` | `1024` / `1920` | 会话宽度（px）；省略则自动检测浏览器分辨率 |
| `height` | `768` / `1080` | 会话高度（px）；省略则自动检测浏览器分辨率 |
| `bpp` | `8` / `16` / `24` / `32` | 色深，`32` = 真彩色 |
| `wallpaper` | `true` / `false` | 显示远程壁纸；默认 `false`（省带宽），设为 `true` 解决桌面空白 |
| `compression` | `on` / `off` | 图像压缩；`off` = 无损渲染壁纸更清晰 |
| `scale` | `true` / `false` | 自动缩放画面适配浏览器窗口 |
| `rendering` | `html5` / `html4` | 渲染模式；`html4` 兼容老旧浏览器（IE6+） |

---

## 四、外设重定向

| 参数 | 取值 | 对应 RDP 配置 | 说明 |
|------|------|---------------|------|
| `clipboard` | `true` / `false` | `redirectclipboard:i:1` | 双向剪贴板，默认 `true` |
| `drives` | `true` / `false` | `redirectdrives:i:1` | 本地磁盘映射（文件上传） |
| `printers` | `true` / `false` | `redirectprinters:i:0` | 打印机重定向 |
| `comports` | `true` / `false` | `redirectcomports:i:0` | 串口重定向 |
| `smartcards` | `true` / `false` | `redirectsmartcards:i:0` | 智能卡 |
| `audio` | `true` / `false` | `audiomode:i:0` | 远程音频播放 |
| `mic` | `true` / `false` | — | 麦克风重定向 |

---

## 五、界面控制

| 参数 | 取值 | 说明 |
|------|------|------|
| `toolbar` | `true` / `false` | **隐藏顶部工具栏**（iframe 嵌入必加 `false`） |
| `stat` | `true` / `false` | 显示连接性能统计面板（延迟/带宽/帧率） |
| `debug` | `true` / `false` | 显示调试日志覆盖层 |
| `reconnect` | `true` / `false` | 断线自动重连 |
| `rightclick` | `true` / `false` | 拦截浏览器右键 → 转发远程桌面右键 |
| `vswipe` | `true` / `false` | 触屏滑动拖拽（电脑端建议 `false`） |
| `autofit` | `true` / `false` | 自动适应窗口大小 |

---

## 六、性能与带宽

| 参数 | 取值 | 说明 |
|------|------|------|
| `bandwidth` | `0` ~ 数字（Mbps） | 带宽上限；`0` = 不限速（滑块最右端） |
| `imagequality` | `1` ~ `100` | 图像压缩质量，`100` = 最高清 |
| `imagequantity` | `1` ~ `100` | 图像丢弃率（越低丢帧越多，适合低带宽） |
| `mouseMoveSamplingRate` | `1` ~ `100` | 鼠标移动采样率（越低越省带宽） |
| `bufferEnabled` | `true` / `false` | 用户输入缓冲（高延迟建议开启） |
| `keepAspectRatio` | `true` / `false` | 保持画面宽高比 |

---

## 七、安全与认证

| 参数 | 取值 | 说明 |
|------|------|------|
| `nla` | `true` / `false` | 网络级认证，默认 `true` |
| `ignorecert` | `true` / `false` | 忽略远程 RDP 证书错误 |
| `mfaPassword` | 6 位数字 | MFA 一次性验证码 |
| `clientIPTracking` | `true` / `false` | IP 变更时断开会话（反劫持） |

---

## 八、高级与会话

| 参数 | 取值 | 说明 |
|------|------|------|
| `vmGuid` | GUID | 直连 Hyper-V 虚拟机（格式：`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`） |
| `vmEnhancedMode` | `checked` | Hyper-V 增强模式（剪贴板/打印机重定向） |
| `gid` | GUID | 加入共享会话（访客邀请链接） |
| `cid` | GUID | 连接服务 ID（隐藏凭据，需自建 REST API） |
| `fid` | 字符串 | iframe 内嵌模式 ID，避免 Cookie 冲突 |
| `mode` | `admin` | 进入本地主机管理面板 |
| `SI` / `SD` / `SK` | 字符串 | 企业模式一次性会话 URL |
| `autoopen` | `true` / `false` | 打开 URL 自动连接（无需点击 Connect） |
| `disconnectonclose` | `true` / `false` | 关闭标签页自动断开 RDP 会话 |

---

## 九、工具栏按钮全映射

### 第一行（状态开关）

| 按钮 | URL 参数 | 说明 |
|------|----------|------|
| Stat | `stat=true` | 实时带宽/帧率/延迟统计面板 |
| Debug | `debug=true` | FreeRDP 底层通信日志 |
| HTML5 | — | 渲染模式指示器（固定 ON） |
| Scale | `scale=true` | 画面自适应缩放 |
| Reconnect | `reconnect=true` | 断网自动重连 |
| Text | — | 批量文本粘贴输入框 |
| Keyboard | — | 虚拟触屏软键盘 |

### 第二行（交互功能）

| 按钮 | URL 参数 | 说明 |
|------|----------|------|
| Clipboard | `clipboard=true` | 剪贴板双向同步 |
| Files | `drives=true` | 本地文件上传远程磁盘 |
| Ctrl+Alt+Del | — | 发送系统安全键 |
| Right-Click | `rightclick=true` | 拦截浏览器右键 |
| VSwipe | `vswipe=true` | 触屏滑动拖拽 |
| Share | — | 生成临时会话分享链接 |
| Disconnect | — | 断开当前会话 |

### 蓝色带宽滑块

`bandwidth=数字`：`0` = 不限速（内网推荐），`2` = 2Mbps 限速（外网省带宽）

---

## 十、Cookie 控制项

以下由客户端 Cookie 控制，而非 URL 参数。可在 F12 控制台设置：

```javascript
// 开启连接统计覆盖层
document.cookie = 'stat=1';

// 开启调试日志
document.cookie = 'debug=1';

// 强制 HTML4 兼容模式（长轮询，不使用 WebSocket）
document.cookie = 'browser=1';

// 隐藏工具栏
document.cookie = 'toolbar=0';
```

| Cookie 名 | 值 | 说明 |
|-----------|-----|------|
| `stat` | `1` / `0` | 连接统计面板 |
| `debug` | `1` / `0` | 调试日志 |
| `browser` | `1` / `0` | `1` = HTML4 兼容模式 |
| `toolbar` | `1` / `0` | 工具栏显隐 |

---

## 十一、完整示例模板

### 模板 1：RemoteApp（cmd，隐藏工具栏，内嵌用）

```
http://网关IP:端口/myrtille/?__EVENTTARGET=&__EVENTARGUMENT=&server=192.168.1.100&user=coldnight&remoteapp=||C:\Windows\System32\cmd.exe&width=1024&height=768&bpp=32&clipboard=true&drives=true&toolbar=false&scale=true&rightclick=true&bandwidth=0&ignorecert=true&connect=Connect%21
```

### 模板 2：完整桌面带壁纸

```
http://网关IP:端口/myrtille/?__EVENTTARGET=&__EVENTARGUMENT=&server=192.168.1.100&user=coldnight&passwordHash=HASH_VALUE&width=1920&height=1080&bpp=32&wallpaper=true&compression=off&toolbar=true&bandwidth=0&ignorecert=true&connect=Connect%21
```

### 模板 3：SSH 连接

```
http://网关IP:端口/myrtille/?__EVENTTARGET=&__EVENTARGUMENT=&server=192.168.1.200&hostType=1&user=root&passwordHash=HASH_VALUE&width=1024&height=768&connect=Connect%21
```

### 模板 4：Hyper-V 虚拟机

```
http://网关IP:端口/myrtille/?__EVENTTARGET=&__EVENTARGUMENT=&server=HYPERV-HOST&vmGuid=12345678-1234-1234-1234-123456789abc&vmEnhancedMode=checked&user=administrator&passwordHash=HASH_VALUE&width=1024&height=768&connect=Connect%21
```

### 模板 5：纯内网明文（不使用 hash）

```
http://网关IP:端口/myrtille/?__EVENTTARGET=&__EVENTARGUMENT=&server=TARGET&user=admin&password=123456&width=1024&height=768&connect=Connect%21
```

---

## 十二、注意事项

1. **密码安全**：公网 URL 不要明文写 `password=`，使用 `passwordHash`（通过 `https://myrtille/GetHash.aspx?password=xxx` 生成）
2. **壁纸空白修复**：组合 `wallpaper=true&compression=off&bandwidth=0`
3. **iframe 嵌入**：必加 `toolbar=false&scale=true&rightclick=true`
4. **RemoteApp 路径**：`remoteapp` 参数必须前缀 `||`，否则失败
5. **布尔值**：统一小写 `true` / `false`
6. **URL 编码**：含中文/特殊字符的参数值必须 URL 编码（如空格 = `%20`，`!` = `%21`）
7. **参数来源**：本文档综合 Myrtille 官方 `DOCUMENTATION.md`、`Default.aspx.cs`、`js/config.js` 及 `myrtille.js` 源码整理

---

## 参考来源

- 官方文档：https://github.com/cedrozor/myrtille/blob/master/DOCUMENTATION.md
- 官网：https://myrtille.io
- Wiki：https://sourceforge.net/p/myrtille/wiki/Usage/
- 自动连接说明：https://myrtille.io/#connect-from-url

---

*文档基于 Myrtille v2.8.0+ 编写，覆盖官方源码中所有 URL 参数及客户端功能。*
