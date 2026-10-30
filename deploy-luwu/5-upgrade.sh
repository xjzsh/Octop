#!/usr/bin/env bash
# =============================================================================
# 升级陆吾AI：拉最新 luwu 分支 → 重建镜像 → 滚动重启（数据不丢）
# =============================================================================
set -euo pipefail

TAG="${1:-1.0.3b1}"
SRC="${SRC:-/opt/luwu/src}"
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "── [1/3] 更新代码"
bash "$(dirname "$0")/2-fetch-code.sh"

echo "── [2/3] 重建镜像 luwu-ai:$TAG"
bash "$(dirname "$0")/3-build.sh" "$TAG"

echo "── [3/3] 重建容器"
sed -i "s/^LUWU_VERSION=.*/LUWU_VERSION=$TAG/" /opt/luwu/.env
docker compose -f "$KIT_DIR/docker-compose.luwu.yml" --env-file /opt/luwu/.env up -d

echo ""
echo "✅ 升级完成。旧镜像未删除，回滚: 把 /opt/luwu/.env 的 LUWU_VERSION 改回旧 tag 再跑 4-deploy.sh"
