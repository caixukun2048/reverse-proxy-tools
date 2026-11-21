# reverse-proxy-tools

通用 Nginx 反代管理，一个命令搞定新增和删除。

## 一行运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/caixukun2048/reverse-proxy-tools/main/reverse-proxy.sh)
```

跑起来先列出当前所有反代域名，再选：

- `1` 删除（按编号选，删前确认，配置和证书一起删）
- `2` 新增（输域名和后端，如 `127.0.0.1:7001`）
- `0` 退出

后端填服务实际监听的地址，不要填服务器公网 IP 的 80 端口，那是 Nginx 自己。
