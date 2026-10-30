# 陆吾AI（Octop 白标）CentOS 7.5 Docker 部署方案

> 目标服务器：CentOS 7.5（已 EOL），Docker 部署，数据持久化在宿主机
> 镜像来源：你的 fork `xjzsh/Octop` 的 `luwu` 分支（自带陆吾品牌资产）

## 总体流程

```
[服务器初始化]              [挂数据盘]                [取代码]              [构建镜像]           [启动]
1-server-init.sh  →   1b-mount-data-disk.sh  →  2-fetch-code.sh  →   3-build.sh    →    4-deploy.sh
 vault源+Docker         /opt/luwu 挂到数据盘       clone luwu分支        前端+后端编译         compose 起容器
 镜像加速               数据+备份都在盘上          (GitHub 或离线包)     约 10~25 分钟        数据落在数据盘
```

> 有独立数据盘就多跑一步 `1b-mount-data-disk.sh`；没有数据盘可跳过，数据直接放系统盘 `/opt/luwu/data`。

日常升级只需 `5-upgrade.sh`（拉新代码 → 重建镜像 → 滚动重启）。

---

## 🔄 日常更新操作（每次更新看这里，单独一块）

> 前提：本地代码已推送到 GitHub `xjzsh/Octop` 的 `luwu` 分支。

### ① 登录服务器

```bash
ssh root@<服务器IP>
```

### ② 更新（一条命令，最常用）

```bash
bash /root/deploy-luwu/5-upgrade.sh
```

它会自动完成三步：拉取 luwu 分支最新代码 → 重建镜像 → 滚动重启容器。
**业务数据不受影响**（都在宿主机 `/opt/luwu/data`），全程约 10~25 分钟。

升级完成后浏览器访问 `http://<服务器IP>:8088` 确认版本即可。

### ③ 带版本号更新（可选）

默认升级仍用 `1.0.3b1` 标签。要发布新版本号：

```bash
bash /root/deploy-luwu/5-upgrade.sh 1.0.4
```

### ④ 更新过程中的常用命令

```bash
# 另开一个窗口实时看构建/运行日志
bash /root/deploy-luwu/3-build.sh 2>&1 | tail -f   # 单独重建时看进度
docker logs -f luwu-ai                             # 看容器运行日志

# 查看容器状态（等 health 变 healthy）
docker ps
```

### ⑤ 其他日常操作

| 场景 | 命令 |
|---|---|
| 只重启服务（不更新代码） | `bash /root/deploy-luwu/4-deploy.sh` |
| 回滚到旧版本 | 把 `/opt/luwu/.env` 里 `LUWU_VERSION` 改回旧 tag（如 `1.0.3b1`），再跑 `4-deploy.sh`；旧镜像默认不删除 |
| 查看管理员密码 | `grep OCTOP_DEFAULT_PASSWORD /opt/luwu/.env` |
| 备份数据 | 见下方「数据与备份」 |

### ⑥ 更新失败怎么办

- **构建失败**：直接重跑 `5-upgrade.sh`，Docker 有层缓存，已完成的步骤不会重来。
- **新容器起不来**：`docker logs luwu-ai` 看报错；急着恢复就按上面「回滚」操作先回旧版本。
- **GitHub 拉取失败**：`2-fetch-code.sh` 会自动切 ghfast.top 加速镜像；仍失败可稍后重试或走路线 B 传离线镜像。

---

## 服务器规格要求

### 1. 如果要在服务器上构建镜像（路线 A）

| 项目 | 最低 | 推荐 | 说明 |
|---|---|---|---|
| CPU | 2 核 | 4 核 | 前端 tsc+vite 编译是单核密集，2 核大概 20~30 分钟 |
| **内存** | **4 G** | **8 G** | ⚠️ 硬门槛。前端编译峰值 2~3G，低于 4G 极易 `Killed`（OOM） |
| 磁盘 | 20 G 空余 | 40 G+ | 镜像 ~2.5G + 构建缓存 ~6G + 数据 |
| 磁盘类型 | 任何 | SSD | 编译和 SQLite 都吃 IO |

> 内存只有 2G 的机器：**不要硬上**，改走路线 B（本机 Docker 构建 → `docker save` 传镜像），服务器只负责运行。

### 2. 只运行镜像（路线 B 或构建完成后）

| 项目 | 最低 | 推荐 | 说明 |
|---|---|---|---|
| CPU | 2 核 | 4 核 | 多智能体并发时会跑工具调用、代码执行 |
| 内存 | 2 G | **4 G** | 单用户轻量用 2G 能跑；多用户/长会话建议 4G+ |
| 磁盘 | 15 G | 30 G+ | 数据会随会话、知识库、头像、日志增长 |

### 3. 系统与内核

