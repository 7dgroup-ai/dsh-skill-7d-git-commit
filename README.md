<p align="center">
  <strong style="font-size: 1.5rem;">@7dgroup/dsh-skill-7d-git-commit</strong>
</p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-263146?style=flat-square">
  <img alt="node" src="https://img.shields.io/badge/node-%5E22.19%20%7C%7C%20%3E%3D24-339933?style=flat-square">
  <img alt="by 7DGroup" src="https://img.shields.io/badge/by-7DGroup-7da1de?style=flat-square">
</p>

<p align="center">
  <strong>English</strong> | <a href="README.zh.md">中文</a>
</p>

# @7dgroup/dsh-skill-7d-git-commit

**Author: 7DGroup**

A DSH (DeepSeek Harness) bundle plugin that registers the `git-commit` skill on `ctx.skills`. Before generating any `git commit` message, the skill validates it against the **7DGroup commit convention** and warns or guides the user to fix violations — a client-side guard that complements the server-side `pre-receive` hook on gitlab.

The bundled skill is a drop-in composition layer: install the bundle into a DSH profile and the skill becomes available in every session using that profile; remove the bundle to uninstall it cleanly.

---

## Project Info

| Field | Value |
|---|---|
| Author | 7DGroup |
| Version | 0.1.0-rc.1 |
| Runtime | Node `^22.19.0 || >=24.0.0` · pnpm 10+ · dsh CLI |
| Peer dependencies | `@deepseek-ai/cordis` · `@deepseek-ai/dsh-skill` · `@deepseek-ai/dsh-invariants` |
| Skill name | `git-commit` |
| Repository | [github.com/7dgroup-ai/dsh-skill-7d-git-commit](https://github.com/7dgroup-ai/dsh-skill-7d-git-commit) |
| License | MIT |

## Features

- **Client-side commit validation** before `git commit` is executed.
- **9 fixed Chinese type tags** such as `【新增】`, `【修复】`, `【优化】`, `【文档】`, etc.
- **Title length, punctuation, forbidden characters/phrases, and wording rules** from the AegisPipe convention.
- **Body formatting rules**: numbered lists, max 70 chars per line.
- **Exemptions** for merge commits and emergency `[skip-check]` deployments.
- **Bundled reference** `references/git-commit-message.md` acts as the source of truth and is loaded on demand.
- **Zero core changes** — pure composition bundle.

## Project Structure

```
dsh-skill-7d-git-commit/
├── src/
│   ├── index.ts              # Cordis plugin: registers the skill provider
│   └── invariant.ts          # Package-owned invariant companion
├── assets/git-commit/
│   ├── SKILL.md              # Skill body (validation logic)
│   └── references/
│       └── git-commit-message.md   # AegisPipe commit convention reference
├── tests/
│   └── skill-git-commit.spec.ts
├── cordis.patch.yml          # Composition layer patch
├── tsdown.config.ts          # Self-contained transpile config
├── package.json
└── README.md / README.zh.md
```

## Quick Start

Prerequisites: `dsh` CLI, Node `^22.19.0 || >=24.0.0`, pnpm 10+.

### Install via dsh CLI

```sh
dsh plugin --profile web add github:7dgroup-ai/dsh-skill-7d-git-commit
```

For the first git install, pnpm will refuse to run the build script until you add the exact package key to the profile's `pnpm-workspace.yaml` under `allowBuilds`. Then re-run the same command.

To avoid the build authorization, use a pre-built tarball or the published npm package:

```sh
dsh plugin --profile web add @7dgroup/dsh-skill-7d-git-commit
```

### Build and Test

```sh
pnpm install
pnpm build   # tsdown; also runs as `prepare` on git installs
pnpm test    # vitest
```

## Usage

Once installed, mention any commit-related request in a dsh session:

> Generate a commit message for the current changes.

The skill will:

1. Analyze the changes.
2. Choose the best matching type tag from the 9 allowed categories.
3. Compose a subject line (`【类型】动作 + 对象`) ≤ 50 chars without trailing punctuation.
4. Add a numbered body for complex changes, each line ≤ 70 chars.
5. Run the validation checklist and reject or fix violations.

## Commit Convention

See `assets/git-commit/references/git-commit-message.md` for the full AegisPipe rules.

High-level requirements:

- Title format: `【类型】简短描述`
- Title length: ≤ 50 characters after the tag
- No trailing `。`, `，`, `.`, `,`
- Forbidden characters in title/body: `@ # $ % ^ & * ~`
- Forbidden phrases: temporary notes, TODO, FIXME, emotional language
- Body lines ≤ 70 chars, numbered list only

## GitLab Integration

The plugin provides both a client-side DSH skill and a server-side GitLab hook. Use them together for "client pre-check + server enforcement".

- Client: `assets/git-commit/SKILL.md` validates commit messages before `git commit`.
- Server: `docs/gitlab-integration/pre-receive` validates pushes before they reach GitLab.
- Rule source: `assets/git-commit/references/git-commit-message.md` shared by both sides.

### Deploy server-side hooks

Copy `docs/gitlab-integration/` to gitlab-01, then run:

```sh
# single-repo pilot
sudo bash install-hooks.sh --pilot devops/aegispipe

# after pilot passes
sudo bash install-hooks.sh --global
```

### Rule synchronization

After updating `docs/gitlab-integration/commit-rules.conf` in this repo:

```sh
sudo bash scripts/sync-rules.sh --global --dry-run
sudo bash scripts/sync-rules.sh --global
```

### Observation and reporting

```sh
# daily summary
sudo bash scripts/audit-report.sh --markdown

# send to DingTalk
export DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
sudo -E bash scripts/dingtalk-notify.sh
```

### Switch to hard reject

1. Complete `docs/gitlab-integration/switch-to-reject-checklist.md`.
2. Change `MODE="reject"` in the deployed `commit-rules.conf`.
3. Take effect immediately on the next push.

For the full deployment SOP, see [`docs/gitlab-integration/deployment-guide.md`](./docs/gitlab-integration/deployment-guide.md).

## Notes

1. The provider contributes a single fixed skill and offers no runtime customization.
2. `prepare` does not emit type declarations; the dsh loader only needs the runtime entry.
3. The build only transpiles; type errors are visible in your editor but not checked during build.
4. The `docs/gitlab-integration/` files are not part of the DSH runtime bundle; copy them to gitlab-01 on demand.

## License

[MIT](LICENSE) · Copyright (c) 2026 7DGroup
