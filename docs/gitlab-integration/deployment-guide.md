# GitLab 服务端提交校验部署指南

> 本指南是 `@7dgroup/dsh-skill-7d-git-commit` 插件的配套文档，供运维团队将客户端提交规范校验延伸至 GitLab 服务端，形成"客户端预判 + 服务端兜底"的双层校验。
>
> 部署前请先阅读 [`scenarios.md`](./scenarios.md)（应用场景说明），确认本方案适用性与落地节奏（单仓试点 / 全局推广、观察期 / 硬拦截）。
>
> 事实来源：
> - 客户端 skill：`assets/git-commit/SKILL.md`
> - 提交规范：`assets/git-commit/references/git-commit-message.md`
> - 生产环境权威配置：本仓库 `docs/gitlab-integration/`（7DGroup 项目）

## 适用范围

- GitLab CE 19.2.0（Omnibus 直装，Gitaly 存储 `/data/gitlab-data/git-data`）
- 其他 GitLab CE 版本可参考，但需验证 `custom_hooks_dir` 与 `pre-receive.d/` 语法差异

## 目录内容

本目录提供可直接复制到 GitLab 服务器执行的脚本模板：

| 文件 | 用途 |
|------|------|
| `scenarios.md` | 应用场景说明：背景、典型场景、适用边界、踩坑 FAQ |
| `pre-receive` | 服务端 hook 主脚本 |
| `commit-rules.conf` | 校验规则配置 |
| `install-hooks.sh` | 单仓试点 / 全局推广 / 卸载 |
| `scripts/audit-report.sh` | 观察期日志巡检汇总 |
| `scripts/dingtalk-notify.sh` | 钉钉机器人日报推送 |
| `scripts/sync-rules.sh` | 规则配置同步助手 |
| `scripts/test-hook-locally.sh` | 本地规则自测 |
| `switch-to-reject-checklist.md` | 硬拦截切换检查清单 |

## 快速部署

### 1. 开发团队确认规则

编辑 `commit-rules.conf`，重点确认：

```ini
MODE="warn"                 # warn=观察期告警不拦 / reject=硬拦截
COMMIT_REGEX='^【(新增|修复|优化|调整|删除|文档|测试|回滚|合并)】'
TITLE_MAX_LEN=50
REJECT_TRAILING_PUNCT=true
DETAIL_MAX_LEN=70
FORBIDDEN_CHARS='@#$%^&*~'
FORBIDDEN_PHRASES='待优化|后续再改|待修改|以后再说|TODO|FIXME|哈哈哈|666'
SKIP_KEYWORD="[skip-check]"
ALLOW_MERGE=true
```

### 2. 单仓试点（推荐首上线）

```bash
# 在 GitLab 服务器上，以 opsadmin + sudo 执行
sudo bash install-hooks.sh --pilot devops/7dgroup
```

### 3. 全局推广

试点运行 1~2 周无问题后：

```bash
# 若目标仓已部署单仓试点 hook，请先卸载，避免重复执行
sudo bash install-hooks.sh --uninstall-pilot devops/7dgroup
sudo bash install-hooks.sh --global
```

### 4. 切换硬拦截

观察期无高频误报后，修改全局配置文件：

```bash
sudo sed -i 's/^MODE="warn"/MODE="reject"/' /var/opt/gitlab/gitaly/custom_hooks/commit-rules.conf
```

切换前必须完成 [`switch-to-reject-checklist.md`](./switch-to-reject-checklist.md)。

## 验证用例

| # | 场景 | 构造提交 | warn 模式期望 | reject 模式期望 |
|---|------|---------|--------------|----------------|
| 1 | 规范提交 | `【新增】用户模块新增登录接口` | 放行 | 放行 |
| 2 | 缺标签 | `update something` | 放行+告警 | 拒绝 |
| 3 | 标题超长 | `【新增】`+51 字描述 | 放行+告警 | 拒绝 |
| 4 | 末尾句号 | `【新增】新增接口。` | 放行+告警 | 拒绝 |
| 5 | `[skip-check]` 绕过 | `hotfix xxx [skip-check]` | 放行，记 BYPASS | 放行，记 BYPASS |
| 6 | Merge 豁免 | `Merge branch 'feat'` | 放行，记 BYPASS | 放行，记 BYPASS |
| 7 | 多提交含前序违规 | 提交1合规+提交2违规+提交3合规 | 放行+告警 | 拒绝 |
| 8 | 禁用字符 `@` | `【新增】配置邮箱 a@b.com` | 放行+告警 | 拒绝 |
| 9 | 禁用短语 TODO | `【修复】修复登录 TODO 后续处理` | 放行+告警 | 拒绝 |
| 10 | 正文超 70 字符 | 标题合规+正文单行>70 字 | 放行+告警 | 拒绝 |
| 11 | 英文专有名词 | `【新增】接入 Docker 与 MySQL` | 放行 | 放行 |

## 回滚

```bash
# 单仓回滚
sudo bash install-hooks.sh --uninstall-pilot devops/7dgroup

# 全局回滚
sudo bash install-hooks.sh --uninstall-global
```

## 运维配套

- 观察期巡检：`scripts/audit-report.sh`
- 钉钉日报：`scripts/dingtalk-notify.sh`
- 规则同步：`scripts/sync-rules.sh`
- 本地自测：`scripts/test-hook-locally.sh`

## 注意事项

1. `pre-receive` 以 `git` 用户身份执行，部署后必须 `chown git:git` + `chmod +x`。
2. 全局 hook 必须使用 `pre-receive.d/` 目录，单仓试点使用 `custom_hooks/pre-receive` 文件。
3. 修改 `commit-rules.conf` 后即时生效，无需重启 Gitaly 或 `gitlab-ctl reconfigure`。
4. 本指南中的脚本为模板，复制到生产环境前请根据实际路径和钉钉 Webhook 调整。
