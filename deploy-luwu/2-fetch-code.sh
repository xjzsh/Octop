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
    # 保证 origin 指向真实仓库（此前可能被改成镜像地址）
    git remote set-url origin "$FORK"
    # 优先直连 GitHub（加速镜像有缓存，可能拉到旧提交），失败再切镜像
    # 注意：clone 用了 --depth 1，浅仓库下 fetch 只更新 FETCH_HEAD 不更新
    # origin/<branch> 引用，因此统一 reset 到 FETCH_HEAD
    if ! timeout 30 git fetch --depth 1 origin "$BRANCH"; then
        echo "    GitHub 直连失败 → 走 ${MIRROR_PREFIX} 加速"
        git remote set-url origin "${MIRROR_PREFIX}/${FORK}"
        git fetch --depth 1 origin "$BRANCH"
        git remote set-url origin "$FORK"
    fi
    git reset --hard FETCH_HEAD
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
