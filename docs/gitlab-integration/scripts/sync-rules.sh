#!/usr/bin/env bash
# ============================================================================
# sync-rules.sh —— 同步 commit-rules.conf 到 GitLab 服务器 hook 部署位置
# ----------------------------------------------------------------------------
# 用途：当本仓库中的 commit-rules.conf 变更后，将其同步到 GitLab 服务器的单仓试点
#       或全局 hook 目录，无需重新运行完整的 install-hooks.sh。
#
# 用法：
#   sudo bash sync-rules.sh --global --dry-run      # 先查看差异
#   sudo bash sync-rules.sh --global                # 同步到全局
#   sudo bash sync-rules.sh --pilot devops/7dgroup # 同步到单仓
#
# 安全：
#   - 默认备份旧配置（带时间戳 .bak）。
#   - 校验新配置必须包含 MODE=，否则拒绝写入。
#   - 支持 --dry-run 先预览 diff。
# ============================================================================

set -euo pipefail

C_R='\033[31m'; C_G='\033[32m'; C_Y='\033[33m'; C_C='\033[36m'; C_0='\033[0m'
info()  { printf "${C_C}[INFO]${C_0} %s\n"  "$*" >&2; }
ok()    { printf "${C_G}[ OK ]${C_0} %s\n"  "$*" >&2; }
warn()  { printf "${C_Y}[WARN]${C_0} %s\n" "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CONF="${SCRIPT_DIR}/../commit-rules.conf"
GLOBAL_TARGET="/var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf"

DRY_RUN=false
MODE=""
PROJECT=""

usage() {
    cat <<EOF
用法：
  sudo bash $0 --global [--dry-run]
  sudo bash $0 --pilot <项目全路径> [--dry-run]

选项：
  --global        同步到全局：${GLOBAL_TARGET}
  --pilot PROJECT 同步到单仓：<repo>.git/custom_hooks/commit-rules.conf
  --dry-run       仅打印 diff，不写入
  -h, --help      显示本帮助
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --global)  MODE="global"; shift ;;
        --pilot)   MODE="pilot"; PROJECT="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[FAIL] 未知参数：$1" >&2; usage; exit 2 ;;
    esac
done

if [ ! -r "${SOURCE_CONF}" ]; then
    echo "[FAIL] 未找到源 commit-rules.conf：${SOURCE_CONF}" >&2
    exit 1
fi

if [ -z "${MODE}" ]; then
    echo "[FAIL] 必须指定 --global 或 --pilot <项目>" >&2
    usage
    exit 2
fi

[ "$(id -u)" -eq 0 ] || { echo "[FAIL] 请用 sudo 执行" >&2; exit 1; }

if ! grep -qE '^MODE="(warn|reject)"' "${SOURCE_CONF}"; then
    echo "[FAIL] 源配置缺少合法的 MODE= 行，拒绝同步" >&2
    exit 1
fi

if [ "${MODE}" = "global" ]; then
    TARGET="${GLOBAL_TARGET}"
else
    [ -n "${PROJECT}" ] || { echo "[FAIL] --pilot 需要指定项目全路径" >&2; exit 2; }
    rel=$(gitlab-rails runner "p = Project.find_by_full_path('${PROJECT}'); puts p ? p.disk_path : ''" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
    case "${rel}" in
        *.git) ;;
        *) rel="${rel}.git" ;;
    esac
    [ -n "${rel}" ] || { echo "[FAIL] 无法解析项目 ${PROJECT}" >&2; exit 1; }
    TARGET="/data/gitlab-data/git-data/${rel}/custom_hooks/commit-rules.conf"
fi

if [ "${DRY_RUN}" = "true" ]; then
    info "源配置：${SOURCE_CONF}"
    info "目标路径：${TARGET}"
    if [ -r "${TARGET}" ]; then
        info "diff（目标 → 源）："
        diff -u "${TARGET}" "${SOURCE_CONF}" || true
    else
        info "目标不存在，将新增文件"
        head -n 30 "${SOURCE_CONF}"
    fi
    exit 0
fi

install -d -o git -g git -m 0755 "$(dirname "${TARGET}")"

if [ -f "${TARGET}" ]; then
    bak="${TARGET}.$(date +%Y%m%d%H%M%S).bak"
    cp -a "${TARGET}" "${bak}"
    info "已备份旧配置：${bak}"
fi

install -o git -g git -m 0644 "${SOURCE_CONF}" "${TARGET}"
ok "配置已同步到：${TARGET}"

current_mode=$(grep -E '^MODE=' "${TARGET}")
ok "当前模式：${current_mode}"

if [ "${MODE}" = "global" ]; then
    warn "全局配置对所有仓库即时生效。请确认当前 MODE 符合预期。"
else
    info "单仓配置即时生效，下次 push 即使用新规则。"
fi
