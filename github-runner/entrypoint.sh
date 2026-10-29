#!/usr/bin/env bash
# GitHub Actions 自托管 runner 入口
# 阶段一（root）：启动内嵌 dockerd（CI 的 docker build 全部跑在这个隔离 daemon 里）
# 阶段二（runner 用户）：调 API 拿 registration token → 注册 ephemeral runner → 跑 job
# --ephemeral：一个 runner 只接一个 job，跑完自动注销；容器重启后从阶段一重来，环境永远干净
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/home/runner}"
RUNNER_DIR="$RUNNER_HOME/actions-runner"
DOCKER_LOG=/tmp/dockerd.log

log() { echo "[entrypoint] $(date '+%F %T') $*"; }

if [[ "$(id -u)" -eq 0 ]]; then
  # ---------- 阶段一 ----------
  log "starting dockerd..."
  rm -f /var/run/docker.sock
  nohup dockerd --storage-driver=overlay2 >"$DOCKER_LOG" 2>&1 &
  for i in $(seq 1 60); do
    docker info >/dev/null 2>&1 && break
    if [[ "$i" -eq 60 ]]; then
      log "dockerd failed to start:"
      tail -30 "$DOCKER_LOG"
      exit 1
    fi
    sleep 1
  done
  log "dockerd ready"
  # 切到 runner 用户进阶段二；--init-groups 保留 docker 组（socket 权限）
  exec setpriv --reuid=runner --regid=runner --init-groups bash "$0"
fi

# ---------- 阶段二 ----------
: "${RUNNER_URL:?RUNNER_URL 必填：org 级填 https://github.com/<org>，仓库级填 https://github.com/<owner>/<repo>}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN 必填：classic PAT（org 级需 admin:org，仓库级需 repo）}"

export HOME="$RUNNER_HOME"
cd "$RUNNER_HOME"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-nas}"

# ephemeral：清掉上一次生命周期残留
rm -rf _work .credentials .runner _diag
mkdir -p _work

# registration token：按 URL 形态自动识别 org 级 / 仓库级
path="${RUNNER_URL#*://}"
path="${path#*/}"
path="${path%/}"
if [[ "$path" == */* ]]; then
  endpoint="/repos/$path/actions/runners/registration-token"
else
  endpoint="/orgs/$path/actions/runners/registration-token"
fi

log "requesting registration token: $endpoint"
TOKEN=$(curl -fsSL -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com$endpoint" -d '{}' | jq -re .token) || {
  log "获取 registration token 失败：检查 PAT 是否有效、权限是否够（org 级需 admin:org，仓库级需 repo）"
  exit 1
}

log "configuring runner '$RUNNER_NAME' (ephemeral, labels: $RUNNER_LABELS)"
"$RUNNER_DIR/config.sh" --url "$RUNNER_URL" --token "$TOKEN" \
  --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" \
  --ephemeral --unattended --replace

cleanup() {
  log "job finished, pruning dind containers & dangling images"
  docker container prune -f >/dev/null 2>&1 || true
  docker image prune -f >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "runner online, waiting for job (one job per lifecycle)"
"$RUNNER_DIR/run.sh"
