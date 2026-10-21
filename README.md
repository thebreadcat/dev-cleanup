# dev-cleanup

Reclaim gigabytes from old dev projects. Finds JS and PHP projects you haven't touched in 30 days and deletes the stuff that `npm install` / `composer install` can rebuild: `node_modules`, build output, and framework caches.

One bash script, no dependencies. Dry run by default.

## Try it (nothing is deleted)

```bash
curl -fsSL https://raw.githubusercontent.com/thebreadcat/dev-cleanup/main/dev-cleanup.sh | bash -s -- ~/code
```

Swap `~/code` for wherever your projects live. When you like what it reports, add `--yes`:

```bash
curl -fsSL https://raw.githubusercontent.com/thebreadcat/dev-cleanup/main/dev-cleanup.sh | bash -s -- --yes ~/code
```

## Install + run weekly (macOS)

```bash
git clone https://github.com/thebreadcat/dev-cleanup && dev-cleanup/install.sh --schedule ~/code
```

This installs a `dev-cleanup` command to `~/.local/bin` and a launchd job that runs every Sunday at 9:00 (it catches up after sleep). The log goes to `~/Library/Logs/dev-cleanup.log`. Pass flags for the weekly run after `--`:

```bash
dev-cleanup/install.sh --schedule ~/code ~/work -- --days 60 --dropbox
```

To remove it: `dev-cleanup/install.sh --uninstall`

## What it deletes

Only from projects with **no file changes in the last `--days` days** (default 30):

| Next to | Removed |
|---|---|
| `package.json` | `node_modules` `.next` `.nuxt` `.svelte-kit` `.angular` `.turbo` `.parcel-cache` `storybook-static` |
| `package.json` | `dist` `build` `out` `coverage` `.cache`, but **only if git ignores them** |
| `composer.json` + `composer.lock` | `vendor` |

Safety rails:

- Dry run unless you pass `--yes`.
- Generic names like `build/` are never touched in a project that isn't a git repo, or where they're committed.
- Active projects are left alone. "Active" means any source file changed recently. `node_modules` and build output don't count.
- Won't scan `/`, `~/Library`, or the Trash.

## Options

```
-y, --yes        Actually delete
-d, --days N     Stale after N days without changes (default 30, 0 = everything)
    --dropbox    Mark node_modules etc. in active projects as Dropbox-ignored (macOS)
    --docker     docker system prune -af (never touches volumes)
    --xcode      Clear Xcode DerivedData
    --gradle     Clear ~/.gradle/caches
    --brew       brew cleanup --prune=7
    --pnpm       pnpm store prune
    --system     All of the above system cleanups
```

## Dropbox users

Dropbox doesn't read `.gitignore`, so `node_modules` in a synced folder means hundreds of thousands of files churning. `--dropbox` sets Dropbox's ignore attribute on heavy folders in active projects, so they stay on disk but stop syncing. Stale projects get those folders deleted instead.

## License

MIT
