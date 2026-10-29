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
## [LRN-20261029-002] correction

**Logged**: 2026-10-29T12:15:00Z
**Priority**: critical
**Status**: resolved
**Area**: infra

### Summary
用户制止：未经确认在用户 Mac 上启动 OrbStack 并跑 docker pull。用户 Mac 不做任何工作负载/守护进程启动，除非明确要求。

### Details
为加速 NAS 拉镜像，自行 open -a OrbStack 在 Mac 拉镜像。用户："你怎么在我的机器上去跑这个Docker呢？我不希望。" 已即时停止：删镜像、prune、退出 OrbStack 恢复原状。用户随后给出正解：用国内 registry 镜像前缀（NAS 已在用 docker.unsee.tech 等）加速 ghcr 拉取。

### Suggested Action
1. 用户 Mac 只做开发/校验（bash -n、compose config），不起 daemon、不跑容器、不拉镜像
2. 遇到国内拉取慢：优先 registry 镜像前缀方案（docker.m.daocloud.io/ghcr.io/...、ghcr.nju.edu.cn/... 等），多在 NAS 上探活再选路

### Metadata
- Source: user_feedback
- Related Files: /tmp/gha-pull-watch.sh
- Tags: mac, boundary, docker, mirror
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29
- Recurrence-Count: 1

---
