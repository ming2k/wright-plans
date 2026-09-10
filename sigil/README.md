# Sigil (Secret Service Provider)

## Overview

Sigil 是 Atrium / Theseus Linux 生态中的现代工业级 Secret Service 提供者与 PAM 自动解锁模块，全面遵循 Freedesktop Secret Service 规范 (`org.freedesktop.secrets`)。

基于零感知信封密钥加密架构（ADR-0002）与原生 Optics (`flux`/`lens`/`iris`) UI 栈构建，不依赖 GTK4 / Libadwaita。在 v1.3.0+ 体系下，Sigil 完全作为原生桌面基础设施守护进程运作，无需任何手动命令行管理介入，完全兼容标准 `secret-tool`、浏览器及 Desktop Portals。

---

## 产物清单

| 路径 | 类型 | 说明 |
|---|---|---|
| `/usr/bin/sigil` | 守护进程 | Secret Service 核心服务后台 |
| `/usr/bin/sigil-prompter` | GUI 交互弹窗 | 基于 Optics (lens/iris) 的解锁提示框 |
| `/usr/lib/security/pam_sigil.so` | PAM 模块 | 登录、锁屏唤醒与改密同步的纯内存套接字模块 |
| `/usr/lib/systemd/user/sigil.service` | systemd 单元 | 用户级后台服务配置 |
| `/usr/lib/systemd/user/sigil.socket` | systemd 单元 | 按需套接字激活配置 |
| `/usr/share/dbus-1/services/org.freedesktop.secrets.service` | D-Bus 激活 | 声明式会话总线激活文件 |
| `/usr/share/licenses/sigil/LICENSE` | 许可证 | MIT License 声明 |

---

## 安装后引导步骤

### 1. 服务启动与开机自启

Sigil 作为 systemd 用户级服务运行，安装完成后执行：

```bash
# 重新加载 systemd 用户单元
systemctl --user daemon-reload

# 启用并立即启动服务（或 socket 激活）
systemctl --user enable --now sigil.service sigil.socket

# 验证服务状态与 D-Bus 总线归属
systemctl --user status sigil.service
busctl --user status org.freedesktop.secrets
```

---

### 2. PAM 全生命周期集成（推荐）

在系统认证栈中集成 `pam_sigil.so`，可获得全自动桌面级体验：

#### A. 登录与改密同步（`/etc/pam.d/system-login` 或 `/etc/pam.d/login`）

在相应小节（通常在 `pam_unix.so` 之后）添加：
```pam
auth       optional   pam_sigil.so
password   optional   pam_sigil.so
session    optional   pam_sigil.so
```
- **首次登录**：自动以当次系统密码完成 Vault 开荒初始化。
- **改密同步**：用户通过 `passwd` 更改密码时，`password` 钩子自动原子重加密凭据库，避免密码脱节。

#### B. 锁屏唤醒自动解锁

在锁屏程序的 PAM 文件中添加：
- **Tessera Lock**: `/etc/pam.d/tessera-lock`
- **Swaylock**: `/etc/pam.d/swaylock`
- **Hyprlock**: `/etc/pam.d/hyprlock`
- 添加配置：
  ```pam
  auth       optional   pam_sigil.so
  session    optional   pam_sigil.so
  ```

> **安全说明**：Sigil 采用纯内存 IPC 通信协议，PAM 认证成功后通过私有 Unix 域套接字安全向 daemon 传递临时口令，磁盘上（包括 `/run/user`）绝不落地任何明文 token。屏幕锁定期间，主密钥在物理内存中彻底抹除（zeroize）。

---

### 3. 避免 D-Bus 冲突（排查与解决）

D-Bus `org.freedesktop.secrets` 在单个用户会话中**只能有一个拥有者**。如果系统之前安装了 GNOME Keyring 或旧版 WSSP，会导致总线争用：

```bash
# 屏蔽 GNOME Keyring 守护进程
systemctl --user disable --now gnome-keyring-daemon.service 2>/dev/null || true
systemctl --user mask gnome-keyring-daemon.service 2>/dev/null || true

# 检查是否有其它单元声明了相同总线名称
grep -rl 'BusName=org.freedesktop.secrets' /usr/lib/systemd/user/ ~/.config/systemd/user/ 2>/dev/null
```

---

### 4. 凭据交互与查询

无需专用私有 CLI 工具，使用标准 Freedesktop `secret-tool` 即可进行检索与测试：

```bash
# 查询凭据
secret-tool lookup service testapp username alice

# 存储凭据
secret-tool store --label="Test Secret" service testapp username alice
```
