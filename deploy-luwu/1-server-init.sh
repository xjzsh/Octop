#!/usr/bin/env bash
# =============================================================================
# 陆吾AI 服务器初始化（CentOS 7.x，root 执行，只需跑一次，可安全重复）
#   1. yum 源指向 vault.centos.org（CentOS 7 已 EOL）
#   2. 安装 Docker CE + compose 插件（阿里云源）
#   3. 配置国内镜像加速 + 日志轮转
#   4. 防火墙放行 8088、SELinux 调整
# =============================================================================
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "❌ 请用 root 运行: sudo bash $0"; exit 1; }
. /etc/os-release
case "${VERSION_ID:-}" in
    7*) ;;
    *) echo "⚠️  本脚本为 CentOS 7 编写（当前 ${VERSION_ID:-?}），8+ 请自行调整";;
esac

echo "── [1/5] yum 源 → vault.centos.org"
sed -i.bak -e 's|^mirrorlist=|#mirrorlist=|g' \
           -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
           /etc/yum.repos.d/CentOS-*.repo
yum clean all >/dev/null
yum makecache fast >/dev/null 2>&1 || yum makecache >/dev/null
echo "    OK"

echo "── [2/5] 安装 Docker CE（阿里云源）"
yum install -y yum-utils git curl >/dev/null
if ! yum list installed docker-ce >/dev/null 2>&1; then
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
docker --version && docker compose version

echo "── [3/5] Docker 镜像加速 + 日志轮转"
mkdir -p /etc/docker
# 注：公共加速镜像时效性强，若构建时拉取基础镜像超时，请替换此列表
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://hub.rat.dev"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}
EOF
systemctl daemon-reload
systemctl enable --now docker

echo "── [4/5] 防火墙 / SELinux"
if systemctl is-active firewalld >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=8088/tcp >/dev/null
    firewall-cmd --reload >/dev/null
    echo "    firewalld 已放行 8088"
else
    echo "    firewalld 未运行，跳过（云服务器请确认安全组已放行 8088）"
fi
# SELinux enforcing 会拦截容器写 bind mount，调成 permissive 并持久化
if command -v getenforce >/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
    setenforce 0
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    echo "    SELinux → permissive（重启后仍生效）"
fi

echo "── [5/5] 建目录"
mkdir -p /opt/luwu/data /opt/luwu/backup /opt/luwu-kit
echo ""
echo "✅ 初始化完成。下一步:"
echo "   有独立数据盘 → bash 1b-mount-data-disk.sh"
echo "   然后把代码放到服务器 → bash 2-fetch-code.sh（走路线 B 时直接 bash 4-deploy.sh）"
