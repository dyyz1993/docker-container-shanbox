# GitHub Actions 自托管 runner（全工具链版）
# 平台：linux/amd64（极空间 Z4Pro x86_64）
# 预装：docker-in-docker / Node 24 / Python3+uv / Go / Temurin JDK 17+21 /
#       Android SDK / Flutter stable / gh CLI；各语言缓存目录由 compose 挂卷持久化
# 镜像约 9~11GB，由 .github/workflows/build-gha-runner.yml 构建并推送 GHCR
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ---------- 系统基础 ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https ca-certificates curl wget gnupg \
    git git-lfs jq unzip zip xz-utils tar \
    build-essential openssh-client ripgrep tzdata locales \
    libicu74 libssl3t64 iptables gosu \
  && locale-gen en_US.UTF-8 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TZ=Asia/Shanghai

# ---------- Docker CE（dind：runner 容器内自建 daemon，与 NAS 宿主完全隔离）----------
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------- gh CLI（官方 apt 仓库无 noble 发行版，直装 .deb）----------
ARG GH_VERSION=2.103.3
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb" -o /tmp/gh.deb \
  && apt-get install -y /tmp/gh.deb \
  && rm /tmp/gh.deb && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------- runner 用户 + docker 组（访问内嵌 daemon 的 socket）----------
RUN useradd -m -u 1001 -s /bin/bash runner \
  && usermod -aG docker runner

# ---------- Node 24 LTS ----------
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && corepack enable

# ---------- Python 3 + uv ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv python3-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# ---------- Go ----------
ARG GO_VERSION=1.27.3
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz
ENV PATH=/usr/local/go/bin:$PATH

# ---------- Temurin JDK 17 + 21 ----------
RUN curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" > /etc/apt/sources.list.d/adoptium.list \
  && apt-get update && apt-get install -y --no-install-recommends temurin-17-jdk temurin-21-jdk \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64

# ---------- Android SDK + Flutter：外挂懒加载 ----------
# 不打进镜像：bootstrap-tools.sh 首次启动时装到 /opt/tools 外挂卷（国内源、跨镜像更新存活）
ENV ANDROID_HOME=/opt/tools/android-sdk \
    ANDROID_BUILD_TOOLS=36.0.0 \
    ANDROID_PLATFORM=android-36 \
    FLUTTER_VERSION=3.47.8
ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:/opt/tools/flutter/bin:$PATH

# ---------- GitHub Actions runner本体 ----------
ARG RUNNER_VERSION=2.338.2
ENV RUNNER_HOME=/home/runner
RUN mkdir -p ${RUNNER_HOME}/actions-runner \
  && curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
      | tar -C ${RUNNER_HOME}/actions-runner -xz \
  && chown -R runner:runner ${RUNNER_HOME}/actions-runner \
  && bash ${RUNNER_HOME}/actions-runner/bin/installdependencies.sh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------- 缓存目录（compose 以同名卷挂载，首次挂卷继承此属主）----------
RUN mkdir -p ${RUNNER_HOME}/_work ${RUNNER_HOME}/.gradle ${RUNNER_HOME}/.m2 \
      ${RUNNER_HOME}/.npm ${RUNNER_HOME}/.pub-cache ${RUNNER_HOME}/.cache/uv \
      ${RUNNER_HOME}/.cache/go-build ${RUNNER_HOME}/go \
  && chown -R runner:runner ${RUNNER_HOME}

# ---------- 冒烟验证（轻量版：外挂工具链不在镜像内，不在此验证）----------
USER runner
RUN node --version && npm --version \
  && python3 --version && uv --version \
  && go version \
  && java -version \
  && docker --version \
  && gh --version | head -1

# ---------- SSH 调试入口 + runner 免密 sudo（对齐托管 runner 行为，Playwright --with-deps 等需要）----------
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server sudo \
  && mkdir -p /run/sshd /root/.ssh /etc/sudoers.d \
  && printf 'PasswordAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/99-runner.conf \
  && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner && chmod 0440 /etc/sudoers.d/runner \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------- 国内镜像源（NAS 上跑 CI job 时生效：Go/Flutter 官方中国镜像；对 GitHub 构建机无影响）----------
ENV GOPROXY=https://goproxy.cn,direct \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright

USER root
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY bootstrap-tools.sh /usr/local/bin/bootstrap-tools.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/bootstrap-tools.sh
WORKDIR ${RUNNER_HOME}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
