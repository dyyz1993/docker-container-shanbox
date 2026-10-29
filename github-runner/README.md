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

## 部署

```bash
# Mac 上首次：push 本仓库触发 .github/workflows/build-gha-runner.yml 构建镜像（约 30 分钟）

# NAS 上（ssh 进极空间）：
mkdir -p ~/docker/github-runner && cd ~/docker/github-runner
# 把本目录 4 个文件 + .env.example 拷上来，然后：
cp .env.example .env   # 填 RUNNER_URL + GITHUB_TOKEN
docker login ghcr.io -u dyyz1993 -p <PAT(read:packages)>   # GHCR 包默认私有；或首次推送后在 GitHub 把包设为 public 跳过登录
docker compose pull
docker compose up -d
```

验证：GitHub 仓库/组织 → Settings → Actions → Runners 出现 `gha-runner-1`（Idle）。
workflow 里 `runs-on: [self-hosted, nas]` 即可路由到它（`nas` 标签在 `.env` 里配）。

## 并发扩容

单实例同一时刻只跑 1 个 job。要 N 个并发（每个都有独立 dind + 独立缓存卷）：

```bash
cp .env .env2   # 改 RUNNER_NAME=gha-runner-2（其余不动）
docker compose -p gha2 --env-file .env2 up -d
```

## 注意事项

- **iOS/macOS 构建不行**：Linux 容器出不了 iOS 包；以后可在 Mac 上直接装一个 runner 用 label 区分。
- **公开仓库红线**：自托管 runner 绝不能服务 public repo（PR 恶意代码 = 拿到你的环境）。
  org runner group 默认仅私有仓库可见，不要改公开。
- **镜像更新**：workflow 每月 1 号自动跟进 actions/runner 新版本；NAS 上 `docker compose pull && up -d`。
- **--ephemeral**：一个 runner 只接一个 job，跑完自动注销、容器重启重新注册（`--replace` 清理同名旧注册）。
  NAS 断电重启后自动恢复，无需人工干预。
- **磁盘**：镜像 ~10GB；`dind-data` 卷会随 CI 构建增长（镜像缓存被保留以加速），必要时
  `docker exec gha-runner-1 docker system prune -af` 清理（会牺牲镜像缓存速度）。
