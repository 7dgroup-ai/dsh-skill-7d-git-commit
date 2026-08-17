<p align="center">
  <strong style="font-size: 1.5rem;">@7dgroup/dsh-skill-7d-git-commit</strong>
</p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-263146?style=flat-square">
  <img alt="node" src="https://img.shields.io/badge/node-%5E22.19%20%7C%7C%20%3E%3D24-339933?style=flat-square">
  <img alt="by 7DGroup" src="https://img.shields.io/badge/by-7DGroup-7da1de?style=flat-square">
</p>

<p align="center">
  <a href="README.md">English</a> | <strong>中文</strong>
</p>

# @7dgroup/dsh-skill-7d-git-commit

**作者：7DGroup**

一个 DSH（DeepSeek Harness）组合层插件包，通过 `ctx.skills` 注册 `7d-git-commit` 技能。在生成任何 `git commit` 提交信息前，自动按**7DGroup 项目提交规范**进行校验，规避 gitlab 服务端 `pre-receive` hook 拦截。零核心改动——安装即启用，移除 bundle 行即卸载。

---

## 项目信息

| 项目 | 值 |
|---|---|
| 作者 | 7DGroup |
| 版本 | 0.1.0-rc.3 |
| 运行环境 | Node `^22.19.0 || >=24.0.0` · pnpm 10+ · dsh CLI |
| Peer 依赖 | `@deepseek-ai/cordis` · `@deepseek-ai/dsh-skill` · `@deepseek-ai/dsh-invariants` |
| 技能名称 | `7d-git-commit` |
| 仓库地址 | [github.com/7dgroup-ai/dsh-skill-7d-git-commit](https://github.com/7dgroup-ai/dsh-skill-7d-git-commit) |
| 许可证 | MIT |

## 功能特性

- 在 `git commit` 执行前进行**客户端提交规范预判**。
- 支持 9 个固定中文类型标签：`【新增】`、`【修复】`、`【优化】`、`【调整】`、`【删除】`、`【文档】`、`【测试】`、`【回滚】`、`【合并】`。
- 校验标题长度、末尾标点、禁用字符/短语、动宾句式等规则。
- 正文格式校验：数字序号逐条罗列、每行 ≤70 字符。
- 支持 Merge commit 与紧急发版 `[skip-check]` 豁免。
- 内置事实来源 `references/git-commit-message.md`，按需加载不撑大提示词。
- 纯组合包挂载，不打 DSH 核心补丁。

## 项目结构

```
dsh-skill-7d-git-commit/
├── src/
│   ├── index.ts              # Cordis 插件：注册技能提供者
│   └── invariant.ts          # 包所有权不变量伴生插件
├── assets/7d-git-commit/
│   ├── SKILL.md              # 技能体：校验逻辑
│   └── references/
│       └── git-commit-message.md   # 7DGroup 提交规范事实来源
├── tests/
│   └── skill-7d-git-commit.spec.ts
├── cordis.patch.yml          # 组合层补丁
├── tsdown.config.ts          # 自包含转译配置
├── package.json
└── README.md / README.zh.md
```

## 快速开始

前置条件：`dsh` CLI、Node `^22.19.0 || >=24.0.0`、pnpm 10+。

### 通过 dsh CLI 安装

```sh
dsh plugin --profile web add github:7dgroup-ai/dsh-skill-7d-git-commit
```

首次 git 安装时，pnpm 会拒绝运行构建脚本，需要把 pnpm 打印的确切包键写入该 profile 的 `pnpm-workspace.yaml` → `allowBuilds`，然后重新执行命令。

如需跳过构建授权，可使用预构建 tarball 或发布后的 npm 包：

```sh
dsh plugin --profile web add @7dgroup/dsh-skill-7d-git-commit
```

### 构建与测试

```sh
pnpm install
pnpm build   # tsdown；git 安装时也会以 prepare 钩子运行
pnpm test    # vitest
```

## 使用方式

安装后，在 dsh 会话中提到任意与提交相关的需求即可触发：

> 为当前改动生成一条 commit message。

技能会执行：

1. 分析改动内容。
2. 从 9 类标签中选择最匹配的类型。
3. 撰写标题：`【类型】` + 动宾短语（≤50 字符，无末尾标点）。
4. 复杂改动补充数字序号详情（每行 ≤70 字符）。
5. 按校验清单逐项检查，不合规则提示修正。

## 提交规范

完整规则见 `assets/7d-git-commit/references/git-commit-message.md`。

核心要求：

- 标题格式：`【类型】简短描述`
- 标题长度：去标签后 ≤50 字符
- 末尾禁止：`。` `，` `.` `,`
- 标题/正文禁用字符：`@ # $ % ^ & * ~`
- 禁用短语：待优化、TODO、FIXME、个人情绪等临时备注
- 正文每行 ≤70 字符，使用数字序号逐条罗列

## 与 GitLab 集成使用

本插件同时提供客户端 DSH skill 与服务端 GitLab hook，建议组合使用形成"客户端预判 + 服务端兜底"的双层校验。

- 客户端：`assets/7d-git-commit/SKILL.md` 在 `git commit` 前校验提交信息。
- 服务端：`docs/gitlab-integration/pre-receive` 在 `git push` 到达仓库前校验并告警/拦截。
- 规范来源：`assets/7d-git-commit/references/git-commit-message.md`，客户端与服务端共用同一套规则。

### 部署服务端 hook

将 `docs/gitlab-integration/` 目录复制到 GitLab 服务器，然后执行：

```sh
# 单仓试点
sudo bash install-hooks.sh --pilot devops/7dgroup

# 试点验证通过后推广全局
sudo bash install-hooks.sh --global
```

### 规则同步

当本仓库中 `docs/gitlab-integration/commit-rules.conf` 变更后：

```sh
sudo bash scripts/sync-rules.sh --global --dry-run
sudo bash scripts/sync-rules.sh --global
```

### 观察期巡检与钉钉日报

```sh
# 生成 Markdown 日报
sudo bash scripts/audit-report.sh --markdown

# 推送钉钉机器人
export DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
sudo -E bash scripts/dingtalk-notify.sh
```

### 切换硬拦截

1. 完成 `docs/gitlab-integration/switch-to-reject-checklist.md`。
2. 将部署后的 `commit-rules.conf` 中 `MODE` 改为 `"reject"`。
3. 下次 push 立即生效。

完整部署 SOP 见 [`docs/gitlab-integration/deployment-guide.md`](./docs/gitlab-integration/deployment-guide.md)。

## 注意事项

1. 该提供方只贡献一个固定 skill，不提供运行时自定义。
2. `prepare` 构建不附带类型声明；dsh Loader 只加载运行时入口。
3. 构建只做转译（`dts: false`），没有 lint 或类型检查脚本——类型错误只能在编辑器/IDE 中暴露。
4. `docs/gitlab-integration/` 目录文件不进入 DSH 运行时包，请按需复制到 GitLab 服务器使用。

## 许可证

[MIT](LICENSE) · Copyright (c) 2026 7DGroup
