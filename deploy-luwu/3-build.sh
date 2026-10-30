#!/usr/bin/env bash
# =============================================================================
# 构建陆吾AI 镜像（服务器上执行，默认全腾讯云内网源加速）
#   产出: luwu-ai:<TAG>   默认 1.0.3b1
#   内存 <4G 时自动调低前端编译内存
# =============================================================================
set -euo pipefail

TAG="${1:-1.0.3b1}"
SRC="${SRC:-/opt/luwu/src}"

cd "$SRC"

# uv.lock 锁定了 files.pythonhosted.org 直连地址（--frozen 不走镜像源），
# 国内 ECS 直连该 CDN 仅几十 KB/s。阿里云内网镜像路径结构一致，替换后
# sha256 校验不变，可放心加速。
sed -i 's|https://files.pythonhosted.org/packages/|http://mirrors.cloud.aliyuncs.com/pypi/packages/|g' "$SRC/uv.lock"

MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MEM_GB=$(( MEM_KB / 1024 / 1024 ))
EXTRA=()
if [ "$MEM_GB" -lt 4 ]; then
    echo "⚠️  内存 ${MEM_GB}G < 4G，前端编译内存调低为 1024MB（仍可能吃紧，失败就改走本机构建路线 B）"
    EXTRA+=(--build-arg NODE_MAX_OLD_SPACE_SIZE=1024)
fi

export DOCKER_BUILDKIT=1
echo "── 构建镜像 luwu-ai:$TAG（约 10~25 分钟，取决于网络与机器性能）"
docker build \
    -t "luwu-ai:$TAG" \
    -f docker/Dockerfile \
    --build-arg PIP_INDEX_URL=http://mirrors.cloud.aliyuncs.com/pypi/simple \
    --build-arg PIP_TRUSTED_HOST=mirrors.cloud.aliyuncs.com \
    --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
    --build-arg APT_MIRROR=mirrors.cloud.tencent.com \
    ${EXTRA[@]+"${EXTRA[@]}"} \
    .

echo ""
echo "✅ 构建完成: luwu-ai:$TAG"
echo "   下一步: bash 4-deploy.sh"
