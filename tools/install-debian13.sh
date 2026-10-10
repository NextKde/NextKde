#!/usr/bin/env bash
#
# install-debian13.sh —— KOS (NextKde) 在 Debian 13 (trixie) 上的零交互安装脚本
#
# 目标：从一台干净的 Debian 13 出发，一条命令走到可用的 KOS 桌面。
#   1. 环境预检（发行版 / 架构 / 磁盘 / apt 源）
#   2. 准备 sudo（KDE 下走 askpass，全程不再弹密码框）
#   3. 探测本地代理（国内网络下 clone 与 Go 模块拉取需要）
#   4. 安装构建依赖 + 运行时集成（含 Quickshell 0.3.x）
#   5. clone 仓库（已存在则原地更新）
#   6. 构建并安装：./tools/kosctl install
#   7. 校验产物并打印后续步骤
#
# 用法：
#   bash install-debian13.sh [选项]
#   bash install-debian13.sh -h            # 查看全部选项
#
# 典型用法（最省事）：
#   bash install-debian13.sh
#   bash install-debian13.sh --all --start          # 连锁屏/独立应用一起装，装完立即生效
#   bash install-debian13.sh --check                # 只做预检，不改动系统
#
# ────────────────────────────────────────────────────────────────────────────
# 设计约束（必须遵守，改脚本时别绕开）
#
# 必须以“桌面登录用户”身份运行，不要 sudo。理由：
#   KOS 的 shell 配置落在 ~/.config/quickshell/kos，systemd 服务是 *用户* 单元，
#   KDE 桌面接管要改 ~/.config/plasma-*-appletsrc —— 这些全部属于你个人的
#   HOME。用 root 跑会把 root 的 HOME 写进去（结果就是你自己登录后看不到
#   KOS），还可能让 plasma 配置变成 root 所有而损坏桌面。脚本只在确实需要
#   时自己调用 sudo（装包、把 KWin 插件拷进 /usr）。
#
# 因此 KOS_PREFIX 默认为 $HOME/.local。deploy_artifacts 不用 sudo 写
# $prefix，把前缀指到 /usr 这类 root 拥有的目录会在部署阶段权限报错；
# 脚本对 HOME 之外的前缀会直接拒绝并说明原因，而不是先动手再炸。
#
# ── sudo 策略 ──
# 有终端时优先让用户在终端里输密码。中文 locale 下 ksshaskpass 认不出
# sudo 的本地化提示语（“[sudo] xxx 的密码：” → Unable to parse phrase），
# 图形授权框会直接失败；终端交互不依赖提示语解析，永远可用。
# 无终端时才退回 askpass，并且钉 LC_ALL=C 让提示语保持英文。
# 授权一次后用后台保活维持时间戳，构建十几分钟也不会再弹框。
#
# ── 代理策略 ──
# 只作用于 git 与 kosctl，不导出到全局。原因是两者需求相反：
#   · git clone 与 kosctl 构建（它用 curl 从 GitHub 拉 pin 死的
#     ONNX Runtime SDK，只要 KOS_BUILD_SPATIAL 不是 off 就必然触发）
#     必须走代理，否则国内网络就是几轮 30 秒超时；
#   · apt 走国内镜像直连更快，挂上代理反而可能失败。
# 探测顺序：环境变量 → github.com 直连 → 依次试常见本地端口。
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_VERSION="1.0.0"

# ── 默认值 ──────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/SuceV587/NextKde.git"
BRANCH="main"
CLONE_DIR="${HOME}/NextKde"
KOS_PREFIX="${KOS_PREFIX:-}"
KOS_SPATIAL="${KOS_BUILD_SPATIAL:-auto}"   # auto | on | off
INSTALL_ALL=0        # --all：额外装锁屏与独立应用
DO_START=0           # --start：装完立刻 kosctl start
CHECK_ONLY=0         # --check：只预检
SKIP_DEPS=0          # --no-deps：跳过 apt 依赖安装
FORCE=0              # --force：跳过发行版检查
USE_PROXY="auto"     # auto | off | <url>
GIT_MIRROR=""        # --mirror https://ghfast.top/ 之类的前缀
LOG_FILE=""

# ── 输出与日志 ──────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''
fi

log_init() {
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/kos"
    mkdir -p "$state_dir"
    LOG_FILE="${KOS_INSTALL_LOG:-$state_dir/install-debian13-$(date +%Y%m%d-%H%M%S).log}"
    : >"$LOG_FILE"
    printf 'KOS Debian 13 安装日志  %s\n' "$(date -Is)" >>"$LOG_FILE"
}