- **CentOS 7.5**：可用。注意三个已知前提：
  - yum 源已 EOL，必须指向 `vault.centos.org`（`1-server-init.sh` 已处理）
  - Docker CE 在 el7 上最高只到 **24.x**，够用但不再更新
  - **overlay2 需要 xfs 的 ftype=1**，老镜像装的系统可能是 ftype=0。检查：`xfs_info / | grep ftype`，若是 0 需在 `daemon.json` 里改用 `"storage-driver": "devicemapper"`（慢）或重装系统
- 其他可选系统（Docker 支持更好）：Ubuntu 20.04/22.04 LTS、Debian 11/12、Rocky 9、openEuler 22.03、麒麟 V10

### 4. 网络

| 方向 | 要求 |
|---|---|
| 出网 | 能访问阿里云 yum 源 + Docker Hub（或镜像加速）；**内网隔离环境**走路线 B 离线镜像 |
| 入网 | 放行业务端口（默认 8088）：云厂商**安全组** + 系统防火墙两处都要 |
| 带宽 | 1 Mbps 起步够用（纯文本对话）；常传文件/图片建议 5 Mbps+ |

> 服务器**不需要**访问 GitHub——代码可以打包带过去，构建也可在本机完成。

### 5. 软件依赖

只有一个：**Docker**（含 compose 插件），由 `1-server-init.sh` 自动安装。不需要在宿主机装 Python、Node、数据库。

### 6. 规模与配置对照

| 使用场景 | 建议配置 | 数据库 |
|---|---|---|
| 试用 / 1~3 人 | 2C4G，40G | SQLite（默认） |
| 小团队 / 5~20 人 | 4C8G，100G SSD | 建议迁 PostgreSQL |
| 部门级 / 20 人以上 | 8C16G，200G SSD，前面挂 nginx | PostgreSQL + 定期备份 |

## 磁盘规划（有独立数据盘时）

```
/dev/vda  系统盘 40G   →  /            系统 + Docker 引擎 + 镜像与构建缓存（约 10G）
/dev/vdb  数据盘 100G  →  /opt/luwu    陆吾AI 全部业务数据 + 备份
                            ├── data/     octop.db、智能体工作区、知识库、头像、日志
                            └── backup/   每日备份包
```

好处：重建镜像、清 Docker 缓存、甚至重装系统，**业务数据都不受影响**；以后换机器只需把这块盘挂过去。

`1b-mount-data-disk.sh` 做的事：识别空盘 → ext4 格式化（`-m 1` 只留 1% 给 root）→ 按 UUID 写入 `/etc/fstab` → `mount -a` 验证。

**为什么用 UUID 而不是 `/dev/vdb`**：云盘设备名在重启、挂载顺序变化时可能漂移，UUID 唯一且稳定。
**为什么加 `nofail`**：万一数据盘出问题（未挂上/损坏），系统仍能正常启动，不会卡在 emergency mode 起不来。
**为什么 `-m 1`**：ext4 默认给 root 预留 5%（100G 盘吃掉 5G），改 1% 省下 4G。

## 前提检查（在服务器上）

| 项目 | 要求 | 检查命令 |
|---|---|---|
| 内存 | 构建 ≥4G；仅运行 ≥2G | `free -h` |
| 磁盘 | 构建 ≥20G 空余；仅运行 ≥15G | `df -h` |
| 磁盘文件系统 | xfs 需 ftype=1（overlay2 前提） | `xfs_info / \| grep ftype` |
| 出网 | 能访问 mirrors.aliyun.com | `curl -m5 -I https://mirrors.aliyun.com` |

## 两条路线，按服务器网络选

### 路线 A：服务器直接 clone GitHub（服务器能通 GitHub 或接受加速镜像）

```bash
# 1. 上传整个 deploy-luwu 目录到服务器（在你 Windows 终端执行）
scp -r D:/pythonWorkspace/Octop-main/deploy-luwu root@<服务器IP>:/opt/luwu-kit

# 2. 到服务器上依次执行
cd /opt/luwu-kit
bash 1-server-init.sh      # 只需跑一次：vault源 + Docker + 加速 + 防火墙
bash 1b-mount-data-disk.sh # 有数据盘时跑：格式化 ext4 并挂到 /opt/luwu（二次确认，绝不碰系统盘）
bash 2-fetch-code.sh       # clone luwu 分支（自动尝试 GitHub → ghfast 加速镜像）
bash 3-build.sh            # 构建镜像 luwu-ai:1.0.3b1
bash 4-deploy.sh           # 生成 .env（含随机管理员密码）并启动
```

### 路线 B：服务器连 GitHub 都不通 → 本机构建，传镜像上服务器

