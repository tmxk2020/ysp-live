# 🚀 ysp-live-docker 9.8-TMXK（软路由优化版）

一个基于 Docker 与 Python 构建的直播源处理与转发工具，针对 OpenWrt 软路由及 Linux Docker 环境提供 Host 网络部署方式。

本分支只完善安装、升级、数据持久化和健康检查流程，**不改动 9.8 的播放解析核心逻辑**。

---

## ✨ 核心特点

- **🌐 Host 网络模式**：容器直接使用宿主机网络，适合需要访问局域网组播或特殊网络环境的设备。
- **🛡️ DNS 配置**：提供常用公共 DNS 配置，可按自己的网络环境调整。
- **⚡ Node.js 运行参数**：保留原有 V8 内存参数。
- **📦 轻量镜像**：基于 Alpine Python 镜像构建，并安装 Node.js 运行时。
- **💾 数据持久化**：配置和运行数据挂载到宿主机；更新前自动备份旧数据。
- **🩺 健康检查**：Compose 和安装脚本都会检查本地 `/health` 接口。

---

## ⚡ 一键安装 / 更新（推荐）

适用于已安装 Docker 和 Docker Compose 的 OpenWrt 或 Linux 设备：

```sh
sh -c "$(wget -O- https://raw.githubusercontent.com/tmxk2020/ysp-live/main/install.sh)"
```

首次安装时按提示确认即可。检测到已有容器时，会显示管理菜单，可查看链接、日志、健康状态或执行更新。

### 更新时会做什么

1. 检查 Docker、Docker Compose、wget、unzip 和 Docker 服务状态。
2. 识别旧容器的 `/app/data` 实际挂载路径。
3. 更新前将旧数据备份到 `/root/ysp-live/backups/`。
4. 保留原有数据挂载路径；如果旧容器使用 Docker 命名卷，则将数据复制到项目持久化目录，原卷不会被删除。
5. 下载并检查源码文件，先执行 `docker compose config` 校验。
6. 构建并启动 9.8-TMXK，再等待 `/health` 响应。

如果配置检查或数据备份失败，脚本会中止更新，不会先删除旧容器。更新后若健康检查未通过，可查看脚本输出的 Docker 日志及备份目录。

> 默认项目目录：`/root/ysp-live/ysp-live-main`  
> 默认数据目录：`/root/ysp-live/ysp-live-main/data`  
> 备份目录：`/root/ysp-live/backups/`

---

## 🛠 手动部署（Docker Compose）

下载仓库源码后，在项目目录执行：

```sh
docker compose config
docker compose up -d --build
```

当前 Compose 配置使用：

- 镜像标签：`ysp-live:9.8-TMXK`
- 网络模式：`host`
- 服务端口：`8767`
- 默认数据目录：当前项目目录下的 `data`
- 健康接口：`http://127.0.0.1:8767/health`

如需把数据放在其他宿主机目录，可在项目目录的 `.env` 中设置：

```dotenv
YSP_HOST_DATA_DIR="/你的持久化数据目录"
```

然后重新执行：

```sh
docker compose up -d --build
```

---

## 🔗 服务地址

部署成功后，将设备 IP 替换为你的软路由或服务器局域网 IP：

| 用途 | 地址 |
|---|---|
| 全频道订阅 | `http://设备IP:8767/all.m3u` |
| 健康检查 | `http://设备IP:8767/health` |
| 运行诊断 | `http://设备IP:8767/diag` |

---

## ❓ 常见问题

### 1. 提示 Docker Compose 不存在

确认已安装 Docker Compose 插件（`docker compose`）或独立命令（`docker-compose`）。

### 2. 服务启动后无法访问

确认 8767 端口没有被其他程序占用，并检查：

```sh
docker ps -a
docker logs --tail 100 ysp-live
```

### 3. 更新后需要恢复旧数据

更新前的备份位于 `/root/ysp-live/backups/`。请先停止容器，再按需恢复对应备份目录中的数据；不要删除原备份。

---

## 🔗 官方网站与交流

- **官方网站**：[tmxk.pp.ua](https://tmxk.pp.ua)
- **联系我们 / 交流反馈**：[tmxk.pp.ua/d/10-lian-xi-wo-men](https://tmxk.pp.ua/d/10-lian-xi-wo-men)
- **TMXK 频道**：[TMXKの分享](https://t.me/tmxktg)
- **TG 推广 / 频道入口**：[@stymei](https://t.me/stymei)

---

## 📢 首发与原作者来源

- **项目首发**：TMXK
- **原代码及作者频道**：[Gary's Club Channel](https://t.me/garysclubchannel)

感谢原作者的代码与分享。本项目在原有基础上进行适配和维护，保留来源致谢。
