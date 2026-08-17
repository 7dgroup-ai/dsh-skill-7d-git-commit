#!/usr/bin/env bash
# ============================================================================
# dingtalk-notify.sh —— 钉钉机器人推送提交校验违规日报
# ----------------------------------------------------------------------------
# 用途：调用 audit-report.sh 生成 Markdown 汇总，并通过钉钉机器人 Webhook 发送。
#
# 安全：
#   - Webhook URL 禁止硬编码，优先从环境变量 DINGTALK_WEBHOOK 读取，其次 --webhook。
#   - 仅发送统计信息，不发送完整 commit subject。
#   - 失败返回非零退出码。
#
# 用法：
#   export DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxxx"
#   sudo -E bash dingtalk-notify.sh
#   sudo -E bash dingtalk-notify.sh --since 2026-08-01 --until 2026-08-07 --title "提交规范周报"
#
# 依赖：curl、audit-report.sh（与本脚本同目录）
# ============================================================================

set -u

WEBHOOK="${DINGTALK_WEBHOOK:-}"
TITLE="AegisPipe 提交规范违规日报"
SINCE=""
UNTIL=""
DRY_RUN=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_SCRIPT="${SCRIPT_DIR}/audit-report.sh"

usage() {
    cat <<EOF
用法：
  export DINGTALK_WEBHOOK="..."
  sudo -E bash $0 [选项]

选项：
  --webhook URL     钉钉机器人 Webhook（也可设环境变量 DINGTALK_WEBHOOK）
  --title TITLE     消息标题
  --since DATE      起始日期 YYYY-MM-DD，默认昨天
  --until DATE      结束日期 YYYY-MM-DD，默认昨天
  --dry-run         仅打印要发送的 Markdown，不实际调用钉钉
  -h, --help        显示本帮助
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --webhook)  WEBHOOK="${2:-}"; shift 2 ;;
        --title)    TITLE="${2:-}"; shift 2 ;;
        --since)    SINCE="${2:-}"; shift 2 ;;
        --until)    UNTIL="${2:-}"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "[FAIL] 未知参数：$1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "${WEBHOOK}" ]; then
    echo "[FAIL] 未提供钉钉 Webhook。请设置环境变量 DINGTALK_WEBHOOK 或使用 --webhook。" >&2
    exit 1
fi

if [ ! -x "${AUDIT_SCRIPT}" ]; then
    echo "[FAIL] 未找到 audit-report.sh：${AUDIT_SCRIPT}" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[FAIL] 未找到 curl，请先安装。" >&2
    exit 1
fi

REPORT=$(bash "${AUDIT_SCRIPT}" --since "${SINCE:-}" --until "${UNTIL:-}" --markdown 2>&1)
if [ $? -ne 0 ] || [ -z "${REPORT}" ]; then
    echo "[FAIL] 生成审计报告失败" >&2
    exit 1
fi

MESSAGE=$(cat <<EOF
{
  "msgtype": "markdown",
  "markdown": {
    "title": "${TITLE}",
    "text": "### ${TITLE}\n${REPORT}"
  }
}
EOF
)

if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY-RUN] 将要发送的消息体："
    echo "${MESSAGE}"
    exit 0
fi

RESPONSE=$(curl -s -S -X POST \
    -H "Content-Type: application/json" \
    -d "${MESSAGE}" \
    "${WEBHOOK}" 2>&1)

CURL_EXIT=$?
if [ ${CURL_EXIT} -ne 0 ]; then
    echo "[FAIL] 调用钉钉 Webhook 失败（curl exit=${CURL_EXIT}）：${RESPONSE}" >&2
    exit 1
fi

ERRCODE=$(printf '%s' "${RESPONSE}" | grep -oP '"errcode":\s*\K[0-9]+' || echo "")
if [ "${ERRCODE}" != "0" ]; then
    echo "[FAIL] 钉钉返回错误：${RESPONSE}" >&2
    exit 1
fi

echo "[OK] 钉钉消息已发送：${RESPONSE}"
