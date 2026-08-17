# GitLab 服务端提交校验配套方案

本目录是 `@7dgroup/dsh-skill-7d-git-commit` 插件的**服务端配套交付物**，与客户端 DSH skill 共同构成"客户端预判 + 服务端兜底"的双层提交规范校验。

## 与本插件的关系

| 层级 | 位置 | 作用 |
|------|------|------|
| 客户端预判 | `assets/git-commit/SKILL.md` | 在生成 commit message 前校验并提示修正 |
| 服务端兜底 | `docs/gitlab-integration/pre-receive` | 在 `git push` 到达仓库前校验并告警/拦截 |
| 规范来源 | `assets/git-commit/references/git-commit-message.md` | 客户端与服务端共用同一套规则 |

## 目录结构

```
docs/gitlab-integration/
├── README.md                          # 本文件
├── deployment-guide.md                # 部署 SOP：单仓试点 → 全局推广 → 硬拦截 → 回滚
├── switch-to-reject-checklist.md      # 观察期转硬拦截检查清单
├── commit-rules.conf                  # 校验规则配置
├── pre-receive                        # 服务端 hook 主脚本
├── install-hooks.sh                   # 安装/卸载脚本
└── scripts/
    ├── audit-report.sh                # 观察期日志巡检汇总
    ├── dingtalk-notify.sh             # 钉钉机器人日报推送
    ├── sync-rules.sh                  # 规则配置同步助手
    └── test-hook-locally.sh           # 本地规则自测
```

## 快速开始

1. **确认规则**：编辑 `commit-rules.conf`，与开发团队确认 9 类标签、长度、禁用字符/短语等。
2. **本地自测**：
   ```bash
   cd docs/gitlab-integration/scripts
   bash test-hook-locally.sh -m "【新增】用户模块新增手机号登录接口"
   bash test-hook-locally.sh -m "【新增】配置邮箱 a@b.com"
   ```
3. **复制到 GitLab 服务器**：将整个 `docs/gitlab-integration/` 目录复制到 GitLab 服务器（如 `/data/7dgroup/dsh-skill-7d-git-commit-docs/`）。
4. **部署**：
   ```bash
   sudo bash install-hooks.sh --pilot devops/7dgroup
   # 试点通过后
   sudo bash install-hooks.sh --global
   ```
5. **切换硬拦截**：完成 `switch-to-reject-checklist.md` 后，修改全局 `commit-rules.conf` 的 `MODE="reject"`。

## 运维配套

- 观察期巡检：`scripts/audit-report.sh`
- 钉钉日报：`scripts/dingtalk-notify.sh`
- 规则同步：`scripts/sync-rules.sh`
- 硬拦截切换：`switch-to-reject-checklist.md`

## 注意事项

1. 本目录文件**不进入 DSH 插件运行时包**，仅供团队按需复制到 GitLab 服务器使用。
2. 生产环境的权威 hook 脚本以本仓库 `docs/gitlab-integration/`（7DGroup 项目）为准，部署侧如有调整请同步回本仓库保持对齐。
3. 部署前请根据实际 GitLab 版本、仓库路径、钉钉 Webhook 调整脚本中的常量。
