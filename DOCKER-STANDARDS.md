# Docker 项目规范与标准（本仓库实践沉淀）

> 适用范围：本仓库及衍生的所有 Docker 项目（shanbox / sandbox-box / github-runner）。
> 来源：2026-05~10 三轮项目实战沉淀，每条规则背后都有真实踩坑记录（详见 `.learnings/`）。
> 新开 Docker 项目前**先读这一页**。

---

## 0. 一分钟速查

```
写代码（Mac）→ CI 构建镜像（GitHub 托管 runner，linux/amd64）→ 推 GHCR
→ NAS 拉取部署（/data/docker/<name>/，只拉不建）
→ 密钥进 .env（600），行为进 entrypoint，重物进外挂卷，缓存进命名卷
```

---

## 1. 架构分层规范

新 Docker 项目的标准目录结构：

```
<project>/
├── Dockerfile          # 基础镜像 + 轻量工具链，全部版本钉死（ARG 可调）
├── docker-compose.yml  # 部署形态；NAS 侧版本【无 build: 段】
├── entrypoint.sh       # 启动编排：dockerd/sshd/注册/引导，全部自动化
├── bootstrap-*.sh      # （可选）重物外挂引导：首启安装、幂等标记
├── .env.example        # 配置模板；密钥永不进 git
└── README.md           # 部署手册，含【实测环境信息】（不是猜的）
```

**角色分工（铁律）**：

| 角色 | 职责 | 禁止 |
|---|---|---|
| Mac（开发机） | 写代码、语法校验、compose config 校验 | 起 daemon、跑容器、拉镜像（除非用户明确同意） |
| CI（托管 runner） | `docker buildx build --platform linux/amd64` → 推 GHCR | — |
| NAS（极空间 jkj） | `pull` + `up -d` + 运行 | **构建镜像**（只能拉取） |

---

## 2. Dockerfile 规范

### 2.1 版本钉死

```dockerfile
ARG RUNNER_VERSION=2.338.2      # 每个外部依赖都有 ARG，升级改一处
ARG GO_VERSION=1.27.3
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz
```

- 不写 `latest`、不赌发行版：**安装前先探活**（apt 仓库确认目标发行版有 Release 文件——gh CLI 官方仓库无 noble 的坑）
- 不可apt装的工具，从 GitHub Releases 下 .deb/tarball 直装

### 2.2 层序 = 缓存策略

- 变化频率低的层放前面（系统依赖 → 语言运行时 → 工具 → 代码）
- **冒烟验证层（`USER runner` + 逐个 `--version`）放尾部**：构建时即发现坏镜像，不占 GHCR
- 后加的内容放**独立尾层**并注明理由：`# 独立尾层：改动不击穿上方缓存层`
- ⚠️ GHA 的层缓存可能命中**旧的 COPY 内容**：改了脚本后要核对**镜像内文件 md5** 与仓库一致（实战踩过：entrypoint 旧版阴魂不散）

### 2.3 重物外挂（>500MB 工具链/数据）

**不进镜像**。进**共享命名卷 + 首启引导**：

```dockerfile
ENV ANDROID_HOME=/opt/tools/android-sdk   # 只声明路径
```

```yaml
volumes:
  - tools:/opt/tools        # external 共享卷，跨镜像更新存活、多实例共享
volumes:
  tools:
    external: true
    name: gha-tools
```

```bash
# bootstrap-tools.sh 原则：
# 1. 幂等：ok 标记文件存在即跳过（毫秒级）
# 2. 国内源优先：dl.google.com 国内 CDN / storage.flutter-io.cn / 腾讯镜像兜底
# 3. 后台执行：nohup ... & 不阻塞 runner 上线
# 4. 失败留日志，下次启动自动重试
```

实战收益：镜像 6.4GB → 3GB；月度更新下载量从数 GB → ~200MB。

### 2.4 国内镜像源矩阵（内置进镜像 ENV）

