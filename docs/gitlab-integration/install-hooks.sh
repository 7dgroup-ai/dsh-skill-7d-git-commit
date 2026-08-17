#!/usr/bin/env bash
# ============================================================================
# install-hooks.sh —— GitLab 服务端提交校验 hook 安装/卸载脚本
# ----------------------------------------------------------------------------
# 适配 GitLab CE 19.2.0（Omnibus 直装），在 GitLab 服务器上以 opsadmin + sudo 执行。
#
# 用法：
#   sudo bash install-hooks.sh --pilot <项目全路径>
#   sudo bash install-hooks.sh --global
#   sudo bash install-hooks.sh --uninstall-pilot <项目全路径>
#   sudo bash install-hooks.sh --uninstall-global
#
# 前置：本目录的 pre-receive 与 commit-rules.conf 必须存在且与本脚本同目录。
# ============================================================================

set -euo pipefail

C_R='\033[31m'; C_G='\033[32m'; C_Y='\033[33m'; C_C='\033[36m'; C_0='\033[0m'
info()  { printf "${C_C}[INFO]${C_0} %s\n"  "$*" >&2; }
ok()    { printf "${C_G}[ OK ]${C_0} %s\n"  "$*" >&2; }
warn()  { printf "${C_Y}[WARN]${C_0} %s\n" "$*" >&2; }
die()   { printf "${C_R}[FAIL]${C_0} %s\n" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="${SCRIPT_DIR}/pre-receive"
RULES_SRC="${SCRIPT_DIR}/commit-rules.conf"

GITALY_CONFIG="/var/opt/gitlab/gitaly/config.toml"
GITLAB_RB="/etc/gitlab/gitlab.rb"
GLOBAL_HOOKS_DIR="/var/opt/gitlab/gitaly/custom_hooks"
LOG_FILE="/var/log/gitlab/commit-check.log"

preflight() {
    [ "$(id -u)" -eq 0 ] || die "请用 sudo 执行本脚本。"
    [ -f "${HOOK_SRC}" ]  || die "未找到 pre-receive：${HOOK_SRC}"
    [ -f "${RULES_SRC}" ] || die "未找到 commit-rules.conf：${RULES_SRC}"
    command -v gitlab-ctl >/dev/null 2>&1 || die "未找到 gitlab-ctl，请在 GitLab 服务器上执行。"
    ok "前置检查通过"
}

ensure_log() {
    install -d -o git -g git -m 0755 "$(dirname "${LOG_FILE}")" 2>/dev/null || true
    touch "${LOG_FILE}" 2>/dev/null || warn "无法创建 ${LOG_FILE}（hook 会静默跳过日志）"
    chown git:git "${LOG_FILE}" 2>/dev/null || true
    chmod 0644 "${LOG_FILE}" 2>/dev/null || true
}

resolve_disk_path() {
    local project="$1"
    [ -n "${project}" ] || die "项目全路径为空"

    info "解析仓库物理路径：${project}"
    local rel
    rel=$(gitlab-rails runner "p = Project.find_by_full_path('${project}'); puts p ? p.disk_path : ''" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
    case "${rel}" in
        *.git) ;;
        *) rel="${rel}.git" ;;
    esac
    [ -n "${rel}" ] || die "无法解析项目 ${project} 的 disk_path。"
    echo "${rel}"
}

do_pilot() {
    local project="${1:-}"
    [ -n "${project}" ] || die "用法：$0 --pilot <项目全路径>"

    info "===== 单仓试点：${project} ====="
    preflight
    ensure_log

    local rel repo_path custom_dir
    rel=$(resolve_disk_path "${project}")
    repo_path="/data/gitlab-data/git-data/${rel}"
    [ -d "${repo_path}" ] || die "仓库目录不存在：${repo_path}"

    custom_dir="${repo_path}/custom_hooks"
    info "部署到：${custom_dir}"

    install -d -o git -g git -m 0755 "${custom_dir}"
    install  -o git -g git -m 0755 "${HOOK_SRC}"  "${custom_dir}/pre-receive"
    install  -o git -g git -m 0644 "${RULES_SRC}" "${custom_dir}/commit-rules.conf"

    ok "单仓试点部署完成"
    echo
    info "验证：在本地 clone 该仓库，分别构造合规/不合规提交 push 测试"
    info "查看审计日志：sudo tail -f ${LOG_FILE}"
    info "切换拦截模式：编辑 ${custom_dir}/commit-rules.conf 的 MODE=reject"
}

