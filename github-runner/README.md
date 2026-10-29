# github-runner — GitHub Actions 自托管 Runner（极空间 NAS 部署版）

一个 Docker 容器 = 内嵌 dockerd（dind）+ GitHub Actions ephemeral runner + 全套常用工具链。
让私有仓库的 CI 跑在自己的极空间 Z4Pro 上，**0 分钟计费、时长不限**，不再消耗 GitHub 托管额度。

## 文件构成

| 文件 | 作用 |
|---|---|
| `Dockerfile` | Ubuntu 24.04 + runner 2.x + 工具链（见下） |
| `entrypoint.sh` | 起 dockerd → 拿 registration token → 注册 ephemeral runner → 跑 job → 容器重启循环 |
| `docker-compose.yml` | 单服务 `runner`（无端口映射，纯出站）+ 8 个缓存卷 |
| `.env.example` | 配置模板 |

## 预装工具链

docker（dind，CI 里 `docker build` 跑在隔离 daemon，碰不到 NAS 宿主）、Node 24、Python3 + uv、
Go、Temurin JDK 17/21、Android SDK（build-tools 36）、Flutter stable、gh CLI、ripgrep、git-lfs。
缓存卷：gradle / maven / npm / pub(Flutter) / uv / go-mod / go-build / dind 镜像缓存 —— 重启不丢，越跑越快。

## GitHub 侧准备

1. **建议先建 Organization**（免费）：runner group 是组织级功能，个人账号只能按仓库逐个注册。
   仓库转入 org 后一次注册全生效；仓库 URL 变为 `github.com/<org>/<repo>`（本地 remote 需改）。
2. **classic PAT**：org 级需 `admin:org`；仓库级需 `repo`。（Settings → Developer settings → PAT）

## 部署（极空间 Z4Pro，只拉不建）

> NAS 约束：极空间上**只能拉取镜像，不能构建**。镜像统一由 CI 构建（见下"镜像构建"），NAS 端 compose 无 `build:` 段。
> 实测环境（2026-10-29）：Z4Pro-O017 / x86_64 / Docker 26.1.4 / compose v2.21.0 / docker root `/data_n001/data/udata/real/zdocker`。

```bash
# 前置：镜像已由 CI 构建推 GHCR，且为 public（匿名可拉，无需 docker login）

# 1. ssh jkj 进 NAS，按 shanbox 同款惯例建项目目录
mkdir -p /data/docker/github-runner && cd /data/docker/github-runner

# 2. 取 compose 与配置模板
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/dyyz1993/docker-container-shanbox/master/github-runner/docker-compose.yml
curl -fsSL -o .env.example     https://raw.githubusercontent.com/dyyz1993/docker-container-shanbox/master/github-runner/.env.example

# 3. 填配置后启动
cp .env.example .env && vim .env   # 填 RUNNER_URL + GITHUB_TOKEN（classic PAT：org 级 admin:org / 仓库级 repo）
docker compose pull && docker compose up -d
```

（也可放进 dockge 面板管理：栈目录 `/data/docker/dockge/stacks/github-runner/`，粘贴同一份 compose + .env 即可。）

验证：GitHub 仓库/组织 → Settings → Actions → Runners 出现 `gha-runner-1`（Idle）。
workflow 里 `runs-on: [self-hosted, nas]` 即可路由到它（`nas` 标签在 `.env` 里配）。

### 磁盘注意

NAS 数据盘当前已用 **91%**（余 165G）。本镜像压缩后约 4.5~5G，解压 + dind 缓存卷会继续增长，留意清理（见下"注意事项"）。

## 并发扩容（多实例 = 每仓库一个实例）

单实例同一时刻只跑 1 个 job。接新仓库：

```bash
cd /data/docker/github-runner
cp .env .env.<名字>
# 改 RUNNER_URL（指向新仓库）、RUNNER_NAME（唯一）、SSH_PORT（唯一端口）
# 必须加一行 ENV_FILE=.env.<名字> —— compose 同目录的 .env 会抢 env_file 变量优先级！
echo "ENV_FILE=.env.<名字>" >> .env.<名字>
docker compose -p <项目名> --env-file .env.<名字> up -d --force-recreate
```

⚠️ 踩坑记录（详见项目 .learnings/）：
- `--env-file` 只做变量替换，compose 里 `env_file:` 也要参数化（`ENV_FILE:-.env`），否则所有实例读到第一份配置
- 改完 entrypoint 后验证镜像内文件与仓库一致（GHA 层缓存可能命中旧 COPY 层）
- ephemeral 异常退出会在 `actions-runner/`（安装目录）留 `.runner`/`.credentials` 尸体，restart 前必须清理（entrypoint 已内置）
- 修 restart 循环容器：`docker stop` → `docker cp` → `docker start`（循环中的容器 exec/cp 都会失败）

## 注意事项

- **iOS/macOS 构建不行**：Linux 容器出不了 iOS 包；以后可在 Mac 上直接装一个 runner 用 label 区分。
- **公开仓库红线**：自托管 runner 绝不能服务 public repo（PR 恶意代码 = 拿到你的环境）。
  org runner group 默认仅私有仓库可见，不要改公开。
- **镜像更新**：NAS 上 `bash /data/docker/github-runner/auto-update.sh`（南大镜像源 + 8 轮断点重试 + 双实例滚动重启）。
  workflow 每月 1 号自动构建新镜像；⚠️ 若仓库里的 docker-compose.yml 也有更新，先重新 curl 覆盖 NAS 上的 compose 再跑脚本。
- **--ephemeral**：一个 runner 只接一个 job，跑完自动注销、容器重启重新注册（`--replace` 清理同名旧注册）。
  NAS 断电重启后自动恢复，无需人工干预。
- **磁盘**：镜像 ~3GB（工具链已外挂到 gha-tools 卷，~3GB）；`dind-data` 卷随 CI 构建增长（镜像缓存保留以加速），
  必要时 `docker exec gha-runner-1 docker system prune -af` 清理。
- **国内镜像源已内置**：GOPROXY/flutter-io.cn/npmmirror(playwright+node 分发)/npm registry 全局 .npmrc
  （lockfile 已锁 resolved URL 的仍走原源，保证一致性）。
