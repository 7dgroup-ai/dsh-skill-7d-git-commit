#!/usr/bin/env bash
# ============================================================================
# audit-report.sh —— GitLab 提交校验审计日志汇总报告
# ----------------------------------------------------------------------------
# 用途：读取 /var/log/gitlab/commit-check.log，按仓库/用户/规则维度汇总
#       WARN / REJECT / BYPASS / CHECK 记录，用于观察期评审与日报。
#
# 运行位置：gitlab-01 上，opsadmin + sudo（日志属主 git，普通用户可能不可读）
#
# 用法：
#   sudo bash audit-report.sh
#   sudo bash audit-report.sh --since 2026-08-01 --until 2026-08-07
#   sudo bash audit-report.sh --markdown > report.md
#
# 日志格式（由 pre-receive 写入）：
#   2026-07-30 14:03:21+0800 | REJECT | user=zhangsan | repo=devops/aegispipe | sha=9fe42b4 | reason=标签不匹配规范 | subject=bad commit no tag
# ============================================================================

set -u

LOG_FILE="${LOG_FILE:-/var/log/gitlab/commit-check.log}"
SINCE=""
UNTIL=""
MARKDOWN=false
TOP_N=10
TAIL_N=20

DEFAULT_SINCE=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d')
DEFAULT_UNTIL=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d')
SINCE="${DEFAULT_SINCE}"
UNTIL="${DEFAULT_UNTIL}"

usage() {
    cat <<EOF
用法：sudo bash $0 [选项]

选项：
  --since YYYY-MM-DD    起始日期（含），默认昨天
  --until YYYY-MM-DD    结束日期（含），默认昨天
  --top N               TOP 原因数量，默认 10
  --tail N              显示最新原始记录数，默认 20
  --markdown            输出 Markdown 格式（适合钉钉/邮件）
  --log FILE            指定日志文件路径
  -h, --help            显示本帮助
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --since)    SINCE="${2:-}"; shift 2 ;;
        --until)    UNTIL="${2:-}"; shift 2 ;;
        --top)      TOP_N="${2:-10}"; shift 2 ;;
        --tail)     TAIL_N="${2:-20}"; shift 2 ;;
        --markdown) MARKDOWN=true; shift ;;
        --log)      LOG_FILE="${2:-}"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "[FAIL] 未知参数：$1" >&2; usage; exit 2 ;;
    esac
done

if ! [[ "${SINCE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! [[ "${UNTIL}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "[FAIL] --since/--until 必须是 YYYY-MM-DD 格式" >&2
    exit 2
fi

if [ ! -r "${LOG_FILE}" ]; then
    echo "[FAIL] 无法读取日志文件：${LOG_FILE}（请以 sudo 执行或检查路径）" >&2
    exit 1
fi

# ----------------------------------------------------------------------------
# 1. 按日期范围过滤日志
# ----------------------------------------------------------------------------
FILTERED=$(awk -v s="${SINCE}" -v u="${UNTIL}" 'BEGIN {FS="[ |]"} $1 >= s && $1 <= u {print}' "${LOG_FILE}")
TOTAL=$(printf '%s\n' "${FILTERED}" | grep -c '^[0-9]' 2>/dev/null || echo 0)

# ----------------------------------------------------------------------------
# 2. 汇总函数
# ----------------------------------------------------------------------------
summary_by_field() {
    local field="$1" tag_filter="${2:-}"
    local prefix
    case "${field}" in
        user)   prefix="user=" ;;
        repo)   prefix="repo=" ;;
        reason) prefix="reason=" ;;
        *)      echo "[ERROR] 未知字段：${field}" >&2; return 1 ;;
    esac

    printf '%s\n' "${FILTERED}" | awk -F'|' -v tag="${tag_filter}" -v key="${prefix}" '
    {
        gsub(/^[ \t]+|[ \t]+$/, "", $2)
        if (tag != "" && $2 !~ tag) next
        for (i = 1; i <= NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
            if ($i ~ "^" key) {
                val = $i
                sub("^" key, "", val)
                gsub(/^[ \t]+|[ \t]+$/, "", val)
                if (val != "") count[val]++
            }
        }
    }
    END {
        for (k in count) print count[k], k
    }' | sort -rn | head -n "${TOP_N}"
}

count_tag() {
    local tag="$1"
    printf '%s\n' "${FILTERED}" | awk -F'|' -v t="${tag}" '
    {
        gsub(/^[ \t]+|[ \t]+$/, "", $2)
        if ($2 == t) count++
    }
    END { print count + 0 }'
}

WARN_COUNT=$(count_tag WARN)
REJECT_COUNT=$(count_tag REJECT)
BYPASS_COUNT=$(count_tag BYPASS)
CHECK_COUNT=$(count_tag CHECK)

print_markdown_table() {
    local title="$1" field="$2"
    echo ""
    echo "### ${title} TOP ${TOP_N}"
    echo ""
    echo "| ${title} | 次数 |"
    echo "|----------|------|"
    summary_by_field "${field}" "WARN|REJECT" | while read -r count name; do
        echo "| ${name} | ${count} |"
    done
}

print_terminal_section() {
    local title="$1" field="$2"
    echo ""
    echo "【${title} TOP ${TOP_N}】"
    summary_by_field "${field}" "WARN|REJECT" | awk '{
        count = $1
        $1 = ""
        sub(/^ /, "", $0)
        printf "  %-6s %s\n", count, $0
    }'
}

# ----------------------------------------------------------------------------
# 3. 输出报告
# ----------------------------------------------------------------------------
if [ "${MARKDOWN}" = "true" ]; then
    cat <<EOF
## AegisPipe 提交规范审计日报（${SINCE} ~ ${UNTIL}）

| 指标 | 数量 |
|------|------|
| 总记录 | ${TOTAL} |
| 观察期告警（WARN） | ${WARN_COUNT} |
| 硬拦截（REJECT） | ${REJECT_COUNT} |
| 绕过/豁免（BYPASS） | ${BYPASS_COUNT} |
| 合规放行（CHECK） | ${CHECK_COUNT} |
EOF
    print_markdown_table "仓库" repo
    print_markdown_table "用户" user
    print_markdown_table "规则原因" reason

    echo ""
    echo "### 最新 ${TAIL_N} 条记录"
    echo ""
    printf '%s\n' "${FILTERED}" | tail -n "${TAIL_N}" | sed 's/^/    /'
else
    cat <<EOF
================================================================================
AegisPipe 提交规范审计报告（${SINCE} ~ ${UNTIL}）
日志来源：${LOG_FILE}
================================================================================
总记录：${TOTAL}    WARN：${WARN_COUNT}    REJECT：${REJECT_COUNT}    BYPASS：${BYPASS_COUNT}    CHECK：${CHECK_COUNT}
EOF
    print_terminal_section "仓库违规" repo
    print_terminal_section "用户违规" user
    print_terminal_section "规则原因" reason

    echo ""
    echo "【最新 ${TAIL_N} 条记录】"
    printf '%s\n' "${FILTERED}" | tail -n "${TAIL_N}"
fi