```bash
# 在你 Windows 本机（需要装 Docker Desktop）：
cd D:/pythonWorkspace/Octop-main
docker build -f docker/Dockerfile -t luwu-ai:1.0.3b1 .
docker save luwu-ai:1.0.3b1 | gzip > luwu-ai-1.0.3b1.tar.gz

# 传到服务器并加载
scp luwu-ai-1.0.3b1.tar.gz root@<服务器IP>:/opt/luwu-kit/
# 服务器上：
docker load < /opt/luwu-kit/luwu-ai-1.0.3b1.tar.gz
```

> 路线 B 时跳过 `2-fetch-code.sh` 和 `3-build.sh`，其余步骤相同。
> 本机构建时若你的代理是 dev-sidecar（31181 端口），Docker Desktop 的镜像拉取走 Docker Desktop 自身设置里的代理配置。

## 每个脚本做什么

| 脚本 | 作用 | 重复执行 |
|---|---|---|
| `1-server-init.sh` | CentOS 7 已 EOL，先把 yum 源指向 vault.centos.org；从阿里云源装 Docker CE + compose 插件；配置国内镜像加速；放行 8088 端口 | 安全，可重复 |
| `1b-mount-data-disk.sh` | 自动识别空数据盘 → 格式化为 ext4 → 挂到 `/opt/luwu` → 写 `/etc/fstab`（`nofail` 保证盘异常也能启动）。**带四重安全校验，绝不碰系统盘** | 安全，已挂载则跳过 |
| `2-fetch-code.sh` | clone `xjzsh/Octop` 的 `luwu` 分支到 `/opt/luwu/src`（失败自动换 ghfast 加速镜像）；已存在则更新到远端最新；**补设 `merge.ours.driver`**（品牌资产免冲突配置是仓库级、clone 后要重设） | 安全，幂等 |
| `3-build.sh` | 构建镜像 `luwu-ai:<TAG>`；apt/npm 走国内源，**自动把 uv.lock 的 PyPI 直连地址替换为阿里云内网镜像**（ECS 直连官方 CDN 仅几十 KB/s，内网源 ~80MB/s，sha256 校验不变）；内存 <4G 自动调低 node 内存参数 | 安全，可重复 |
| `4-deploy.sh` | 首次运行生成 `/opt/luwu/.env`（**自动生成随机强密码**）；用 compose 启动；打印登录信息 | 安全，幂等 |
| `5-upgrade.sh` | fetch → 重建镜像 → 滚动重启，旧容器数据不丢 | 升级时跑 |

## 部署后

- 访问：`http://<服务器IP>:8088`
- 管理员账号/密码：写在服务器 `/opt/luwu/.env` 里（`4-deploy.sh` 生成时打印过一次）
- 万一没创建管理员（密码不合格会走设置向导）：向导口令在 `/opt/luwu/data/octop-login.txt`
- 数据库：SQLite，文件在宿主机 `/opt/luwu/data/octop.db`

## 数据与备份

数据全部落在宿主机 `/opt/luwu/data/`，重建容器、升级镜像都不影响。备份：

```bash
# 建议加 crontab，每天凌晨备份
tar czf /opt/luwu/backup/luwu-$(date +%F).tar.gz -C /opt/luwu data
# 保留 7 天
find /opt/luwu/backup -name "luwu-*.tar.gz" -mtime +7 -delete
```

注意：容器运行中直接拷 `octop.db` 可能碰到 WAL 未合并（和之前 Windows 上一样的问题），tar 整目录时记得连 `-wal`/`-shm` 一起拿，或备份前 `docker exec luwu-ai octop db checkpoint`（如支持），或干脆 `docker stop` 几秒再备。

## 常见问题

| 现象 | 处理 |
|---|---|
| `yum install` 全部 404 | vault 源没换成功，看 `1-server-init.sh` 第 1 步输出 |
| 构建时 `Killed`（前端编译） | 内存不足：`3-build.sh` 已自动降 node 内存；还不行就用路线 B 本机构建 |
| 拉基础镜像超时 | `/etc/docker/daemon.json` 里的加速镜像失效了（国内镜像源经常变），换列表里的地址或自建 |
| 浏览器打不开 8088 | ① 云服务器**安全组**放行 8088（容易忘）② `firewall-cmd --list-ports` 确认 ③ `docker logs luwu-ai` 看服务起没起 |
| SELinux 导致数据卷 Permission denied | `1-server-init.sh` 已自动处理（设 permissive）；手动场景可给卷加 `:z` |

## 安全建议（上线前过一遍）

1. 端口别裸奔公网：要么只放行办公网段（安全组/防火墙白名单），要么前面挂 nginx + HTTPS
2. 首次登录后立刻改掉 `.env` 里的初始密码
3. SQLite 够用于小团队；多用户/长期生产再迁 PostgreSQL（compose 的 `OCTOP_DATABASE_DRIVER=postgresql` 即可）
