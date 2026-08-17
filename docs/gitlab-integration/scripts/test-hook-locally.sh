#!/usr/bin/env bash
# ============================================================================
# test-hook-locally.sh —— 本地模拟 GitLab pre-receive 提交校验
# ----------------------------------------------------------------------------
# 用途：不依赖 GitLab/Gitaly，用纯 shell 模拟服务端 hook 的核心校验逻辑，
#       用于规则变更前在本地快速自测。
#
# 输入：
#   - 默认读取当前目录或 ../ 下的 commit-rules.conf 作为规则源。
#   - 通过 stdin 或文件传入 commit message（标题 + 正文）。
#
# 输出：CHECK / WARN / REJECT / BYPASS 结论与原因。
#
# 示例：
#   bash test-hook-locally.sh -m "【新增】用户模块新增手机号登录接口"
#   echo -e "【新增】新增接口。\n\n1. 补充登录接口\n2. 调整参数" | bash test-hook-locally.sh
# ============================================================================

set -u

# ----------------------------------------------------------------------------
# 0. 定位规则配置文件
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RULES_CANDIDATES=(
    "${SCRIPT_DIR}/../commit-rules.conf"
    "${SCRIPT_DIR}/commit-rules.conf"
)

RULES_FILE=""
for cand in "${REPO_RULES_CANDIDATES[@]}"; do
    if [ -r "${cand}" ]; then
        RULES_FILE="${cand}"
        break
    fi
done

# 配置项默认值
MODE="warn"
COMMIT_REGEX='^【(新增|修复|优化|调整|删除|文档|测试|回滚|合并)】'
TITLE_MAX_LEN=50
REJECT_TRAILING_PUNCT=true
DETAIL_MAX_LEN=70
FORBIDDEN_CHARS='@#$%^&*~'
FORBIDDEN_PHRASES='待优化|后续再改|待修改|以后再说|TODO|FIXME|哈哈哈|666'
SKIP_KEYWORD="[skip-check]"
ALLOW_MERGE=true

if [ -n "${RULES_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${RULES_FILE}"
else
    echo "[WARN] 未找到 commit-rules.conf，使用内置默认规则。" >&2
fi

# ----------------------------------------------------------------------------
# 1. 读取待测 message
# ----------------------------------------------------------------------------
usage() {
    cat <<EOF
用法：
  bash $0 -m "commit message 字符串"
  bash $0 -f message.txt
  echo "commit message" | bash $0

选项：
  -m, --message   直接指定 commit message
  -f, --file      从文件读取 commit message
  -h, --help      显示本帮助
EOF
}

MESSAGE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -m|--message)
            MESSAGE="${2:-}"
            shift 2
            ;;
        -f|--file)
            [ -r "${2:-}" ] || { echo "[FAIL] 无法读取文件：${2:-}" >&2; exit 2; }
            MESSAGE="$(cat "${2:-}")"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[FAIL] 未知参数：$1" >&2
            usage
            exit 2
            ;;
    esac
done

if [ -z "${MESSAGE}" ]; then
    if [ -t 0 ]; then
        echo "[FAIL] 未提供 commit message，且 stdin 非管道。请用 -m/-f 或管道输入。" >&2
        usage
        exit 2
    else
        MESSAGE="$(cat)"
    fi
fi

[ -z "${MESSAGE}" ] && { echo "[FAIL] commit message 为空" >&2; exit 2; }

# ----------------------------------------------------------------------------
# 2. 工具函数
# ----------------------------------------------------------------------------
char_len() {
    local s="$1" n lc
    for lc in "C.UTF-8" "en_US.UTF-8" "zh_CN.UTF-8"; do
        if [ "$(printf '中' | LC_ALL="${lc}" wc -m 2>/dev/null | awk '{print $1}')" = "1" ]; then
            n=$(printf '%s' "${s}" | LC_ALL="${lc}" wc -m 2>/dev/null | awk '{print $1}')
            printf '%s' "${n}"
            return
        fi
    done
    n=$(printf '%s' "${s}" | perl -CS -e 'print length(<STDIN>)' 2>/dev/null | awk '{print $1}')
    if [ -n "${n}" ] && [ "${n}" != "0" ]; then
        printf '%s' "${n}"
        return
    fi
    printf '%s' "$(printf '%s' "${s}" | wc -c | awk '{print $1}')"
}

subject="$(printf '%s' "${MESSAGE}" | head -1)"

