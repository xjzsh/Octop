#!/usr/bin/env bash
# =============================================================================
# 启动陆吾AI（首次自动生成 .env 与随机管理员密码；可安全重复执行）
# =============================================================================
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/luwu/.env}"
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$ENV_FILE" ]; then
    echo "── 生成配置 $ENV_FILE"
    # 生成强密码：≥8位、含字母和数字、避开易混淆字符
    # （head -c 256 先限量，cut 全量读完，避免管道 SIGPIPE 在 pipefail 下中断脚本）
    PW="$(head -c 256 /dev/urandom | base64 | tr -dc 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789' | cut -c1-14)"
    [ "${#PW}" -eq 14 ] || { echo "❌ 密码生成异常"; exit 1; }
    cat > "$ENV_FILE" <<EOF
# 陆吾AI 部署配置（由 4-deploy.sh 生成）
LUWU_VERSION=1.0.3b1
OCTOP_PORT=8088
OCTOP_BIND=0.0.0.0
OCTOP_ADMIN_USERNAME=admin
OCTOP_DEFAULT_PASSWORD=${PW}
EOF
    chmod 600 "$ENV_FILE"
    CREATED=1
else
    CREATED=0
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

echo "── 启动容器"
docker compose -f "$KIT_DIR/docker-compose.luwu.yml" --env-file "$ENV_FILE" up -d

echo ""
echo "✅ 已启动。访问: http://<服务器IP>:$OCTOP_PORT"
echo "   等待约 20~40 秒完成首次初始化，可用 docker logs -f luwu-ai 观察进度"
if [ "$CREATED" = 1 ]; then
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  管理员账号: $OCTOP_ADMIN_USERNAME"
    echo "║  初始密码:   $OCTOP_DEFAULT_PASSWORD"
    echo "║  （已写入 $ENV_FILE，首次登录后请改密）"
    echo "╚══════════════════════════════════════════════╝"
else
    echo "   登录信息见 $ENV_FILE"
fi
