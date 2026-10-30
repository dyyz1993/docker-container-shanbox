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
## [LRN-20261029-002] best_practice

**Logged**: 2026-10-29T17:05:00Z
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
用户提议：重型/需额外下载的工具链用"外挂"进容器，别打进镜像——彻底避免每次镜像更新拉几个 GB。

### Details
gha-runner 镜像 6.4GB，大头是 Android SDK（~3GB）+ Flutter（~2GB）。且 CI 全量重建后层摘要全变，NAS 更新 = 重新下载全部层（晚高峰国际带宽下苦不堪言）。采纳用户方案：两个工具链移到共享外挂卷 gha-tools:/opt/tools，bootstrap-tools.sh 首启检测标记文件、从 dl.google.com（国内 CDN）+ storage.flutter-io.cn 懒加载安装，幂等、跨镜像更新存活、双实例共享一份。镜像瘦至 ~3GB，后续月度更新预计 100MB 级增量。

### Suggested Action
凡 >500MB 的工具链/数据集一律外挂卷 + 首启引导（幂等标记 + 国内源），镜像只留"不可变基础件"。

### Metadata
- Source: user_feedback
- Related Files: github-runner/bootstrap-tools.sh, github-runner/docker-compose.yml
- Tags: docker, image-size, lazy-bootstrap, mirror
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29
- Recurrence-Count: 1

---
## [LRN-20261030-001] best_practice

**Logged**: 2026-10-31T04:00:00Z
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
playwright 浏览器镜像源（npmmirror）收录滞后：新 playwright 版本（如 1208/Chrome for Testing 145）镜像源 404。全局 PLAYWRIGHT_DOWNLOAD_HOST 会卡死新版。

### Details
xbrowser-marketplace e2e：npm registry 走 npmmirror 后，playwright install 404（cdn.npmmirror.com/binaries/playwright 最高收录 1243 之前的 build；1208 的 chrome-for-testing 变体不存在）。对策：该 install 步骤局部 `PLAYWRIGHT_DOWNLOAD_HOST: ""` 回官方 CDN，其余照旧。另：playwright-cache 卷首用前需 chown 1001（默认 root 属主致 __dirlock EACCES）。

### Suggested Action
镜像源只用于"确认收录"的资源；版本敏感的二进制分发（playwright browsers）要么锁版本、要么局部回官方源。

### Metadata
- Source: conversation
- Related Files: /tmp/xm-trigger/.github/workflows/ci.yml
- Tags: playwright, mirror, npmmirror, e2e
- First-Seen: 2026-10-30
- Last-Seen: 2026-10-30
- Recurrence-Count: 1

---