# ----------------------------------------------------------------------------
# 3. 规则判定
# ----------------------------------------------------------------------------
reason=""

# 规则 A：关键词绕过
if printf '%s' "${subject}" | grep -qF "${SKIP_KEYWORD}"; then
    echo "BYPASS | 命中 ${SKIP_KEYWORD}，跳过校验"
    exit 0
fi

# 规则 B：Merge commit 豁免
if [ "${ALLOW_MERGE}" = "true" ] && printf '%s' "${subject}" | grep -qE '^Merge '; then
    echo "BYPASS | Merge commit 豁免"
    exit 0
fi

# 规则 C：标签正则
if ! printf '%s' "${subject}" | grep -qE "${COMMIT_REGEX}"; then
    reason="标签不匹配规范"
fi

# 规则 D：标题长度
if [ -z "${reason}" ]; then
    title_desc="${subject#*】}"
    tlen=$(char_len "${title_desc}")
    if [ -z "${title_desc}" ]; then
        reason="标题缺少描述文字"
    elif [ "${tlen}" -gt "${TITLE_MAX_LEN}" ]; then
        reason="标题长度 ${tlen} 超过 ${TITLE_MAX_LEN} 字符"
    fi
fi

# 规则 E：末尾标点
if [ -z "${reason}" ] && [ "${REJECT_TRAILING_PUNCT}" = "true" ]; then
    last_char=$(printf '%s' "${subject}" | perl -CS -e 'use utf8; my $s = <STDIN>; $s =~ s/\n$//; print substr($s, -1)' 2>/dev/null)
    case "${last_char}" in
        '.'|','|'。'|'，')
            reason="标题以标点（${last_char}）结尾，规范禁止"
            ;;
    esac
fi

# 规则 F：禁用字符
if [ -z "${reason}" ] && [ -n "${FORBIDDEN_CHARS}" ]; then
    bad_char=""
    i=0
    chars_len=${#FORBIDDEN_CHARS}
    while [ "${i}" -lt "${chars_len}" ]; do
        ch="${FORBIDDEN_CHARS:${i}:1}"
        if [ -n "${ch}" ] && printf '%s' "${MESSAGE}" | grep -qF "${ch}"; then
            bad_char="${ch}"
            break
        fi
        i=$((i + 1))
    done
    [ -n "${bad_char}" ] && reason="含禁止的特殊符号「${bad_char}」（规范禁止 @ # $ % ^ & * ~ 等）"
fi

# 规则 G：禁用短语
if [ -z "${reason}" ] && [ -n "${FORBIDDEN_PHRASES}" ]; then
    hit_phrase=$(printf '%s' "${MESSAGE}" | grep -oE "${FORBIDDEN_PHRASES}" | head -1)
    [ -n "${hit_phrase}" ] && reason="含禁止的短语「${hit_phrase}」（规范禁止临时标记/情绪化内容）"
fi

# 规则 H：正文行宽
if [ -z "${reason}" ] && [ "${DETAIL_MAX_LEN:-0}" -gt 0 ] 2>/dev/null; then
    long_line=""
    while IFS= read -r line; do
        [ -z "${line}" ] && continue
        content_line="${line#"${line%%[!0-9]*}"}"
        case "${content_line}" in
            .*|、*) content_line="${content_line#?}" ;;
        esac
        content_line="${content_line#"${content_line%%[![:space:]]*}"}"
        [ -z "${content_line}" ] && continue
        clen=$(char_len "${content_line}")
        if [ "${clen}" -gt "${DETAIL_MAX_LEN}" ]; then
            long_line="${clen}"
            break
        fi
    done < <(printf '%s\n' "${MESSAGE}" | tail -n +2)
    [ -n "${long_line}" ] && reason="正文存在单行 ${long_line} 字符超过 ${DETAIL_MAX_LEN}（规范 detail≤70）"
fi

# ----------------------------------------------------------------------------
# 4. 输出结论
# ----------------------------------------------------------------------------
if [ -n "${reason}" ]; then
    if [ "${MODE}" = "reject" ]; then
        echo "REJECT | ${reason}"
        echo "       | 规范格式：【类型】简短描述，类型须为 新增/修复/优化/调整/删除/文档/测试/回滚/合并 之一"
        exit 1
    else
        echo "WARN   | ${reason}"
        exit 0
    fi
else
    echo "CHECK  | 通过"
    exit 0
fi
