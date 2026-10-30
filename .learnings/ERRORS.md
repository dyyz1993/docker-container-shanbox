## [ERR-20261029-001] gh-cli-apt-repo-no-noble

**Logged**: 2026-10-29T01:45:00Z
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
Dockerfile 基于 Ubuntu 24.04 (noble) 时，gh CLI 官方 apt 仓库 `https://cli.github.com/packages` 没有 noble 发行版，`apt-get update` 报 "does not have a Release file"（exit 100）。

### Error
```
E: The repository 'https://cli.github.com/packages noble Release' does not have a Release file.
```

### Context
- `github-runner/Dockerfile` 按 gh 官方文档添加 apt 仓库（jammy/focal 等老版本有，noble 缺失）
- Docker 构建（linux/amd64, buildx）在 CI 托管 runner 上失败

### Suggested Fix
不走 apt 仓库，直接从 GitHub Releases 下载官方 .deb 安装：
`curl -fsSL https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb | apt-get install -y /dev/stdin`
版本用 ARG 钉住，升级只改一个参数。

### Resolution
- **Resolved**: 2026-10-29T01:40:29Z
- **Commit/PR**: fix: install gh from release .deb (apt repo lacks noble Release)
- **Notes**: 已验证：GHCR 镜像构建成功（14 分钟），匿名可拉取

### Metadata
- Reproducible: yes
- Related Files: github-runner/Dockerfile
---
## [ERR-20261029-002] pkill-self-match-remote-shell

**Logged**: 2026-10-29T12:06:00Z
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
ssh 远端执行 `pkill -f "模式"` 时，模式字符串出现在远端 shell 自身命令行里（作为 pkill 参数），pkill 把自己的父 shell 一起杀掉 → ssh 无输出断连；且同命令里先匹配到的 compose pull 也被误杀，30 分钟的直连拉取前功尽弃。连犯两次。

### Error
```
ssh jkj 'pkill -f "compose pull"; nohup docker pull ...'   # 远端 shell 自身 cmdline 含 "compose pull"，被自杀
```

### Context
远程进程管理场景；`pkill -f` 按完整命令行匹配，不排除自身与父进程。

### Suggested Fix
1. 字符集技巧破坏自匹配：`pkill -f "[c]ompose pull"`
2. 或改用精确进程文件：`pgrep -f pattern` 后 `kill <pid列表>`（排除 $$ 相关）
3. 本地管道 `cmd | grep -v Warning` 会掩盖真实退出码——判断远端命令成败时勿依赖管道退出码

### Resolution
- **Resolved**: 2026-10-29T12:05:00Z
- **Notes**: 改用"启动不 pkill、检测用 [x] 方括号模式"后恢复正常

### Metadata
- Reproducible: yes
- Recurrence-Count: 2
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29
---
## [ERR-20261029-003] remote-state-check-boundaries

**Logged**: 2026-10-29T13:10:00Z
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
同一任务内连续踩中三个"远程状态判定"边界：(1) docker pull 成功后最后一行是镜像 tag 而非 "Status: Downloaded" 行，tail -1 判定误报失败；(2) NAS 上的 compose 文件是部署时快照，仓库 compose 更新（新增 ports）后 NAS 侧不知情，镜像更新了端口却不生效；(3) 换镜像重建容器后 sshd host key 变化触发 known_hosts 拦截。

### Error
```
tail -1 pull.log | grep -q "Downloaded newer" || echo DEAD   # 最后一行实际是 "ghcr.nju.edu.cn/...:latest"
ssh -p 2202 host → Connection refused（compose 无 ports 段，sshd 在容器里活着）
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

### Suggested Fix
1. 成功标记用 `grep -q` 全文或 `tail -3`，勿依赖精确最后一行
2. 给 NAS 部署的 compose/配置文件，仓库侧更新后必须同步重拉（README 更新流程已补这句）
3. 重建容器类服务首次连接用 `-o StrictHostKeyChecking=accept-new`；指纹变化先 `ssh-keygen -R` 再连

### Metadata
- Reproducible: yes
- See Also: ERR-20261029-002
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29
- Recurrence-Count: 3
---
## [ERR-20261029-004] ephemeral-runner-restart-corpse-chain

**Logged**: 2026-10-29T19:55:00Z
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
ephemeral runner 容器 restart 后连环死锁 2 小时。四层根因叠加：(1) `docker restart` 不重建容器，异常退出留下的 `.runner`/`.credentials` 在 **RUNNER_DIR（actions-runner/ 安装目录）**而非 RUNNER_HOME，清理清错位置 → "already configured" 拒绝重注册 → set -e 退出 → restart 循环；(2) 循环容器无法 docker exec/docker cp（含 stdin 方式），热修极难；(3) compose 的 env_file 修复版未同步 NAS 前，多实例曾错注册到同一仓库互相踢会话；(4) 镜像 COPY 层缓存命中旧 entrypoint，force-recreate 拿到的还是旧逻辑。

### Error
```
Cannot configure the runner because it is already configured.
Error response from daemon: Container ... is restarting, wait until the container is running
```

### Suggested Fix
1. 清理必须绝对路径且覆盖 RUNNER_DIR + RUNNER_HOME 两处（已修）
2. 修循环容器：`docker stop`（非 restart）→ docker cp → `docker start`；docker cp 对运行中/循环容器会报 /proc/self/fd 错
3. 多实例各自 ENV_FILE 写进自身 env 文件（防 compose 同目录 .env 抢优先级）
4. 改 entrypoint 后必须验证镜像内文件 md5 与仓库一致（GHA 层缓存可能骗人）

### Metadata
- Reproducible: yes
- See Also: ERR-20261029-002
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29
- Recurrence-Count: 1
---
## [ERR-20261030-001] pnpm-version-dual-source

**Logged**: 2026-10-31T00:10:00Z
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
pnpm/action-setup@v4 在 action input `version: 10` 与 package.json `packageManager: pnpm@12.16.1` 并存时报 ERR_PNPM_BAD_PM_VERSION，CI 三个 job 全挂。存量问题：旧 CI 从未跑到这一步（前置步骤先挂），NAS runner 首次让流水线跑深才暴露。

### Error
```
Error: Multiple versions of pnpm specified:
  - version 10 in the GitHub Action config with the key "version"
  - version pnpm@12.16.1+sha512... in package.json "packageManager"
```

### Suggested Fix
删掉 workflow 里的 `version: 10` 输入，以 package.json `packageManager` 字段为唯一权威版本源。另：commitlint 对 commit message 有 type-enum + subject ≤80 字符约束；husky pre-commit 需要完整 devDeps（lint-scripts 缺 glob 会让本地提交直接失败）。

### Metadata
- Reproducible: yes
- Related Files: .github/workflows/ci.yml（xbrowser-marketplace 仓库）
- First-Seen: 2026-10-30
- Last-Seen: 2026-10-30
---
