import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { Context } from '@deepseek-ai/cordis'
import { describe, expect, it } from 'vitest'
import SkillRegistry from '@deepseek-ai/dsh-skill'
import * as SkillGitCommit from '@7dgroup/dsh-skill-7d-git-commit'

describe('dsh-skill-7d-git-commit', () => {
  it('registers and disposes the bundled git commit skill', async () => {
    const ctx = new Context()
    await ctx.plugin(SkillRegistry)
    const fiber = await ctx.plugin(SkillGitCommit)
    const resourcePath = fileURLToPath(new URL('../assets/7d-git-commit/', import.meta.url)).replace(/[\\/]$/, '')

    expect(await ctx.skills.list()).toEqual([{
      name: '7d-git-commit',
      description: 'AegisPipe 提交规范适配 Skill：在生成 git commit message 前自动校验并套用盛盾 AegisPipe 项目的提交规范，规避服务端 pre-receive hook 拦截。当用户需要 git commit 或生成提交信息时使用。',
      invocation: { modelInvocable: true, userInvocable: true },
      provider: '7d-git-commit',
      source: 'bundled',
      resourceBase: { kind: 'directory', path: resourcePath },
    }])
    const loaded = await ctx.skills.get('7d-git-commit')
    expect(loaded?.content).toContain('## 校验清单')
    expect(loaded?.content).toContain('references/git-commit-message.md')
    expect(loaded?.resourceBase).toEqual({ kind: 'directory', path: resourcePath })

    await fiber.dispose()
    expect(await ctx.skills.list()).toEqual([])
  })

  it('ships the commit rule reference beside the body', async () => {
    const base = new URL('../assets/7d-git-commit/', import.meta.url)
    await expect(readFile(new URL('references/git-commit-message.md', base), 'utf8')).resolves.not.toBe('')
  })
})