| 生态 | 源 | 备注 |
|---|---|---|
| Go | `GOPROXY=https://goproxy.cn,direct` | 不加基本不可用 |
| Flutter | `PUB_HOSTED_URL=pub.flutter-io.cn` `FLUTTER_STORAGE_BASE_URL=storage.flutter-io.cn` | 官方中国镜像 |
| Node 分发 | `NODE_INSTALL_URL=https://cdn.npmmirror.com/binaries/node` | **必须用 cdn 直链**，npmmirror.com/mirrors 是网页跳转会绕回国外源 |
| Playwright 浏览器 | `PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright` | ⚠️ 收录滞后：新版本 build 可能 404，用前查 [收录列表](https://registry.npmmirror.com/-/binary/playwright/builds/)，没有就**该步骤局部清空此变量**回官方 CDN |
| npm/pnpm registry | 全局 `~/.npmrc` 写 `registry=https://registry.npmmirror.com` | lockfile 已锁 resolved URL 的仍走原源，一致性不受影响 |

---

## 3. docker-compose 规范

### 3.1 NAS 部署版：无 `build:` 段

```yaml
services:
  runner:
    image: ${RUNNER_IMAGE:-ghcr.io/owner/name:latest}   # 只拉取
    hostname: <固定名>        # 固定主机名：重建容器后名字稳定、--replace 能清旧注册
    restart: unless-stopped
    privileged: true          # 仅 dind 等确实需要时；能不用就不用
    env_file:
      - ${ENV_FILE:-.env}     # ⚠️ 多实例必须参数化！
```

### 3.2 多实例（每仓库/每租户一实例）

```bash
cp .env .env.xmarket
# 改 RUNNER_URL / RUNNER_NAME / SSH_PORT，并且【必须】加：
echo "ENV_FILE=.env.xmarket" >> .env.xmarket   # 防 compose 同目录 .env 抢优先级！
docker compose -p <项目名> --env-file .env.xmarket up -d --force-recreate
```

**三层配置解析优先级**（实战血泪）：
`--env-file` 指定文件里的变量 > compose 同目录 `.env`（compose 自动加载！）> Dockerfile ENV。
`env_file:` 指令本身也参与变量替换——不参数化则所有实例读到第一份配置、互踢会话。

### 3.3 卷规划

| 卷类型 | 用途 | 属主 |
|---|---|---|
| `<lang>-cache` × N | 各语言构建缓存（gradle/maven/npm/pnpm/pub/uv/go…） | 首用前确认 `chown 1001:1001`（默认 root 会让非 root 进程 EACCES，如 playwright `__dirlock`） |
| `dind-data` | 容器内 dockerd 的镜像缓存 | 每个 job 结束 `docker prune` 防膨胀 |
| `tools`（external 共享） | 外挂工具链 | bootstrap 引导自管 |
| bind mount | NAS 现成资源（如 chromium） | **一律 `:ro` 只读** |

**不映射宿主 docker.sock 给业务容器**（= 交出 NAS 全部容器控制权）。CI 需要 docker → 容器内自建 dockerd（dind，privileged）。

---

## 4. entrypoint.sh 规范

```bash
set -euo pipefail          # 严格模式
RUNNER_HOME="${RUNNER_HOME:-/home/runner}"   # 全部路径用绝对路径或显式变量

# 两阶段：root 阶段（dockerd/sshd/引导）→ setpriv 降权进阶段二（业务进程）
```

必须项清单：
- [ ] **restart 竞态防护**：起 dockerd 前等旧进程退净 + 清 pid/socket 文件
- [ ] **生命周期尸体清理**：用绝对路径清 RUNNER_DIR（安装目录！）+ RUNNER_HOME 两处的注册残留
- [ ] 引导类脚本后台化（`nohup ... &`），失败留日志不阻塞主流程
- [ ] 降权用 `setpriv --reuid --regid --init-groups`（保留补充组）

---

## 5. 安全红线

1. **自托管 runner 永不服务 public 仓库**（PR 恶意代码 = 拿到宿主环境）
2. 密钥只进 `.env`（600），永不进 git / 镜像层 / 对话记录；进过对话记录 = 必须轮换
3. PAT 最小权限 + 设过期时间；org 级注册需 `admin:org`，仓库级需 `repo`
4. privileged 的真实代价（实测）：容器可见宿主 `/dev/nvme*` 裸设备 + docker.sock（控制 NAS 全部容器）+ 内网横向可达。**闸门 = 只跑自己私有仓库的代码**；要接不受信代码，先 rootless 重构
5. Mac 是用户私人环境：不起 daemon、不跑容器、不拉镜像——除非用户明确同意

---

## 6. 远程运维操作规范（ssh jkj）

| 场景 | 正确姿势 | 坑 |
|---|---|---|
| 杀远程进程 | `pkill -f "[p]attern"` 字符集技巧 | `pkill -f "compose pull"` 会匹配到自身命令行 → 自杀 + 误杀 |
| 判断远端命令成败 | `grep -q` 全文/多行，或显式 `echo EXIT:$?` | 管道 `\| grep -v Warning` 掩盖真实退出码 |
| docker pull 成功判定 | `grep -E "Downloaded newer\|up to date"` 全文 | 成功后最后一行是镜像名不是 Status 行 |
| 修 restart 循环容器 | `docker stop` → `docker cp` → `docker start` | 循环中容器 exec/cp 全部失败 |
| 首连重建过的容器 | `-o StrictHostKeyChecking=accept-new`；指纹变了先 `ssh-keygen -R` | 旧指纹拦截 ssh |
| compose 更新 | 改完仓库必须**重新 curl 覆盖 NAS 上的文件**再 up | NAS 上是部署时快照，仓库更新它不知道 |
| 长任务 | NAS 本地自愈循环（nohup + 重试 + 日志标记）+ 本地轮询看护 | 本地看护超时后**必须校验成功标记**再继续，不能拿着旧状态往下走 |

镜像拉取：国内拉 GHCR 用 `ghcr.nju.edu.cn/<owner>/<repo>`（实测唯一可用；daocloud/unsee/chenby 均废）。NJU 对私有镜像无现货缓存（回源慢）是固有成本，断点续传 + 多轮重试解决。**私有镜像源必须用 cdn/直链域名，网页跳转型前缀无效**。

---

## 7. 提交前检查清单

```bash
bash -n entrypoint.sh bootstrap-*.sh            # 语法
docker compose config --quiet                    # 配置合法性（需要 .env 存在）
# owner 断言：所有 ghcr.io / raw.githubusercontent 引用匹配 git remote
grep -oE "ghcr\.io/[^/]+/" <files> | 排除 "$(git remote get-url origin 解析的 owner)"
# 镜像内文件核对（更新脚本类改动后）：
docker exec <c> md5sum /usr/local/bin/entrypoint.sh   # vs 本地 md5
# 外部资源探活：
curl -sI "https://registry.npmmirror.com/-/binary/playwright/builds/"   # 版本收录确认
```

---

## 8. 实战案例索引（.learnings/）

| 编号 | 一句话 | 教训层 |
|---|---|---|
| ERR-20261029-001 | gh apt 仓库无 noble Release → release .deb 直装 | 依赖探活 |
| ERR-20261029-002 | 远程 pkill 自匹配自杀 + 管道掩盖退出码 | 远程操作 |
| ERR-20261029-003 | pull 尾行判定/compose 快照不同步/known_hosts | 远程状态判定 |
| ERR-20261029-004 | ephemeral 尸体在安装目录 + restart 循环 + env_file 优先级 + GHA 缓存旧 COPY | 多实例生命周期 |
| LRN-20261029-001 | NAS 只拉不建 + /data/docker/<name> + jkj≠shanbox | 部署边界 |
| LRN-20261029-002 | 重物外挂卷方案（用户提出） | 架构 |
| LRN-20261030-001 | playwright 镜像收录滞后 → 局部回官方源 | 镜像源策略 |
| ERR-20261030-001 | （本条）pnpm 版本双源冲突 → packageManager 字段为准 | CI 配置 |