# 参数解析阶段就可能 die（例如 --repo 缺值），那时 log_init 还没跑，
# LOG_FILE 还是空串，直接 >>"" 会多抛一条 shell 报错，所以这里先挡一下。
logline() {
    [[ -n "$LOG_FILE" ]] || return 0
    printf '%s\n' "$*" >>"$LOG_FILE"
}
step() { printf '\n%s=== %s ===%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET"; logline ""; logline "=== $* ==="; }
info() { printf '  %s\n' "$*";                 logline "  $*"; }
ok()   { printf '  %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*";  logline "  ok   $*"; }
warn() { printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; logline "  warn $*"; }
err()  { printf '  %s✘%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; logline "  err  $*"; }
die()  { err "$*"; printf '\n  安装日志：%s\n' "${LOG_FILE:-（未初始化）}" >&2; exit 1; }

# 执行外部命令：输出直通终端，同时落盘。退出码取管道第一段。
run() {
    printf '%s   $ %s%s\n' "$C_DIM" "$*" "$C_RESET"
    logline "   \$ $*"
    set +e
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}
    set -e
    return "$rc"
}

usage() {
    cat <<'EOF'
Usage: bash install-debian13.sh [选项]

KOS (NextKde) 在 Debian 13 (trixie) 上的零交互安装脚本：预检 → 装依赖 →
clone → 构建 → 安装 → 校验。

克隆与安装位置
  --dir <路径>         clone 到哪里（默认 $HOME/NextKde）
  --repo <URL>         仓库地址（默认官方 upstream）
  --branch <名称>      分支或 tag（默认 main）
  --mirror <前缀>      clone 失败时使用镜像前缀，例：--mirror https://ghfast.top/
  --prefix <路径>      安装前缀 KOS_PREFIX（默认 $HOME/.local）

安装内容
  --spatial <模式>     景深/空间壁纸：auto（默认）| on | off
                       auto/on 会从 GitHub 拉取 ONNX Runtime SDK（需要代理）；
                       --spatial off 可完全跳过这个下载
  --all                核心之外再装锁屏与独立应用
  --start              安装完成后立即 ./tools/kosctl start（不必注销）
  --no-deps            跳过 apt 依赖安装（依赖已备齐时用）

网络
  --proxy [URL]        强制使用代理；不带 URL 表示走自动探测
  --no-proxy           完全不用代理（直连）

其它
  --check              只做环境预检，不改动系统
  --force              跳过发行版检查（非 Debian 13 上强行继续）
  -h, --help           显示本帮助

环境变量
  KOS_PREFIX          安装前缀（同 --prefix）
  KOS_BUILD_SPATIAL   auto | ON | OFF（同 --spatial）
  KOS_LOG / KOS_INSTALL_LOG  日志路径

务必以桌面登录用户身份运行，不要加 sudo —— 原因见脚本头部注释。
EOF
}

# ── 参数解析 ────────────────────────────────────────────────────────────────
parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --dir)       [[ -n "${2:-}" ]] || die "--dir 需要一个路径"; CLONE_DIR="$2"; shift 2 ;;
            --repo)      [[ -n "${2:-}" ]] || die "--repo 需要一个地址"; REPO_URL="$2"; shift 2 ;;
            --branch)    [[ -n "${2:-}" ]] || die "--branch 需要一个名称"; BRANCH="$2"; shift 2 ;;
            --mirror)    [[ -n "${2:-}" ]] || die "--mirror 需要一个前缀"; GIT_MIRROR="$2"; shift 2 ;;
            --prefix)    [[ -n "${2:-}" ]] || die "--prefix 需要一个路径"; KOS_PREFIX="$2"; shift 2 ;;
            --spatial)   [[ -n "${2:-}" ]] || die "--spatial 需要 auto|on|off"; KOS_SPATIAL="${2,,}"; shift 2 ;;
            --proxy)
                if [[ -n "${2:-}" && "$2" != -* ]]; then USE_PROXY="$2"; shift 2
                else USE_PROXY="auto"; shift; fi ;;
            --no-proxy)  USE_PROXY="off"; shift ;;
            --all)       INSTALL_ALL=1; shift ;;
            --start)     DO_START=1; shift ;;
            --no-deps)   SKIP_DEPS=1; shift ;;
            --check)     CHECK_ONLY=1; shift ;;
            --force)     FORCE=1; shift ;;
            -h|--help)   usage; exit 0 ;;
            *)           printf '未知选项：%s\n\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
    done
    case "$KOS_SPATIAL" in
        auto|on|off) ;;
        ON|On) KOS_SPATIAL="on" ;;
        OFF|Off) KOS_SPATIAL="off" ;;
        *) die "--spatial 只接受 auto|on|off，收到：$KOS_SPATIAL" ;;
    esac
    [[ "$CLONE_DIR" == /* ]] || die "--dir 需要绝对路径"
}

# ── sudo：askpass + PATH 垫片 + 时间戳保活 ──────────────────────────────────
SUDO_SHIM_DIR=""
SUDO_KEEPALIVE_PID=""

sudo_cleanup() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    [[ -n "$SUDO_SHIM_DIR" ]] && rm -rf "$SUDO_SHIM_DIR" || true
}

# 只做身份检查，不触发授权：--check 也要求非 root，但不需要密码。
require_non_root() {
    [[ "${EUID}" -ne 0 ]] && return 0
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
        die "请不要用 sudo 运行：KOS 的配置必须写进你自己的 HOME。
    被 sudo 提升成 root 后 HOME 变成 /root，你会装出一个自己登录后看不到的 KOS。
    请直接以桌面用户身份执行本脚本，需要权限时脚本自己会调 sudo。"
    fi
    die "请不要以 root 身份运行本脚本（原因同 --help 末尾的说明）。"
}

setup_sudo() {
    if [[ -z "${SUDO_ASKPASS:-}" && -x /usr/bin/ksshaskpass ]]; then
        export SUDO_ASKPASS=/usr/bin/ksshaskpass
    fi
    if [[ -n "${SUDO_ASKPASS:-}" && ! -x "${SUDO_ASKPASS}" ]]; then
        warn "SUDO_ASKPASS=${SUDO_ASKPASS} 不可执行，忽略它"
        unset SUDO_ASKPASS
    fi

    # 有终端时优先让用户在终端里输密码。原因很实际：中文 locale 下
    # ksshaskpass 认不出 sudo 的本地化提示语
    # （“[sudo] chengtian 的密码：” → Unable to parse phrase），图形框会直接失败。
    # 终端交互不依赖任何提示语解析，永远可用。
    if [[ -t 0 ]]; then
        info "需要管理员权限，请在终端输入密码（只会问这一次）"
        if /usr/bin/sudo -v; then
            ok "sudo 已授权（终端输入）"
            start_sudo_keepalive
            return 0
        fi
        warn "终端授权没成功，改用图形授权框重试"
    fi

    # 无终端（例如从 IDE 里启动）时只能走 askpass。
    # LC_ALL=C 让 sudo 用英文提示语，ksshaskpass 才认得出来——这是让图形
    # 授权在中文系统上真正可用的关键。
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
        info "需要管理员权限（将弹出图形授权框）"
        if LC_ALL=C /usr/bin/sudo -A -v; then
            ok "sudo 已授权（图形授权）"

            # kosctl 内部写死了 `sudo`。无 tty 时把它垫成 `sudo -A`，
            # 否则它在构建中途会因为没有终端而直接失败。
            # 垫片里带 LC_ALL=C：让 sudo 的提示语保持英文，ksshaskpass 才认得出。
            # 只作用于 sudo 自己，不影响 kosctl 的中文输出。
            SUDO_SHIM_DIR=$(mktemp -d)
            cat >"$SUDO_SHIM_DIR/sudo" <<'SHIM'
#!/bin/sh
exec env LC_ALL=C /usr/bin/sudo -A "$@"
SHIM
            chmod 0755 "$SUDO_SHIM_DIR/sudo"
            export PATH="$SUDO_SHIM_DIR:$PATH"
            info "已挂载 sudo 图形授权垫片"
            start_sudo_keepalive
            return 0
        fi
    fi

    die "sudo 授权失败，无法安装依赖与 KWin 插件。
    可手动验证：sudo -v
    若图形授权框报 “Unable to parse phrase”，请改为在终端里运行本脚本。"
}

# 保活：构建可能跑十几分钟，时间戳一过期就会再弹一次授权框。
start_sudo_keepalive() {
    (
        while :; do
            sleep 45
            /usr/bin/sudo -n true 2>/dev/null || exit 0
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
    trap sudo_cleanup EXIT
}

# ── 预检 ────────────────────────────────────────────────────────────────────
OS_ID=""; OS_VERSION_ID=""; OS_CODENAME=""; OS_PRETTY=""; APT_SUITE_HINT=""

read_os_release() {
    [[ -r /etc/os-release ]] || die "读不到 /etc/os-release，无法判断发行版"
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"; OS_VERSION_ID="${VERSION_ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"; OS_PRETTY="${PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"
}

# apt 源里出现 sid/unstable 时给出显著提示：这种混搭会把 unstable 的包
# 一并拉进来（本机历史上就出现过 90+ 个包的连带升级）。
scan_apt_suites() {
    local files=() f
    [[ -f /etc/apt/sources.list ]] && files+=(/etc/apt/sources.list)
    while IFS= read -r f; do files+=("$f"); done < <(
        find /etc/apt/sources.list.d -maxdepth 1 -type f \
            \( -name '*.list' -o -name '*.sources' \) 2>/dev/null | sort
    )
    (( ${#files[@]} )) || return 0
    local suites
    suites=$(
        {
            # 老格式：deb <uri> <suite> [components]
            grep -hE '^[[:space:]]*deb(-src)?[[:space:]]' "${files[@]}" 2>/dev/null \
                | awk '{print $3}'
            # deb822：Suites: a b
            grep -hE '^[[:space:]]*Suites:' "${files[@]}" 2>/dev/null \
                | sed 's/^[[:space:]]*Suites:[[:space:]]*//'
        } | tr ' ' '\n' | grep -v '^$' | sort -u
    ) || true
    APT_SUITE_HINT="$suites"
    if grep -qE '(^|[[:space:]])(sid|unstable)([[:space:]]|$)' <<<"$suites"; then
        warn "检测到 apt 源指向 sid/unstable，与 os-release 的 $OS_VERSION_ID/$OS_CODENAME 不一致"
        warn "继续安装可能连带升级大量系统包（含 systemd）。若要纯净，请先把源改回 trixie。"
    fi
}

