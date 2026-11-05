#!/bin/bash
# 99-proxy-setup.sh — gha-runner 出站代理自动配置
# 由 entrypoint.sh 在 dockerd 就绪后调用（root 阶段）
# mihomo（一倍率节点池 url-test 自动选优，配置在 /etc/mihomo/config.yaml）
# GitHub/GHCR/内网直连（mihomo rules），其余流量走代理

# mihomo 二进制持久化在外挂卷 /opt/tools/bin（首次自动下载）
if [ ! -x /opt/tools/bin/mihomo ]; then
    mkdir -p /opt/tools/bin
    curl -fsSL "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.4/mihomo-linux-amd64-v1.19.4.gz" | gunzip > /opt/tools/bin/mihomo 2>/dev/null       && chmod +x /opt/tools/bin/mihomo || echo "[proxy-setup] mihomo download failed"
fi
[ -x /opt/tools/bin/mihomo ] && PATH="/opt/tools/bin:$PATH"
([ -x /opt/tools/bin/mihomo ] && BIN=/opt/tools/bin/mihomo || BIN=mihomo; $BIN -d /etc/mihomo > /tmp/mihomo.log 2>&1 &) 2>/dev/null

# 等端口就绪（最多 15s）
for _ in $(seq 1 15); do
    curl -s --max-time 2 -x http://127.0.0.1:7890 -o /dev/null http://www.gstatic.com/generate_204 2>/dev/null && break
    sleep 1
done

if curl -s --max-time 3 -x http://127.0.0.1:7890 -o /dev/null http://www.gstatic.com/generate_204 2>/dev/null; then
    echo "[proxy-setup] mihomo OK on :7890"
    # 注入环境变量（/etc/profile.d + runner 用户的 .bashrc，确保 job 与交互 shell 都可见）
    cat > /etc/profile.d/99-proxy.sh << 'ENV'
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export no_proxy=localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
export NO_PROXY=$no_proxy
ENV
    chmod +x /etc/profile.d/99-proxy.sh
    grep -q "99-proxy" /home/runner/.bashrc 2>/dev/null || \
        echo '. /etc/profile.d/99-proxy.sh' >> /home/runner/.bashrc
else
    echo "[proxy-setup] mihomo FAILED, proxy not configured"
fi
