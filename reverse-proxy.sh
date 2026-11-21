#!/bin/bash
# 反代管理：列出当前反代域名，选择删除或新增
# 用法：bash manage-reverse-proxy.sh

SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"

# 列出当前所有反代域名（从配置文件名提取）
list_domains() {
    local d
    for f in "$SITES_AVAILABLE"/reverse-proxy-*; do
        [ -e "$f" ] || continue
        d=$(basename "$f")
        echo "${d#reverse-proxy-}"
    done
}

# 新增一个反代（复用 install-reverse-proxy.sh 的逻辑）
add_proxy() {
    local domain backend backend_host backend_port scheme
    read -rp "反代域名（如 panel.example.com）: " domain
    [ -n "$domain" ] || { echo "域名不能为空"; return; }
    read -rp "后端地址（如 127.0.0.1:7001）: " backend
    [ -n "$backend" ] || { echo "后端不能为空"; return; }

    # 后端归一化：去掉 scheme、末尾斜杠，无端口默认 80
    backend="${backend%/}"
    if [[ "$backend" =~ ^https?:// ]]; then
        scheme="${backend%%://*}"
        backend="${backend#*://}"
    else
        scheme="http"
    fi
    if [[ "$backend" == *:* ]]; then
        backend_host="${backend%:*}"
        backend_port="${backend##*:}"
    else
        backend_host="$backend"
        backend_port="80"
    fi
    backend="$scheme://$backend_host:$backend_port"

    local conf="$SITES_AVAILABLE/reverse-proxy-$domain"
    cat > "$conf" <<EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass $backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
EOF
    ln -sf "$conf" "$SITES_ENABLED/reverse-proxy-$domain"
    if ! nginx -t; then
        echo "nginx 配置有问题，停止"
        rm -f "$conf" "$SITES_ENABLED/reverse-proxy-$domain"
        return
    fi
    systemctl reload nginx

    # 证书
    if ! command -v certbot >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq python3-certbot-nginx
    fi
    certbot --nginx -d "$domain" --non-interactive --agree-tos -m "admin@$domain" --redirect || echo "证书申请失败，请检查域名解析是否指向本机"
    nginx -t && systemctl reload nginx || echo "提示：nginx 重载失败，请手动检查"
    echo "反代已新增：https://$domain -> $backend"
}

# 删除一个反代：先列出当前域名，再选编号
delete_proxy() {
    local domains=()
    local d
    while IFS= read -r d; do
        [ -n "$d" ] && domains+=("$d")
    done < <(list_domains)

    if [ "${#domains[@]}" -eq 0 ]; then
        echo "当前没有任何反代"
        return
    fi

    echo "当前反代域名："
    local i
    for i in "${!domains[@]}"; do
        echo "  $((i+1))) ${domains[$i]}"
    done
    echo "  0) 取消"
    local choice
    read -rp "输入编号删除（0 取消）: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -eq 0 ] || [ "$choice" -gt "${#domains[@]}" ]; then
        echo "已取消"
        return
    fi
    local domain="${domains[$((choice-1))]}"
    read -rp "确认删除 $domain？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消"
        return
    fi
    rm -f "$SITES_ENABLED/reverse-proxy-$domain" "$SITES_AVAILABLE/reverse-proxy-$domain"
    certbot delete --cert-name "$domain" --non-interactive 2>/dev/null || true
    nginx -t && systemctl reload nginx || echo "提示：nginx 重载失败，请手动检查"
    echo "反代 $domain 已删除"
}

# 主菜单
while true; do
    echo ""
    echo "=== 反代管理 ==="
    echo "当前反代："
    local cur
    cur=$(list_domains)
    if [ -z "$cur" ]; then
        echo "  （无）"
    else
        echo "$cur" | sed 's/^/  /'
    fi
    echo ""
    echo "  1) 删除一个反代"
    echo "  2) 新增一个反代"
    echo "  0) 退出"
    local op
    read -rp "选择: " op
    case "$op" in
        1) delete_proxy ;;
        2) add_proxy ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
done