preflight() {
    step "环境预检"
    read_os_release
    info "发行版：$OS_PRETTY（ID=$OS_ID VERSION_ID=$OS_VERSION_ID CODENAME=${OS_CODENAME:-未知}）"

    if [[ "$OS_ID" != debian ]]; then
        if (( FORCE )); then
            warn "非 Debian 发行版（$OS_ID），因 --force 继续"
        else
            die "本脚本只面向 Debian 13 (trixie)，当前是 ${OS_PRETTY}。
    确要继续请加 --force。"
        fi
    elif [[ "$OS_VERSION_ID" != "13" ]]; then
        if (( FORCE )); then
            warn "Debian 版本是 $OS_VERSION_ID，不是 13，因 --force 继续"
        else
            die "本脚本只面向 Debian 13 (trixie)，当前 VERSION_ID=$OS_VERSION_ID。
    Debian 12 的 Qt6/KF6 版本低于 KOS 要求，请勿在 12 上安装。
    确要继续请加 --force。"
        fi
    else
        ok "Debian 13 (trixie) 已确认"
    fi

    local arch; arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$arch" in
        amd64|arm64) ok "架构：$arch" ;;
        *) warn "架构 $arch 未经测试（KOS 主要在 amd64 上验证）" ;;
    esac

    command -v apt-get >/dev/null 2>&1 || die "找不到 apt-get，这不是 Debian 系系统"

    scan_apt_suites

    # 磁盘：构建 + 部署大约需要 3~5 GB，留出余量
    local target="$CLONE_DIR"
    while [[ ! -e "$target" && "$target" != "/" ]]; do target=$(dirname "$target"); done
    local avail_kb
    avail_kb=$(df -Pk -- "$target" 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -n "$avail_kb" ]]; then
        local avail_gb=$(( avail_kb / 1024 / 1024 ))
        if (( avail_gb < 6 )); then
            die "可用磁盘空间仅 ${avail_gb} GB（$target），构建 KOS 至少需要 6 GB"
        fi
        ok "可用磁盘空间：${avail_gb} GB（$target）"
    fi

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        ok "当前是 Wayland 会话"
    else
        warn "当前会话类型为 ${XDG_SESSION_TYPE:-未知}；KOS 是 Wayland 桌面 Shell，需在 Plasma 6 Wayland 会话下使用"
    fi

    if command -v plasmashell >/dev/null 2>&1 || [[ -n "${KDE_FULL_SESSION:-}" ]]; then
        ok "检测到 KDE Plasma 环境"
    else
        warn "未检测到 Plasma 环境；KOS 依赖 KWin 6，建议在 KDE Plasma 6 上使用"
    fi

    if [[ -n "$KOS_PREFIX" ]]; then
        validate_prefix
    else
        KOS_PREFIX="$HOME/.local"
        info "安装前缀：$KOS_PREFIX（默认；可用 --prefix 覆盖）"
    fi

    info "仓库：$REPO_URL  分支：$BRANCH"
    info "克隆到：$CLONE_DIR"
}

