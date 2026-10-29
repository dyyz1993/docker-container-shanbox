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

# ---------- Android SDK ----------
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_PLATFORM=android-36
ENV ANDROID_HOME=/opt/android-sdk
RUN curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" -o /tmp/cmdline-tools.zip \
  && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
  && mkdir -p ${ANDROID_HOME}/cmdline-tools \
  && mv /tmp/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
  && rm /tmp/cmdline-tools.zip \
  && (yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_HOME} --licenses > /dev/null || true) \
  && ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_HOME} \
      "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${ANDROID_BUILD_TOOLS}" > /dev/null \
  && chown -R runner:runner ${ANDROID_HOME}
ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:$PATH

# ---------- Flutter stable ----------
ARG FLUTTER_VERSION=3.47.8
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" | tar -C /opt -xJ \
  && chown -R runner:runner /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH

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

# ---------- 冒烟验证 ----------
USER runner
RUN flutter config --no-analytics >/dev/null \
  && flutter precache --android \
  && git config --global --add safe.directory /opt/flutter \
  && node --version && npm --version \
  && python3 --version && uv --version \
  && go version \
  && java -version \
  && sdkmanager --sdk_root=${ANDROID_HOME} --list_installed | head -5 \
  && flutter --version \
  && docker --version

# ---------- SSH 调试入口 + runner 免密 sudo（对齐托管 runner 行为，Playwright --with-deps 等需要）----------
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server sudo \
  && mkdir -p /run/sshd /root/.ssh /etc/sudoers.d \
  && printf 'PasswordAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/99-runner.conf \
  && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner && chmod 0440 /etc/sudoers.d/runner \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

USER root
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh
WORKDIR ${RUNNER_HOME}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
