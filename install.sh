#!/usr/bin/env bash
set -euo pipefail

METHOD="2022-blake3-aes-128-gcm"
SERVICE="ss-rust"
CONF_DIR="/etc/shadowsocks-rust"
CONF_FILE="$CONF_DIR/config.json"
BIN="/usr/local/bin/ssserver"

uninstall() {
  echo "==> 卸载 Shadowsocks-2022..."
  systemctl disable --now $SERVICE || true
  rm -f /etc/systemd/system/$SERVICE.service
  rm -rf "$CONF_DIR"
  rm -f "$BIN"
  systemctl daemon-reload
  echo "✅ 已卸载完成"
  exit 0
}

if [[ "${1:-}" == "uninstall" ]]; then
  uninstall
fi

# Root 检查
[[ $EUID -ne 0 ]] && { echo "请用 root 运行"; exit 1; }

apt update
apt install -y curl wget xz-utils tar simple-obfs qrencode || true

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ASSET="x86_64-unknown-linux-gnu.tar.xz" ;;
  aarch64|arm64) ASSET="aarch64-unknown-linux-gnu.tar.xz" ;;
  *) echo "不支持架构: $ARCH"; exit 1 ;;
esac

DL=$(curl -fsSL https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
   | grep -oE "https://[^\" ]+/${ASSET}" | head -n1)
TMP=$(mktemp /tmp/ssrust.XXXXXX.tar.xz)
curl -fsSL "$DL" -o "$TMP"
tar -xJf "$TMP" -C /usr/local/bin --strip-components=1 ssserver
chmod +x $BIN

# 随机端口 & 密码
PORT=$(( (RANDOM % 45536) + 20000 ))
PASS=$(openssl rand -hex 16)

mkdir -p "$CONF_DIR"
cat >"$CONF_FILE" <<EOF
{
  "server": "0.0.0.0",
  "server_port": $PORT,
  "password": "$PASS",
  "method": "$METHOD",
  "plugin": "obfs-server",
  "plugin_opts": "obfs=http",
  "mode": "tcp_and_udp"
}
EOF

cat >/etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=Shadowsocks-Rust 2022 + obfs
After=network.target
[Service]
ExecStart=$BIN -c $CONF_FILE
Restart=always
User=nobody
LimitNOFILE=51200
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now $SERVICE

IP=$(curl -4fsSL ifconfig.me || hostname -I | awk '{print $1}')
RAW="$METHOD:$PASS"
B64=$(echo -n "$RAW" | base64 | tr '+/' '-_' | tr -d '=')
URI="ss://${B64}@${IP}:${PORT}?plugin=obfs-local%3Bobfs%3Dhttp#SS2022"

echo "===================================="
echo "✅ 安装完成"
echo "地址: $IP"
echo "端口: $PORT"
echo "密码: $PASS"
echo "方法: $METHOD"
echo "插件: obfs-local;obfs=http"
echo "链接: $URI"
echo "===================================="
command -v qrencode >/dev/null && qrencode -t ANSIUTF8 "$URI" || true
