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
