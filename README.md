# Shanbox - 轻量级 Docker 反向代理沙箱

一个基于 Debian + Nginx + SSH + Supervisor 的轻量容器，提供通配符域名路由和访问控制。

**特点：**
- 通配符域名路由：`xxx.yourdomain.com` 自动代理到指定端口
- 4 种访问策略：public / key / header / private
- HTML vs API 智能拦截：浏览器访问跳转认证页，API 请求返回 401 JSON
- 内网白名单：LAN 和指定公网 IP 自动放行
- SSH 管理：通过 SSH 密钥登录容器管理路由
- 数据持久化：配置、脚本、数据通过 Volume 持久化
- 自动恢复：Supervisor 管理 sshd/nginx/cron，崩溃自动重启

## 架构

```
外网用户
    │
    ▼ :8443 (HTTPS)
┌──────────────┐
│  NAS/Nginx   │  ← SSL 证书在这里处理
│  反向代理     │
└──────┬───────┘
       │ :9080 (HTTP)
       ▼
┌──────────────┐
│   Shanbox    │
│   容器内部    │
│              │
│  ┌─────────┐ │
│  │  Nginx  │ │──→ 访问控制 + 路由转发
│  └────┬────┘ │
│       │      │
│  ┌────┴────┐ │
│  │ 后端服务 │ │──→ localhost:xxxx
│  └─────────┘ │
│              │
│  SSH :2200   │  ← 远程管理
└──────────────┘
```

## 快速部署

### 1. 创建目录结构

```bash
mkdir -p /data/docker/shanbox/{config,scripts,data,logs}
```

### 2. 创建 `.env`

```bash
cat > /data/docker/shanbox/.env << 'EOF'
SSH_PUBLIC_KEY=ssh-rsa AAAA... 你的公钥
PUBLIC_IP=1.2.3.4
DOMAIN=yourdomain.com
EOF
```

| 变量 | 说明 |
|------|------|
| `SSH_PUBLIC_KEY` | 你的 SSH 公钥，用于登录容器 |
| `PUBLIC_IP` | 你的公网 IP，该 IP 访问时自动跳过认证 |
| `DOMAIN` | 你的域名（如 `shanbox.example.com`） |

### 3. 创建 `docker-compose.yml`

```yaml
services:
  shanbox:
    image: ghcr.io/dyyz1993/docker-container-shanbox:latest
    container_name: shanbox
    restart: unless-stopped
    ports:
      - "9080:80"    # HTTP（外部反代用）
      - "2200:22"    # SSH 管理
    env_file:
      - .env
    volumes:
      - ./config:/etc/nginx/custom
      - ./scripts:/root/scripts
      - ./data:/root/data
      - ./logs:/var/log
```

### 4. 启动

```bash
cd /data/docker/shanbox
docker compose up -d
```

### 5. 配置 SSH 快捷方式（本地）

```bash
cat >> ~/.ssh/config << 'EOF'

Host shanbox
    HostName <服务器IP>
    Port 2200
    User root
    IdentityFile ~/.ssh/id_rsa
EOF
```

然后直接 `ssh shanbox` 即可连接。

## 路由管理

### 添加路由

编辑 `config/routes.conf`：

```nginx
map $host $backend_port {
    default              0;
    ~^app\.              3000;
    ~^api\.              8080;
    ~^docs\.             9090;
}

map $host $access_policy {
    default              "public";
    ~^app\.              "key";
    ~^api\.              "header";
    ~^docs\.             "public";
}
```

**含义：**
- `app.yourdomain.com` → 代理到容器内 `localhost:3000`，需要 URL 参数 `?key=xxx` 认证
- `api.yourdomain.com` → 代理到容器内 `localhost:8080`，需要 `X-Auth-Token` 请求头认证
- `docs.yourdomain.com` → 代理到容器内 `localhost:9090`，公开访问

修改后重载 nginx：

```bash
docker exec shanbox nginx -t && docker exec shanbox nginx -s reload
```

### 使用 manage-route.sh 脚本

```bash
# 添加路由
docker exec shanbox /root/scripts/manage-route.sh add app 3000 key

# 删除路由
docker exec shanbox /root/scripts/manage-route.sh remove app

# 列出所有路由
docker exec shanbox /root/scripts/manage-route.sh list
```

## 访问策略详解

### public（公开）

任何人都可以访问，无需认证。

```nginx
~^docs\.    "public";
```

### key（URL 参数认证）

请求必须携带 `?key=xxx` 参数，否则被拦截。

```nginx
~^app\.    "key";
```

- HTML 请求（浏览器）→ 302 重定向到 `/__auth__/` 认证页面
- API 请求 → 返回 `401 {"error":"unauthorized","message":"authentication required"}`
- 带 `?key=任意值` → 放行

### header（请求头认证）

请求必须携带 `X-Auth-Token` 请求头，否则被拦截。

```nginx
~^api\.    "header";
```

- 缺少 `X-Auth-Token` 头 → 同上拦截逻辑
- 带 `X-Auth-Token: 任意值` → 放行

### private（仅内网）

只有内网 IP 和白名单 IP 可以访问，外部完全不可达。

```nginx
~^admin\.    "private";
```

内网白名单自动包含：
- `10.0.0.0/8`
- `192.168.0.0/16`
- `127.0.0.0/8`
- `.env` 中 `PUBLIC_IP` 指定的公网 IP

## 目录结构

```
shanbox/
├── docker-compose.yml
├── .env                        # 环境变量（SSH 公钥、域名、公网 IP）
├── config/
│   └── routes.conf             # 路由配置（域名→端口+策略）
├── scripts/
│   └── manage-route.sh         # 路由管理脚本
├── data/                       # 持久化数据
└── logs/                       # 日志
    └── nginx/
```

## 外部反向代理配置

容器只提供 HTTP，HTTPS 由外部 Nginx/OpenResty 处理。

示例（OpenResty）：

```nginx
server {
    listen 8443 ssl;
    server_name *.yourdomain.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://127.0.0.1:9080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }
}
```

## 更新镜像

```bash
cd /data/docker/shanbox
docker compose pull
docker compose up -d
```

## 常用操作

```bash
# 查看容器状态
docker ps --filter name=shanbox

# 查看日志
docker logs shanbox --tail 50

# 进入容器
ssh shanbox
# 或
docker exec -it shanbox bash

# 重启 nginx
docker exec shanbox nginx -s reload

# 查看各服务状态
docker exec shanbox supervisorctl status

# 重启整个容器
docker restart shanbox
```

## CI/CD

推送到 `master` 分支自动触发 GitHub Actions：
1. 构建 Docker 镜像
2. 推送到 `ghcr.io/dyyz1993/docker-container-shanbox:latest`
3. 运行 12 个 E2E 测试验证所有功能
