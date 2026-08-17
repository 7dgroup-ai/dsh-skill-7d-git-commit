/**
 * Package-owned invariant companion for `@7dgroup/dsh-skill-7d-git-commit`.
 * @module @7dgroup/dsh-skill-7d-git-commit/invariant
 */

/* jscpd:ignore-start */
import type { Context } from '@deepseek-ai/cordis'
import type { InvariantInstaller } from '@deepseek-ai/dsh-invariants'

const PACKAGE_NAME = '@7dgroup/dsh-skill-7d-git-commit'
const SKILL_NAME = '7d-git-commit'

/** Cordis companion plugin name. */
export const name = 'skill-7d-git-commit-invariant'
/** Service required before the companion can reserve package ownership. */
export const inject = ['invariants']

/**
 * Startup invariant: the bundled `7d-git-commit` provider must expose exactly one
 * skill whose name matches the package contract. Registration uniqueness and
 * lifecycle remain owned by the skill registry.
 *
 * When the bundled skill is shadowed by a same-name local skill (filesystem
 * roots outrank the bundled rank 600 — project `.dsh/skills`=100,
 * project `.agents/skills`=200, custom=300, `~/.dsh/skills`=400,
 * `~/.agents/skills`=500), the visible catalog carries the local winner and
 * this provider's skill disappears from `ctx.skills.list()`. The failure
 * message then names the shadowing provider so the operator can locate and
 * remove/rename the conflicting skill directory (see README troubleshooting).
 */
const install: InvariantInstaller = async (ctx, fail) => {
  const skills = await ctx.skills.list()
  const matches = skills.filter((skill) => skill.provider === SKILL_NAME)
  if (matches.length !== 1 || matches[0]?.name !== SKILL_NAME) {
    const winners = skills.filter((skill) => skill.name === SKILL_NAME)
    const detail = winners.length > 0
      ? `"${SKILL_NAME}" is shadowed by ${winners.map((skill) => `"${skill.name}" (provider "${skill.provider}", source "${skill.source}")`).join(', ')} — a same-name skill from a higher-priority root outranks the bundled rank 600; remove or rename the conflicting skill directory`
      : `no skill named "${SKILL_NAME}" is visible in the catalog`
    fail(`expected exactly 1 bundled skill named "${SKILL_NAME}", found ${matches.length}; ${detail}`)
  }
}
/** The installer runs in a child fiber and needs read access to `ctx.skills`. */
;(install as { inject?: string[] }).inject = ['skills']

/**
 * Register this package's invariant companion.
 * @param ctx - Cordis context carrying the invariant service.
 * @returns the installed registration's disposer after setup succeeds.
 */
export const apply = (ctx: Context): Promise<() => void> =>
  Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install))
/* jscpd:ignore-end */
