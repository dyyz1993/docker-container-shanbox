## [LRN-20261029-001] correction

**Logged**: 2026-10-29T02:10:00Z
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
极空间（ssh 别名 jkj）部署约束：只能拉取镜像、不能在 NAS 上构建；compose 项目要放 /data/docker/<name>/。

### Details
用户纠正（原话"jkj 里面只能拉取不可以在里面进行构建…要在/docker/data/xxx"）。实测（全部只读）：
- ssh 别名：`jkj` = 极空间宿主机（192.168.0.29:10000 root）；`shanbox` = shanbox **容器内部**（无 docker CLI，hostname 是容器 ID）——别再用 shanbox 查宿主机
- 宿主机：Z4Pro-O017，x86_64，Docker 26.1.4，compose v2.21.0，docker root `/data_n001/data/udata/real/zdocker`
- compose 惯例：手工部署放 `/data/docker/<name>/`（shanbox 同款）；dockge 面板栈在 `/data/docker/dockge/stacks/<name>/`（容器内显示为 /volume1/...）
- 数据盘 91% 已用（余 165G）；GHCR 镜像匿名可拉

### Suggested Action
给 NAS 的 compose 一律删掉 `build:` 段（镜像全部 CI 构建推 GHCR）；部署路径 /data/docker/<name>/；查宿主机用 jkj 不用 shanbox。

### Metadata
- Source: user_feedback
- Related Files: github-runner/docker-compose.yml, github-runner/README.md
- Tags: nas, zspace, deploy, docker
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29
- Recurrence-Count: 1

---
