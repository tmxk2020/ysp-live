#!/bin/sh
# ysp-live 9.8-TMXK installer / updater
# Back up persistent data before replacing the container and verify /health.

CONTAINER_NAME="ysp-live"
INSTALL_BASE="${YSP_INSTALL_BASE:-/root/ysp-live}"
PROJECT_DIR="$INSTALL_BASE/ysp-live-main"
PORT="8767"
YSP_BRANCH="${YSP_BRANCH:-main}"
REPO_ZIP="https://codeload.github.com/tmxk2020/ysp-live/zip/refs/heads/$YSP_BRANCH"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
say_error() { printf "${RED}[错误] %s${RESET}\n" "$1"; }
say_ok() { printf "${GREEN}%s${RESET}\n" "$1"; }
say_warn() { printf "${YELLOW}%s${RESET}\n" "$1"; }

get_local_ip() {
    local_ip=$(uci get network.lan.ipaddr 2>/dev/null)
    [ -n "$local_ip" ] || local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -n "$local_ip" ] || local_ip="localhost"
    printf '%s' "$local_ip"
}
show_links() {
    IP=$(get_local_ip)
    echo ""
    echo "===================================================================="
    echo "  ysp-live 服务访问与管理链接"
    printf "  全频道订阅: http://%s:%s/all.m3u\n" "$IP" "$PORT"
    printf "  健康检查:   http://%s:%s/health\n" "$IP" "$PORT"
    printf "  运行诊断:   http://%s:%s/diag\n" "$IP" "$PORT"
    echo "===================================================================="
    echo ""
}
select_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_MODE="plugin"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_MODE="standalone"
    else
        say_error "未检测到 Docker Compose，请安装 compose 插件或 docker-compose。"
        return 1
    fi
}
compose() {
    if [ "$COMPOSE_MODE" = "plugin" ]; then docker compose "$@"; else docker-compose "$@"; fi
}
check_environment() {
    command -v docker >/dev/null 2>&1 || { say_error "未检测到 Docker。"; return 1; }
    command -v wget >/dev/null 2>&1 || { say_error "缺少 wget。"; return 1; }
    command -v unzip >/dev/null 2>&1 || { say_error "缺少 unzip。"; return 1; }
    docker info >/dev/null 2>&1 || { say_error "Docker 服务不可用，请先启动 Docker。"; return 1; }
    select_compose || return 1
}
backup_existing_data() {
    [ -n "$CONTAINER_ID" ] || return 0
    mount_info=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Type}}|{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    [ -n "$mount_info" ] || { say_warn "旧容器未发现 /app/data 挂载，将保留项目目录中的 data。"; return 0; }

    DATA_TYPE=${mount_info%%|*}
    DATA_SOURCE=${mount_info#*|}
    [ -d "$DATA_SOURCE" ] || { say_error "数据挂载路径不可读：$DATA_SOURCE"; return 1; }

    BACKUP_DIR="$INSTALL_BASE/backups/data-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR" || return 1
    cp -a "$DATA_SOURCE" "$BACKUP_DIR/data" || {
        say_error "旧数据备份失败，已中止更新；旧容器未删除。"
        return 1
    }
    say_ok "旧数据备份完成：$BACKUP_DIR/data"

    mkdir -p "$PROJECT_DIR/data" || return 1
    if [ "$DATA_TYPE" = "bind" ]; then
        case "$DATA_SOURCE" in *'"'*|*'\n'*) say_error "数据目录路径含不支持的字符：$DATA_SOURCE"; return 1 ;; esac
        if [ -f "$PROJECT_DIR/.env" ]; then
            grep -v '^YSP_HOST_DATA_DIR=' "$PROJECT_DIR/.env" > "$PROJECT_DIR/.env.tmp" 2>/dev/null || :
            mv "$PROJECT_DIR/.env.tmp" "$PROJECT_DIR/.env"
        fi
        printf 'YSP_HOST_DATA_DIR="%s"\n' "$DATA_SOURCE" >> "$PROJECT_DIR/.env"
    else
        # Named-volume data is copied to the persistent bind directory; original volume is untouched.
        cp -a "$DATA_SOURCE"/. "$PROJECT_DIR/data"/ || {
            say_error "旧数据卷迁移失败；原数据卷保留，更新已中止。"
            return 1
        }
    fi
}
download_and_stage() {
    TMP_DIR="$INSTALL_BASE/.ysp-live-update.$$"
    ZIP_FILE="$TMP_DIR/source.zip"
    mkdir -p "$TMP_DIR" || return 1
    trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
    echo "[2/5] 下载 GitHub 源码（分支：$YSP_BRANCH）..."
    wget -q --no-check-certificate "$REPO_ZIP" -O "$ZIP_FILE" || {
        say_error "源码下载失败，请检查网络或 GitHub 访问。"
        return 1
    }
    unzip -q "$ZIP_FILE" -d "$TMP_DIR" || { say_error "源码解压失败。"; return 1; }
    SRC_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/Dockerfile" ] && [ -f "$SRC_DIR/docker-compose.yml" ] || {
        say_error "源码缺少 Dockerfile 或 docker-compose.yml，已中止。"
        return 1
    }
    # Never overwrite runtime data with anything from the source archive.
    rm -rf "$SRC_DIR/data"
    mkdir -p "$PROJECT_DIR" || return 1
    cp -R "$SRC_DIR"/. "$PROJECT_DIR"/ || { say_error "复制项目文件失败。"; return 1; }
    [ -f "$PROJECT_DIR/ysp-live-v9.8-TMXK.py" ] && [ -f "$PROJECT_DIR/ysp-engine.js" ] || {
        say_error "核心程序文件不完整，已中止启动。"
        return 1
    }
}
wait_for_health() {
    attempt=1
    while [ "$attempt" -le 30 ]; do
        wget -q -O /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null && return 0
        sleep 2
        attempt=$((attempt + 1))
    done
    return 1
}
restore_previous_container() {
    [ -n "$OLD_CONTAINER_BACKUP" ] || return 0
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || :
    if docker inspect "$OLD_CONTAINER_BACKUP" >/dev/null 2>&1; then
        docker rename "$OLD_CONTAINER_BACKUP" "$CONTAINER_NAME" &&
            docker start "$CONTAINER_NAME" >/dev/null 2>&1
    fi
}

