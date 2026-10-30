#!/usr/bin/env bash
# =============================================================================
# 在服务器上获取 luwu 分支代码 → /opt/luwu/src
#   首次: clone（GitHub 失败自动换 ghfast.top 加速镜像）
#   再次: 更新到 origin/luwu 最新
# =============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/luwu/src}"
FORK="${FORK:-https://github.com/xjzsh/Octop.git}"
BRANCH="${BRANCH:-luwu}"
MIRROR_PREFIX="https://ghfast.top"

cd "$(dirname "$APP_DIR" 2>/dev/null || echo /opt/luwu)"
mkdir -p "$(dirname "$APP_DIR")"

if [ -d "$APP_DIR/.git" ]; then
    echo "── 已有仓库，更新到 origin/$BRANCH 最新"
    cd "$APP_DIR"
    git fetch origin "$BRANCH" || { echo "fetch 失败，尝试加速镜像"; git remote set-url origin "${MIRROR_PREFIX}/${FORK}"; git fetch origin "$BRANCH"; }
    git reset --hard "origin/$BRANCH"
else
    echo "── clone $BRANCH 分支（depth 1）"
    if ! git clone --depth 1 -b "$BRANCH" "$FORK" "$APP_DIR" 2>/dev/null; then
        echo "    GitHub 直连失败 → 走 ${MIRROR_PREFIX} 加速"
        rm -rf "$APP_DIR"
        git clone --depth 1 -b "$BRANCH" "${MIRROR_PREFIX}/${FORK}" "$APP_DIR"
    fi
fi

cd "$APP_DIR"
# .gitattributes 里的 merge=ours 需要仓库级驱动配置（clone 不会带过来）
git config merge.ours.driver true

echo ""
echo "✅ 代码就绪: $APP_DIR ($(git log --oneline -1))"
echo "   下一步: bash 3-build.sh"
