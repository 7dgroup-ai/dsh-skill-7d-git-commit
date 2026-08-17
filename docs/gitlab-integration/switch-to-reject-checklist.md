# 服务端提交校验：观察期转硬拦截切换检查清单

> 适用对象：GitLab 全局 `pre-receive` hook，当前 `MODE="warn"` 观察期。
> 目标：在切换为 `MODE="reject"` 硬拦截前，逐项确认环境、规则、人员、回滚准备就绪。

---

## 一、数据指标检查

### 1.1 最近 7 天/14 天违规趋势是否下降并低于阈值

**检查标准**：连续 7 天 WARN 总数 ≤ 5 条/天，且无明显反弹。

**命令**：

```bash
# 最近 7 天每日 WARN 数量
for d in $(seq -6 0 | xargs -I{} date -d "{} days" +%Y-%m-%d); do
  count=$(sudo awk -F'|' -v d="$d" '$1 ~ d && $3 ~ /WARN/ {count++} END {print count+0}' /var/log/gitlab/commit-check.log)
  echo "$d: $count"
done
```

**结论**：□ 通过  □ 未通过（说明：__________）

### 1.2 高频违规仓库是否已通知并整改

**检查命令**：

```bash
sudo bash scripts/audit-report.sh --since $(date -d '7 days ago' +%Y-%m-%d) --until $(date +%Y-%m-%d)
```

关注"仓库违规 TOP"列表，确认 TOP3 仓库负责人已收到通知并制定整改计划。

**结论**：□ 通过  □ 未通过

### 1.3 高频违规用户是否已通知并整改

关注"用户违规 TOP"列表，确认 TOP3 用户已了解规则并修正提交习惯。

**结论**：□ 通过  □ 未通过

---

## 二、关键仓库验证

### 2.1 已确认的关键仓库清单

以下仓库应在观察期内单独验证通过（至少构造 1 次合规 push、1 次违规 push）：

| 仓库全路径 | 验证人 | 验证日期 | 结果 |
|-----------|--------|---------|------|
| devops/aegispipe | | | □ 通过 □ 未验证 |
| （其他核心业务仓） | | | □ 通过 □ 未验证 |

### 2.2 验证命令模板

```bash
GITLAB_HOST=10.94.7.1
REPO=devops/aegispipe
git clone ssh://git@${GITLAB_HOST}:2222/${REPO}.git && cd $(basename "$REPO")
git checkout -b test/hook-verify

echo ok > ok.txt; git add ok.txt; git commit -m "【测试】验证提交规范合规提交"
echo bad > bad.txt; git add bad.txt; git commit -m "bad commit no tag"

git push origin test/hook-verify
```

---

## 三、规则配置确认

- [ ] `COMMIT_REGEX` 已覆盖全部 9 类标签
- [ ] `TITLE_MAX_LEN=50` 符合规范
- [ ] `DETAIL_MAX_LEN=70` 符合规范
- [ ] `FORBIDDEN_CHARS` 与 `FORBIDDEN_PHRASES` 经开发团队确认
- [ ] `SKIP_KEYWORD="[skip-check]"` 仅用于紧急发版，并已告知研发团队
- [ ] 开发团队已在 `commit-rules.conf` 最新版本上确认

**查看当前全局规则**：

```bash
grep -E '^(MODE|COMMIT_REGEX|TITLE_MAX_LEN|DETAIL_MAX_LEN|FORBIDDEN_CHARS|FORBIDDEN_PHRASES|SKIP_KEYWORD|ALLOW_MERGE)=' \
  /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf
```

---

## 四、告警与值守准备

### 4.1 钉钉告警通道已配置

- [ ] 已创建/确认钉钉机器人 Webhook
- [ ] 已测试 `scripts/dingtalk-notify.sh` 能正常发送日报
- [ ] 告警接收群包含运维值班人员与研发负责人

**测试命令**：

```bash
export DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxxx"
sudo -E bash scripts/dingtalk-notify.sh --since $(date -d '1 days ago' +%Y-%m-%d)
```

### 4.2 切换窗口与值守人员

- [ ] 切换时间：建议工作日 10:00 前（低峰期）
- [ ] 值守人员：__________
- [ ] 切换后 30 分钟内至少验证 1 次合规 push 与 1 次违规 push

---

## 五、回滚方案准备

### 5.1 软回滚（最快，推荐首选）

```bash
sudo sed -i 's/^MODE="reject"/MODE="warn"/' /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf
sudo grep '^MODE=' /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf
```

### 5.2 硬回滚（完全卸载 hook）

```bash
sudo bash install-hooks.sh --uninstall-global
```

- [ ] 回滚命令已记录到值班手册/备忘录
- [ ] 回滚责任人：__________

---

## 六、切换执行步骤（确认清单通过后再执行）

```bash
# 1. 备份当前配置
sudo cp /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf \
        /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf.$(date +%Y%m%d%H%M%S).bak

# 2. 切换为硬拦截模式
sudo sed -i 's/^MODE="warn"/MODE="reject"/' /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf
sudo grep '^MODE=' /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf

# 3. 切换后立即验证合规/违规 push
# 4. 观察 30 分钟日志
sudo tail -f /var/log/gitlab/commit-check.log
```

---

## 七、切换后检查

- [ ] 合规 push 正常放行
- [ ] 违规 push 被拒绝，终端与 GitLab Web UI 可见 `GL-HOOK-ERR:` 错误信息
- [ ] `[skip-check]` 绕过仍记录 `BYPASS` 审计日志
- [ ] Merge commit 正常豁免
- [ ] 钉钉日报正常发送
- [ ] 无大规模研发群反馈误报/阻断

---

## 审批签字

| 角色 | 签字 | 日期 |
|------|------|------|
| 运维负责人 | | |
| 研发负责人 | | |
| 项目经理 | | |

> 备注：本清单应作为切换硬拦截的工单附件存档。
