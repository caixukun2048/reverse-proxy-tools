#!/bin/bash
#
# 通用反代一键脚本（Nginx + Let's Encrypt）
# ============================================================
# 不针对任何面板/程序：给一个域名和一个后端地址，就配好 HTTPS 反代。
# 适用：面板、网站、Web 应用、API 等任何跑在某个端口上的 HTTP 服务。
#
# 用法（用 root 登录服务器后）：
#   bash install-reverse-proxy.sh [域名] [后端地址]
#   不传参数也行，脚本会提示你输入（只问两样）：
#     反代域名   例如 panel.example.com
#     后端地址   IP:端口，例如 127.0.0.1:8080（不写端口默认 80）
#                本机服务就写 127.0.0.1:端口，别的服务器就写它的 IP:端口
#   域名要先做好 A 记录指向这台服务器，安全组放行 80/443。
#   证书邮箱默认用 admin@<域名>，只用来收过期提醒。
#
set -euo pipefail

DOMAIN="${1:-}"
BACKEND="${2:-}"

# 提示输入（只问两样）
if [ -z "$DOMAIN" ] && [ -t 0 ]; then
  read -r -p "请输入反代域名（例如 panel.example.com）: " DOMAIN
fi
if [ -z "$BACKEND" ] && [ -t 0 ]; then
  read -r -p "请输入后端地址（IP:端口，例如 127.0.0.1:8080，不写端口默认 80）: " BACKEND
fi

[ -z "$DOMAIN" ] && { echo "错误：没给域名，装不了。"; exit 1; }
[ -z "$BACKEND" ] && { echo "错误：没给后端地址，装不了。"; exit 1; }

[ "$(id -u)" -ne 0 ] && { echo "请用 root 运行这个脚本"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

# 后端地址标准化
BACKEND_SCHEME="http"
if [[ "$BACKEND" == https://* ]]; then
  BACKEND_SCHEME="https"
fi
BACKEND="${BACKEND#http://}"
BACKEND="${BACKEND#https://}"
BACKEND="${BACKEND%/}"
if [[ "$BACKEND" != *:* ]]; then
  BACKEND="$BACKEND:80"
fi
BACKEND_URL="$BACKEND_SCHEME://$BACKEND"

echo "反代域名：$DOMAIN"
echo "后端地址：$BACKEND_URL"

# 提醒 DNS（不强求，certbot 拿不到会自己报错）
SERVER_IP="$(curl -4 -s --max-time 5 https://ifconfig.me || true)"
if [ -n "$SERVER_IP" ]; then
  RESOLVED="$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1)"
  if [ "$RESOLVED" != "$SERVER_IP" ]; then
    echo "提醒：$DOMAIN 现在解析到 ${RESOLVED:-（无记录）}，不是本机 $SERVER_IP。"
    echo "请先把域名的 A 记录指到本机，否则 certbot 拿不到证书。"
  fi
fi

# 装 Nginx + certbot
apt-get update -y
apt-get install -y nginx python3-certbot-nginx
# 删掉默认站点，避免抢 80 端口
rm -f /etc/nginx/sites-enabled/default

# 写反代配置
cat > /etc/nginx/sites-available/reverse-proxy-"$DOMAIN" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass $BACKEND_URL;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        client_max_body_size 50m;
    }
}
EOF
ln -sf /etc/nginx/sites-available/reverse-proxy-"$DOMAIN" /etc/nginx/sites-enabled/reverse-proxy-"$DOMAIN"
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# 拿证书并自动配 HTTPS
CERT_EMAIL="admin@$DOMAIN"
if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$CERT_EMAIL" --redirect; then
  echo ""
  echo "============================================================"
  echo " 反代完成！"
  echo "============================================================"
  echo " 访问地址：  https://$DOMAIN"
  echo " 后端地址：  $BACKEND_URL"
  echo " 配置文件：  /etc/nginx/sites-available/reverse-proxy-$DOMAIN"
  echo " 证书邮箱：  $CERT_EMAIL（只用来收过期提醒）"
  echo "============================================================"
else
  echo ""
  echo "警告：certbot 拿证书失败（可能是域名没解析到本机，或 80 端口没对外放行）。"
  echo "反代先用 HTTP 跑着：http://$DOMAIN"
  echo "放行端口、解析生效后手动执行：certbot --nginx -d $DOMAIN"
fi
