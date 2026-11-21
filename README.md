# reverse-proxy-tools

通用 Nginx + Let's Encrypt 反代管理脚本，不绑定任何面板，任何后端都能反代。

## 脚本

| 脚本 | 用途 |
| --- | --- |
| `install-reverse-proxy.sh` | 一键安装反代：只问域名和后端地址，自动写 Nginx 配置、申请 Let's Encrypt 证书并开启 HTTPS |
| `manage-reverse-proxy.sh` | 反代管理：先列出当前所有反代域名，再选择删除或新增 |

## 安装反代

```bash
bash install-reverse-proxy.sh
```

按提示输入反代域名和后端地址（例如 `127.0.0.1:7001`）。脚本会自动写 Nginx 配置、申请 Let's Encrypt 证书并开启 HTTPS。

注意：后端要填服务实际监听的地址和端口。服务在本机 7001 端口时填 `127.0.0.1:7001`，不要填服务器公网 IP 的 80 端口（那是 Nginx 自己，会反代成死循环）。

## 管理反代

```bash
bash manage-reverse-proxy.sh
```

先显示当前所有反代域名，然后选择：

- `1` 删除一个反代（按编号选，删前再确认一次，配置和证书一起删）
- `2` 新增一个反代（输域名和后端）
- `0` 退出