do_install() {
    echo "===================================================================="
    echo "  ysp-live 9.8-TMXK 安装 / 更新"
    echo "===================================================================="
    check_environment || return 1
    mkdir -p "$INSTALL_BASE" "$PROJECT_DIR" || return 1

    CONTAINER_ID=$(docker ps -aq -f "name=^/$CONTAINER_NAME$" | head -n 1)
    OLD_CONTAINER_BACKUP=""
    if [ -n "$CONTAINER_ID" ]; then
        echo "[1/5] 检查并备份现有数据..."
        backup_existing_data || return 1
    else
        echo "[1/5] 首次安装，准备数据目录..."
        mkdir -p "$PROJECT_DIR/data" || return 1
    fi

    download_and_stage || return 1
    echo "[3/5] 检查 Docker Compose 配置..."
    (cd "$PROJECT_DIR" && compose config >/dev/null) || {
        say_error "Compose 配置检查失败，旧容器尚未停止。"
        return 1
    }

    if [ -n "$CONTAINER_ID" ]; then
        OLD_CONTAINER_BACKUP="ysp-live-rollback-$(date +%Y%m%d-%H%M%S)"
        echo "[4/5] 暂停旧容器并保留回滚副本..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || {
            say_error "无法停止旧容器，已中止更新。"
            return 1
        }
        docker rename "$CONTAINER_NAME" "$OLD_CONTAINER_BACKUP" || {
            docker start "$CONTAINER_NAME" >/dev/null 2>&1 || :
            say_error "无法保留旧容器回滚副本，已中止更新。"
            return 1
        }
    else
        echo "[4/5] 构建并启动容器..."
    fi

    if ! (cd "$PROJECT_DIR" && compose up -d --build); then
        say_error "新容器构建或启动失败，正在尝试恢复旧容器..."
        restore_previous_container
        echo "数据备份保留在：$INSTALL_BASE/backups/"
        return 1
    fi

    echo "[5/5] 等待健康检查..."
    if wait_for_health; then
        say_ok "ysp-live 已启动，健康接口响应正常。"
        if [ -n "$OLD_CONTAINER_BACKUP" ]; then
            docker rm -f "$OLD_CONTAINER_BACKUP" >/dev/null 2>&1 || :
        fi
        show_links
        return 0
    fi

    say_error "新容器的 /health 在 60 秒内未响应，正在尝试恢复旧容器..."
    docker logs --tail 80 "$CONTAINER_NAME" 2>&1
    restore_previous_container
    echo "数据备份保留在：$INSTALL_BASE/backups/"
    return 1
}
show_menu() {
    echo "===================================================================="
    echo "  检测到 ysp-live 容器"
    echo "  1) 显示访问链接"
    echo "  2) 查看实时日志"
    echo "  3) 检查健康接口"
    echo "  4) 备份数据并更新"
    echo "  5) 退出"
    echo "===================================================================="
    printf "请选择 [1-5]: "
    read choice
    case "$choice" in
        1) show_links ;;
        2) docker logs -f "$CONTAINER_NAME" ;;
        3)
            if command -v curl >/dev/null 2>&1; then
                curl -fsS "http://127.0.0.1:$PORT/health" || say_error "健康接口暂不可用。"
            else
                wget -qO- "http://127.0.0.1:$PORT/health" || say_error "健康接口暂不可用。"
                echo ""
            fi
            ;;
        4) do_install ;;
        *) echo "已退出。" ;;
    esac
}

if ! check_environment; then exit 1; fi
if [ -n "$(docker ps -aq -f "name=^/$CONTAINER_NAME$" | head -n 1)" ]; then
    show_menu
else
    echo "未检测到 ysp-live 容器，将执行首次安装。"
    printf "是否继续？[y/N]: "
    read confirm
    case "$confirm" in [yY]|[yY][eE][sS]) do_install ;; *) echo "已取消安装。" ;; esac
fi
