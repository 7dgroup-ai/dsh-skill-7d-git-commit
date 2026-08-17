/**
 * Package-owned invariant companion for `@7dgroup/dsh-skill-7d-git-commit`.
 * @module @7dgroup/dsh-skill-7d-git-commit/invariant
 */

/* jscpd:ignore-start */
import type { Context } from '@deepseek-ai/cordis'
import type { InvariantInstaller } from '@deepseek-ai/dsh-invariants'

const PACKAGE_NAME = '@7dgroup/dsh-skill-7d-git-commit'
const SKILL_NAME = 'git-commit'

/** Cordis companion plugin name. */
export const name = 'skill-git-commit-invariant'
/** Service required before the companion can reserve package ownership. */
export const inject = ['invariants']

/**
 * Startup invariant: the bundled `git-commit` provider must expose exactly one
 * skill whose name matches the package contract. Registration uniqueness and
 * lifecycle remain owned by the skill registry.
 */
const install: InvariantInstaller = async (ctx, fail) => {
  const skills = await ctx.skills.list()
  const matches = skills.filter((skill) => skill.provider === SKILL_NAME)
  if (matches.length !== 1 || matches[0]?.name !== SKILL_NAME) {
    fail(`expected exactly 1 bundled skill named "${SKILL_NAME}", found ${matches.length}`)
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
