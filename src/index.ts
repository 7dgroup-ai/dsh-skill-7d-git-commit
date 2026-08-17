/**
 * Bundled `7d-git-commit` skill provider.
 *
 * @module @7dgroup/dsh-skill-7d-git-commit
 */

import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import type { Context } from '@deepseek-ai/cordis'
import {
  BUNDLED_SKILL_RANK,
  type SkillCandidate,
  type SkillDefinition,
  type SkillProvider,
} from '@deepseek-ai/dsh-skill'

const PROVIDER_NAME = '7d-git-commit'
const SKILL_BODY_URL = new URL('../assets/7d-git-commit/SKILL.md', import.meta.url)
const RESOURCE_BASE = {
  kind: 'directory',
  path: fileURLToPath(new URL('../assets/7d-git-commit/', import.meta.url)).replace(/[\\/]$/, ''),
} as const
const INVOCATION = { modelInvocable: true, userInvocable: true } as const
const DESCRIPTION = 'AegisPipe 提交规范适配 Skill：在生成 git commit message 前自动校验并套用盛盾 AegisPipe 项目的提交规范，规避服务端 pre-receive hook 拦截。当用户需要 git commit 或生成提交信息时使用。'

// rank 语义（ctx.skills 同层同名技能按 rank 升序取优，小者胜出）：
//   项目 .dsh/skills=100 · 项目 .agents/skills=200 · custom=300 ·
//   ~/.dsh/skills=400 · ~/.agents/skills=500 · bundled=600
// BUNDLED_SKILL_RANK 是所有根中最低优先级，因此任何本地文件系统同名
// `7d-git-commit` 技能（如 ~/.agents/skills/7d-git-commit、项目 .agents/skills/）
// 都会覆盖本包技能。安装后会话中"看不到 AegisPipe 版"多为该原因 ——
// 技能仍由本 provider 正常注册，只是被更高优先级的同名候选遮蔽，
// 诊断与处理见 README「故障排查」章节。

/* jscpd:ignore-start */
const CANDIDATE: SkillCandidate = {
  name: PROVIDER_NAME,
  description: DESCRIPTION,
  invocation: INVOCATION,
  provider: PROVIDER_NAME,
  source: 'bundled',
  resourceBase: RESOURCE_BASE,
  rank: BUNDLED_SKILL_RANK,
  locator: SKILL_BODY_URL,
}

const provider: SkillProvider = {
  name: PROVIDER_NAME,
  list: () => Promise.resolve([CANDIDATE]),
  async get(_candidate): Promise<SkillDefinition> {
    return {
      name: CANDIDATE.name,
      description: CANDIDATE.description,
      invocation: CANDIDATE.invocation,
      provider: CANDIDATE.provider,
      source: CANDIDATE.source,
      resourceBase: RESOURCE_BASE,
      content: await readFile(SKILL_BODY_URL, 'utf8'),
    }
  },
}

/** Cordis plugin name. */
export const name = 'skill-7d-git-commit'
/** Service required by the bundled provider. */
export const inject = ['skills']

/** Register the bundled `7d-git-commit` provider on `ctx.skills`. */
export function apply(ctx: Context): void {
  ctx.skills.registerProvider(() => provider)
}
/* jscpd:ignore-end */