validate_prefix() {
    [[ "$KOS_PREFIX" == /* ]] || die "--prefix 需要绝对路径"

    # KOS 是“每用户”设计的：shell 配置写 ~/.config/quickshell/kos、服务是
    # systemd 用户单元、桌面接管改 ~/.config/plasma-*-appletsrc。把产物装到
    # HOME 之外不会让别的用户受益，只会让系统目录与自己的配置版本错位，
    # 因此这里默认拒绝，要求 --force 才放行。
    # 注意：不能只用 -w 判断——本机 /usr 的属主被改过，-w 会误判为可写。
    if [[ "$KOS_PREFIX" != "$HOME"/* ]]; then
        if (( FORCE )); then
            warn "前缀 $KOS_PREFIX 不在 HOME 内（--force 已放行）"
        else
            die "前缀 $KOS_PREFIX 不在你的 HOME 内。
    KOS 的 shell 配置、systemd 用户服务和桌面接管配置都写在你自己的 HOME 里，
    产物装到 HOME 之外只会造成系统目录与用户配置错位，不会带来任何好处。
    推荐值就是默认值：$HOME/.local
    确要如此请加 --force。"
        fi
    fi

    local probe="$KOS_PREFIX"
    while [[ ! -e "$probe" && "$probe" != "/" ]]; do probe=$(dirname "$probe"); done
    if [[ ! -w "$probe" ]]; then
        die "前缀 $KOS_PREFIX 不可写（最近的存在路径是 $probe）。
    部署阶段（deploy_artifacts）不用 sudo 写 \$prefix，前缀必须由你自己的用户拥有。"
    fi
    ok "安装前缀可用：$KOS_PREFIX"
}

# ── 代理 ────────────────────────────────────────────────────────────────────
PROXY_URL=""
GIT_NET_ARGS=()

detect_proxy() {
    step "网络与代理"
    if [[ "$USE_PROXY" == "off" ]]; then
        info "--no-proxy：不使用代理"
    elif [[ "$USE_PROXY" != "auto" ]]; then
        PROXY_URL="$USE_PROXY"
        ok "使用指定代理：$PROXY_URL"
    elif [[ -n "${https_proxy:-}" || -n "${http_proxy:-}" ]]; then
        PROXY_URL="${https_proxy:-$http_proxy}"
        ok "沿用环境中的代理：$PROXY_URL"
    else
        if curl -fsS -m 8 -o /dev/null https://github.com 2>/dev/null; then
            ok "GitHub 可直连，不使用代理"
        else
            local candidate
            for candidate in \
                http://127.0.0.1:7890 http://127.0.0.1:7897 http://127.0.0.1:7891 \
                http://127.0.0.1:10809 http://127.0.0.1:20171 http://127.0.0.1:1080
            do
                if curl -fsS -m 6 -x "$candidate" -o /dev/null https://github.com 2>/dev/null; then
                    PROXY_URL="$candidate"
                    break
                fi
            done
            if [[ -n "$PROXY_URL" ]]; then
                ok "自动探测到可用代理：$PROXY_URL"
            else
                warn "GitHub 直连不通，也没探测到本地代理；clone 可能失败（可用 --proxy 指定）"
            fi
        fi
    fi
    if [[ -n "$PROXY_URL" ]]; then
        # 只作用于 git：apt 走国内镜像直连更快，把 http_proxy 导出反而可能拖慢甚至失败。
        GIT_NET_ARGS=(-c "http.proxy=$PROXY_URL" -c "https.proxy=$PROXY_URL")
    fi
}

# ── apt：刷新、Quickshell、依赖 ─────────────────────────────────────────────
APT_ENV=(env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none
         NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1)

apt_candidate() {
    local candidate
    candidate=$(apt-cache policy "$1" 2>/dev/null \
        | awk '/^[[:space:]]*Candidate:/{print $2; exit}')
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

apt_update() {
    if run sudo "${APT_ENV[@]}" apt-get \
            -o Acquire::Retries=3 update; then
        return 0
    fi
    if [[ -n "$PROXY_URL" ]]; then
        warn "apt-get update 失败，改用代理重试一次"
        run sudo "${APT_ENV[@]}" apt-get \
            -o "Acquire::http::Proxy=$PROXY_URL" \
            -o "Acquire::https::Proxy=$PROXY_URL" \
            -o Acquire::Retries=3 update
        return $?
    fi
    return 1
}

enable_backports() {
    local suites="$1"   # 例如 trixie-backports
    if grep -rqs -- "$suites" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        info "$suites 已在 apt 源中"
        return 0
    fi
    [[ -n "$OS_CODENAME" ]] || die "无法确定发行版代号，不能自动启用 backports"
    local codename="$OS_CODENAME"
    local src="/etc/apt/sources.list.d/${suites}.sources"
    local pin="/etc/apt/preferences.d/90-${suites}.pref"
    info "写入 $src（deb822 格式，用 Debian 官方签名密钥）"
    sudo tee "$src" >/dev/null <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${suites}
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    # backports 的标准钉法：只有显式 -t 才会用到，绝不会无意中升级系统包。
    info "写入 $pin（Pin-Priority: 100）"
    sudo tee "$pin" >/dev/null <<EOF
Package: *
Pin: release n=${suites}
Pin-Priority: 100
EOF
    info "已启用 ${suites}（源代号 ${codename}）"
}

ensure_quickshell() {
    step "Quickshell 0.3.x"

    local qs_bin="" version=""
    qs_bin=$(command -v qs || command -v quickshell || true)
    if [[ -n "$qs_bin" ]]; then
        version=$("$qs_bin" --version 2>&1 | head -n1 || true)
        if [[ "$version" == *"0.3."* ]]; then
            ok "已可用：$qs_bin（$version）"
            return 0
        fi
        warn "已安装的 Quickshell 版本不是 0.3.x：$version"
    fi

    if apt_candidate quickshell; then
        info "apt 源中已有 quickshell，直接安装"
        run sudo "${APT_ENV[@]}" apt-get install -y quickshell || warn "quickshell 安装返回非零"
    else
        warn "当前 apt 源没有 quickshell，尝试启用 ${OS_CODENAME:-trixie}-backports"
        local suites="${OS_CODENAME:-trixie}-backports"
        enable_backports "$suites" || true
        apt_update || die "启用 backports 后 apt-get update 失败"
        if apt_candidate quickshell; then
            info "从 $suites 安装 quickshell"
            run sudo "${APT_ENV[@]}" apt-get install -y -t "$suites" quickshell \
                || warn "quickshell 安装返回非零"
        else
            warn "$suites 里仍然找不到 quickshell"
        fi
    fi

    qs_bin=$(command -v qs || command -v quickshell || true)
    if [[ -z "$qs_bin" ]]; then
        die "Quickshell 未能安装成功，而 KOS 的 shell 单元必须有它。
    手动兜底方案（任选其一）：
      1) sudo apt-get install -t ${OS_CODENAME:-trixie}-backports quickshell
      2) 按 https://quickshell.org/docs/ 从源码构建
    装好后重新执行本脚本即可。"
    fi
    version=$("$qs_bin" --version 2>&1 | head -n1 || true)
    ok "Quickshell 就绪：$qs_bin（$version）"
}

# 与 tools/kosctl 的 Debian 分支保持一致。这里刻意在脚本内自带一份：
# upstream main 的 kosctl 还没有 apt 分支，而本脚本要求“从零可用”。
debian_core_build_packages=(
    git cmake ninja-build g++ golang-go curl patchelf pkg-config
    extra-cmake-modules libwayland-dev wayland-protocols libxkbcommon-dev
    qt6-base-dev qt6-declarative-dev qt6-quick3d-dev qt6-svg-dev qt6-wayland-dev
    qt6-image-formats-plugins qt6-5compat-dev libqt6svg6
    qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts
    qml6-module-qtquick-dialogs qml6-module-qtquick-window qml6-module-qtquick-effects
    qml6-module-qtqml-models qml6-module-qtqml-workerscript
    qml6-module-qt5compat-graphicaleffects
    libkf6windowsystem-dev libkf6iconthemes-dev libkf6globalaccel-dev
    libkf6kio-dev libkf6calendarcore-dev
)

debian_kwin_build_packages=(
    kwin-dev libdrm-dev libgbm-dev libepoxy-dev
    libxkbcommon-x11-dev
    libkf6config-dev libkf6i18n-dev libkf6guiaddons-dev libkf6kcmutils-dev
    libkf6coreaddons-dev libkdecorations3-dev libplasma-dev
    gettext libvulkan-dev zlib1g-dev
    libxcb1-dev libxcb-composite0-dev libxcb-randr0-dev libxcb-res0-dev
    libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-damage0-dev
    libxcb-render0-dev libxcb-shape0-dev libxcb-cursor-dev libxcb-keysyms1-dev
    libxcb-icccm4-dev libxcb-image0-dev libxcb-util-dev
)

# 运行时集成。缺了 KOS 仍能启动，但网络/音量/蓝牙/剪贴板/截图会残废，
# 既然目标是“完整”，就一起装上。
debian_runtime_packages=(
    network-manager wireplumber bluez brightnessctl
    wl-clipboard cliphist xdg-utils kde-spectacle
    libqt6sql6-sqlite qml6-module-qtquick-dialogs
    "libglib2.0-0t64 libglib2.0-0"
)

debian_spatial_build_packages=( libopencv-dev )

# 多个候选名取仓库中真实存在的那个（t64 改名、包更名都靠它兜底）。
resolve_pkg() {
    local -a candidates=()
    local candidate
    read -ra candidates <<<"$1"
    for candidate in "${candidates[@]}"; do
        if apt-cache show "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    printf '%s' "${candidates[0]:-}"
    return 1
}

install_dependencies() {
    step "安装构建与运行时依赖"

    if ! compgen -G '/var/lib/apt/lists/*_Packages*' >/dev/null 2>&1; then
        info "apt 包列表为空，先刷新"
        apt_update || die "apt-get update 失败，请检查软件源与网络"
    fi

    local -a want=("${debian_core_build_packages[@]}")
    want+=("${debian_kwin_build_packages[@]}")
    want+=("${debian_runtime_packages[@]}")
    case "$KOS_SPATIAL" in
        on)  want+=("${debian_spatial_build_packages[@]}") ;;
        auto) want+=("${debian_spatial_build_packages[@]}") ;;
        off) ;;
    esac

    local pkg resolved
    local -a resolved_all=() unavailable=()
    for pkg in "${want[@]}"; do
        if resolved=$(resolve_pkg "$pkg"); then
            resolved_all+=("$resolved")
        else
            unavailable+=("$pkg")
        fi
    done
    if (( ${#unavailable[@]} > 0 )); then
        warn "以下包在当前 apt 源中不可用，已跳过：${unavailable[*]}"
    fi

    # 去重后只装缺的
    local -a unique=() missing=()
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && unique+=("$pkg")
    done < <(printf '%s\n' "${resolved_all[@]}" | awk 'NF && !seen[$0]++')

    for pkg in "${unique[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if (( ${#missing[@]} == 0 )); then
        ok "依赖已齐备（共检查 ${#unique[@]} 个包）"
        return 0
    fi
    info "需要安装 ${#missing[@]} / ${#unique[@]} 个包"
    if ! run sudo "${APT_ENV[@]}" apt-get install -y "${missing[@]}"; then
        if [[ -n "$PROXY_URL" ]]; then
            warn "apt 直连安装失败，改用代理重试一次"
            run sudo "${APT_ENV[@]}" apt-get \
                -o "Acquire::http::Proxy=$PROXY_URL" \
                -o "Acquire::https::Proxy=$PROXY_URL" \
                install -y "${missing[@]}" \
                || die "依赖安装失败，详见日志：$LOG_FILE"
        else
            die "依赖安装失败，详见日志：$LOG_FILE"
        fi
    fi
    ok "依赖安装完成"
}

# ── clone / 更新仓库 ────────────────────────────────────────────────────────
clone_repo() {
    step "获取 KOS 源码"

    if [[ -d "$CLONE_DIR/.git" ]]; then
        info "已存在 git 仓库：$CLONE_DIR"
        if ! git -C "$CLONE_DIR" diff --quiet || ! git -C "$CLONE_DIR" diff --cached --quiet; then
            warn "工作区有未提交改动，跳过更新，直接使用当前检出"
        else
            run git -C "$CLONE_DIR" "${GIT_NET_ARGS[@]}" fetch --prune origin \
                || warn "fetch 失败，使用本地已有提交"
            if git -C "$CLONE_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
                run git -C "$CLONE_DIR" checkout "$BRANCH" || true
            fi
            run git -C "$CLONE_DIR" "${GIT_NET_ARGS[@]}" pull --ff-only \
                || warn "无法快进到最新，沿用当前检出"
        fi
    elif [[ -e "$CLONE_DIR" ]]; then
        die "$CLONE_DIR 已存在且不是 git 仓库。
    请移走它，或用 --dir 指定另一个目录。"
    else
        mkdir -p "$(dirname "$CLONE_DIR")"
        local url="$REPO_URL"
        info "克隆 $url（分支 $BRANCH）→ $CLONE_DIR"
        if ! run git "${GIT_NET_ARGS[@]}" clone --branch "$BRANCH" --depth 1 \
                "$url" "$CLONE_DIR"; then
            rm -rf "$CLONE_DIR"
            if [[ -n "$GIT_MIRROR" ]]; then
                warn "直连克隆失败，改用镜像前缀 $GIT_MIRROR"
                url="${GIT_MIRROR%/}/${REPO_URL}"
                run git "${GIT_NET_ARGS[@]}" clone --branch "$BRANCH" --depth 1 \
                    "$url" "$CLONE_DIR" \
                    || die "克隆失败。可尝试：--proxy http://127.0.0.1:7890 或 --mirror <前缀>"
            else
                die "克隆失败。国内网络常见原因：GitHub 不可直连。
    可尝试：
      bash install-debian13.sh --proxy http://127.0.0.1:7890
      bash install-debian13.sh --mirror https://ghfast.top/"
            fi
        fi
    fi

    [[ -x "$CLONE_DIR/tools/kosctl" ]] \
        || die "仓库结构异常：$CLONE_DIR/tools/kosctl 不存在或不可执行"
    local head
    head=$(git -C "$CLONE_DIR" log -1 --format='%h %s' 2>/dev/null || true)
    ok "源码就绪：${head:-（无法读取提交信息）}"
}

# ── 构建 + 安装 ─────────────────────────────────────────────────────────────
kos_env() {
    local -a env_pairs=("KOS_PREFIX=$KOS_PREFIX")
    case "$KOS_SPATIAL" in
        on)  env_pairs+=("KOS_BUILD_SPATIAL=ON") ;;
        off) env_pairs+=("KOS_BUILD_SPATIAL=OFF") ;;
    esac
    # 构建期 kosctl 会用 curl 从 GitHub 拉取 pin 死的 ONNX Runtime SDK
    # （只要 KOS_BUILD_SPATIAL 不是 off 就必然触发）。国内网络不挂代理就是
    # 四轮 30 秒连接超时然后失败，所以把探测到的代理只传给 kosctl；
    # 不导出到全局，是为了让 apt 继续直连国内镜像（挂代理反而更慢或不通）。
    if [[ -n "$PROXY_URL" ]]; then
        env_pairs+=("http_proxy=$PROXY_URL" "https_proxy=$PROXY_URL"
                    "all_proxy=$PROXY_URL"
                    "no_proxy=${no_proxy:-localhost,127.0.0.1,::1}")
    fi
    printf '%s\n' "${env_pairs[@]}"
}

kosctl_run() {
    local -a env_pairs=()
    mapfile -t env_pairs < <(kos_env)
    ( cd "$CLONE_DIR" && run env "${env_pairs[@]}" ./tools/kosctl "$@" )
}

build_and_install() {
    step "构建并安装"
    info "前缀 KOS_PREFIX=$KOS_PREFIX；景深构建 KOS_BUILD_SPATIAL=$KOS_SPATIAL"
    if [[ -n "$PROXY_URL" && "$KOS_SPATIAL" != "off" ]]; then
        info "构建期会经代理 $PROXY_URL 拉取 ONNX Runtime SDK（景深壁纸依赖）"
    elif [[ "$KOS_SPATIAL" == "off" ]]; then
        info "景深关闭，跳过 ONNX Runtime SDK 下载"
    fi
    info "首次构建通常需要几分钟，输出同时写入日志"

    kosctl_run doctor || warn "doctor 报告了缺失项（不致命，继续安装）"

    kosctl_run install || die "kosctl install 失败。构建输出已完整写入：$LOG_FILE"

    if (( INSTALL_ALL )); then
        info "额外安装：锁屏"
        kosctl_run install lockscreen || warn "锁屏安装失败（核心桌面不受影响）"
        info "额外安装：独立应用"
        kosctl_run install apps || warn "独立应用安装失败（核心桌面不受影响）"
    fi
}

verify_install() {
    step "校验安装结果"
    local cfg="$HOME/.config"
    local failed=0

    local f
    for f in libexec/kos-platform libexec/kos-data-service bin/kos-settings; do
        if [[ -x "$KOS_PREFIX/$f" ]]; then ok "二进制 $KOS_PREFIX/$f"
        else warn "缺少 $KOS_PREFIX/$f"; failed=1; fi
    done

    for f in kos-platform.service kos-data.service kos-shell.service; do
        if [[ -f "$cfg/systemd/user/$f" ]]; then ok "用户服务 $f"
        else warn "用户服务 $f 未部署"; failed=1; fi
    done

    if [[ -d "$cfg/quickshell/kos" ]]; then ok "shell 配置 $cfg/quickshell/kos"
    else warn "shell 配置未部署"; failed=1; fi

    if command -v systemctl >/dev/null 2>&1; then
        local unit state
        for unit in kos-platform.service kos-data.service kos-shell.service; do
            state=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
            info "systemctl --user is-enabled $unit → ${state:-unknown}"
        done
    fi
    return "$failed"
}

print_summary() {
    local cfg="$HOME/.config"
    printf '\n'
    printf '%s╭─ 安装完成 ────────────────────────────────────────────╮%s\n' "$C_BOLD$C_GREEN" "$C_RESET"
    printf '  源码    %s\n' "$CLONE_DIR"
    printf '  前缀    %s\n' "$KOS_PREFIX"
    printf '  Shell   %s\n' "$cfg/quickshell/kos"
    printf '  日志    %s\n' "$LOG_FILE"
    printf '%s╰───────────────────────────────────────────────────────╯%s\n' "$C_BOLD$C_GREEN" "$C_RESET"
    printf '\n  下一步：\n'
    printf '    1) 注销并重新登录（或重启）—— KWin 特效与桌面接管在下次登录生效\n'
    printf '    2) 不想注销：cd %s && ./tools/kosctl start\n' "$CLONE_DIR"
    printf '    3) 排查问题：cd %s && ./tools/kosctl doctor\n' "$CLONE_DIR"
    printf '    4) 以后升级：重新执行本脚本，或 cd %s && git pull && ./tools/kosctl install\n' "$CLONE_DIR"
    printf '\n'
}

main() {
    parse_args "$@"
    log_init

    printf '%sKOS 安装脚本（Debian 13 / Debian-family） v%s%s\n' "$C_BOLD" "$SCRIPT_VERSION" "$C_RESET"
    printf '%s日志：%s%s\n' "$C_DIM" "$LOG_FILE" "$C_RESET"

    # 预检全程只读，也刻意不触发 sudo 授权，方便先看清状况再决定是否动手。
    require_non_root
    preflight
    detect_proxy

    if (( CHECK_ONLY )); then
        step "预检模式"
        if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
            ok "Quickshell 已安装"
        else
            warn "Quickshell 未安装（正式安装阶段会自动处理）"
        fi
        ok "预检通过，未改动系统。去掉 --check 即可正式安装"
        exit 0
    fi

    setup_sudo
    ensure_quickshell

    if (( SKIP_DEPS )); then
        step "依赖"
        info "--no-deps：跳过 apt 依赖安装"
    else
        install_dependencies
    fi

    clone_repo
    build_and_install

    if verify_install; then
        ok "全部校验通过"
    else
        warn "有校验项未通过，请查看上面的告警与日志"
    fi

    if (( DO_START )); then
        step "立即生效（kosctl start）"
        kosctl_run start || warn "kosctl start 未成功；下次登录仍会正常启动"
    fi

    print_summary
}

main "$@"