do_global() {
    info "===== 全局推广（所有仓库生效）====="
    preflight
    ensure_log

    cp -a "${GITLAB_RB}" "${GITLAB_RB}.$(date +%Y%m%d%H%M%S).pre-hook.bak"
    info "已备份 gitlab.rb"

    if grep -qE "^[[:space:]]*gitaly\['configuration'\]\[:hooks\]\[:custom_hooks_dir\]" "${GITLAB_RB}"; then
        sed -i -E "/^[[:space:]]*gitaly\['configuration'\]\[:hooks\]\[:custom_hooks_dir\]/d" "${GITLAB_RB}"
        warn "检测到已存在配置行，已先移除旧值"
    fi

    cat >> "${GITLAB_RB}" <<'EOF'

# --- 7DGroup 服务端提交校验 hook（全局 custom_hooks_dir）---
gitaly['configuration'][:hooks][:custom_hooks_dir] = '/var/opt/gitlab/gitaly/custom_hooks'
# --- 7DGroup hook end ---
EOF
    ok "已写入 gitlab.rb"

    info "执行 gitlab-ctl reconfigure（约 1-2 分钟）..."
    gitlab-ctl reconfigure
    ok "reconfigure 完成"

    local hook_d="${GLOBAL_HOOKS_DIR}/pre-receive.d"
    install -d -o git -g git -m 0755 "${hook_d}"
    install -o git -g git -m 0755 "${HOOK_SRC}"  "${hook_d}/01-commit-check"
    install -o git -g git -m 0644 "${RULES_SRC}" "${GLOBAL_HOOKS_DIR}/commit-rules.conf"

    ok "全局推广部署完成"
    echo
    warn "全局配置对所有仓库立即生效。上线前请确认 MODE=warn（观察期）。"
    info "当前 MODE：$(grep -E '^MODE=' "${GLOBAL_HOOKS_DIR}/commit-rules.conf")"
    info "查看审计日志：sudo tail -f ${LOG_FILE}"
}

do_uninstall_pilot() {
    local project="${1:-}"
    [ -n "${project}" ] || die "用法：$0 --uninstall-pilot <项目全路径>"
    preflight

    local rel repo_path custom_dir
    rel=$(resolve_disk_path "${project}")
    repo_path="/data/gitlab-data/git-data/${rel}"
    custom_dir="${repo_path}/custom_hooks"

    if [ -d "${custom_dir}" ]; then
        rm -f "${custom_dir}/pre-receive" "${custom_dir}/commit-rules.conf"
        rmdir "${custom_dir}" 2>/dev/null || true
        ok "已移除单仓 hook：${custom_dir}"
    else
        warn "未发现单仓 hook 目录：${custom_dir}"
    fi
}

do_uninstall_global() {
    info "===== 卸载全局 hook ====="
    preflight

    rm -f "${GLOBAL_HOOKS_DIR}/pre-receive.d/01-commit-check" 2>/dev/null && ok "已移除全局 hook 文件"
    rm -f "${GLOBAL_HOOKS_DIR}/commit-rules.conf" 2>/dev/null || true

    if grep -q "7DGroup hook end" "${GITLAB_RB}"; then
        sed -i -E '/7DGroup 服务端提交校验 hook/,/7DGroup hook end/d' "${GITLAB_RB}"
        ok "已从 gitlab.rb 移除配置"
        info "执行 gitlab-ctl reconfigure ..."
        gitlab-ctl reconfigure
        ok "reconfigure 完成"
    else
        warn "gitlab.rb 未发现本脚本写入的配置标记"
    fi
}

usage() {
    cat <<EOF
install-hooks.sh —— GitLab 服务端提交校验 hook 安装/卸载

用法：
  sudo bash $0 --pilot <项目全路径>            # 单仓试点
  sudo bash $0 --global                        # 全局推广
  sudo bash $0 --uninstall-pilot <项目全路径>  # 卸载单仓
  sudo bash $0 --uninstall-global              # 卸载全局

前置：
  - 在 GitLab 服务器上以 opsadmin + sudo 执行
  - pre-receive 与 commit-rules.conf 须与本脚本同目录
EOF
}

case "${1:-}" in
    --pilot)            do_pilot "${2:-}" ;;
    --global)           do_global ;;
    --uninstall-pilot)  do_uninstall_pilot "${2:-}" ;;
    --uninstall-global) do_uninstall_global ;;
    -h|--help|"")       usage ;;
    *)                  die "未知参数：$1（用 --help 查看用法）" ;;
esac
