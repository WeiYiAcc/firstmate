---
name: secretspec-mise-patterns
description: How secretspec (sops+age, the single source of truth for secrets) integrates with mise-tracked config files on the captain's hosts. Load before editing any mise-tracked file that may carry a credential, before adding a config file to `mise dotfiles`, when a `{{SECRET_*}}`/`{{EMAIL_*}}` placeholder appears in tracked content, or when a key has leaked into git history.
user-invocable: false
---

# secretspec + mise patterns

Rules for keeping plaintext secrets out of the captain's config plane, verified 2026-10-31 against the live host (VPS) and the `home-manager` / `mise-setup` repos.

## The one rule that matters

**secretspec is the single source of truth for every secret. No plaintext copies may exist anywhere downstream** — not in config files, not in derived `.env` files, not in tracked dotfiles. Every consumer either reads the secret from the environment at runtime or holds a placeholder that resolves at apply time.

Violating this means the key ends up in a git repo (`WeiYiAcc/mise-setup`, `home-manager`) and must be treated as leaked — see "Rotation after a leak" below.

## Architecture on the captain's hosts

```
sops (age)  →  ~/home-manager/secrets.enc.yaml   ← encrypted values, one file
                 │
secretspec.toml (manifest, plaintext-safe, tracked)
  ~/.config/secretspec/secretspec.toml  ← declares WHICH keys exist + providers
                 │
secretspec export --format=shell --reason "..."   ← resolves values at shell start
                 │  (home-manager-generated .bashrc: interactive AND non-interactive)
                 ▼
        environment variables (GPROXY_API_KEY, LINEAR_*, …)
                 │
        client configs reference the env var by name — never the value
```

- **Secrets store**: `~/home-manager/secrets.enc.yaml` — sops-encrypted with age; age key lives at `~/.config/sops/age/key.txt`. `unencrypted_suffix: _unencrypted` means a key literally named `FOO_unencrypted` is stored plaintext inside the encrypted file — reserved for non-sensitive values (URLs, user lists).
- **Manifest**: `~/.config/secretspec/secretspec.toml` declares every key as `KEY = { description = "...", required = false }` under `[profiles.default]`. Providers on this host: `kdbx` (KeePass DB at `~/secrets-sync/secrets.kdbx`, keyfile `~/.config/secretspec/secrets.key`) and `sops_file`. Other hosts may declare only `sops_file` — check the local manifest's `[profiles.default.defaults] providers` before assuming.
- **Injection**: the home-manager-generated `.bashrc` runs `eval "$(secretspec export --format=shell --reason "<caller>")"` for both interactive and non-interactive shells, so agents and `ssh host cmd` see the keys. **`--reason` is mandatory**: since secretspec 0.19.1, `[project].require_reason` defaults to `"agents"` and export silently fails without it (do NOT wrap the eval in `2>/dev/null` — that was the 2026-09-22 silent-empty-keys bug).
- **No derived plaintext files**: the old `api-keys.env` pattern was deliberately deleted (2026-09-15). Never reintroduce a secretspec→plaintext-file step "for convenience".

## mise-tracked files must not contain plaintext keys

mise `dotfiles` history/checkpoints sync tracked file contents to the private `WeiYiAcc/mise-setup` repo. Anything written in plaintext there is a git-history leak even though the repo is private.

**Before `mise dot track <path>` or before letting the autosave watcher pick up an edit:**

1. Replace the literal credential with an env reference the consuming program expands natively — preferred wherever the tool supports it (table below).
2. Where the file format can't expand env vars (e.g. systemd `Environment=` lines in tracked unit files), use a `{{SECRET_<id>}}` placeholder — these exist in the setup repo today (e.g. `Environment=LINEAR_WEBHOOK_SECRET=53032c53429b0c954a424ee360de57cb4d2e1d0f35612e716ef47e17aba94951` in `linear-webhook.service`). Placeholders are resolved by mise's bootstrap/dotfiles template pass at apply time; the id maps to a bootstrap secret input, never inline.
   - Same pattern for non-secret-but-private values: `{{EMAIL_<id>}}` already appears in git author lines.
   - A live unit file under `~/.config/systemd/user/` may hold the rendered value — that file is local; only the mise-tracked copy must stay placeholder-only.
3. Then track. `mise dot track --encrypt` exists for genuinely credential-named files, but env-reference is the first-choice pattern; `--allow-plaintext` is an explicit escape hatch, not a default.

**Native env-reference forms by client** (from `data/learnings.md`, the SSOT convention):

| Client / file | Form | Example |
|---|---|---|
| codex `~/.codex/config.toml` | `env_key = "VAR"` | `env_key = "GPROXY_API_KEY"` under `[model_providers.X]` |
| claude `~/.claude/settings.json` | `apiKeyHelper` (shell command printing the key) or env var | `"ANTHROPIC_AUTH_TOKEN"` env, or `"apiKeyHelper": "secretspec get X --reason ..."` |
| hermes `~/.hermes/config.yaml` | `${VAR}` | `api_key: ${GPROXY_API_KEY}` |
| opencode `~/.config/opencode/opencode.json` | `{env: "VAR"}` | `"apiKey": "{env: GPROXY_API_KEY}"` |
| systemd units (mise-tracked) | `{{SECRET_<id>}}` placeholder, or `EnvironmentFile=` pointing at an untracked local env file | `Environment=LINEAR_WEBHOOK_SECRET=53032c53429b0c954a424ee360de57cb4d2e1d0f35612e716ef47e17aba94951` |
| docker-compose `.env` (untracked, local) | `${VAR}` with real values only in the untracked `.env` | `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}` |

When a file is mise-tracked, prefer the native env-expansion form; reach for `{{SECRET_*}}` only when the file format offers no runtime indirection.

## Adding a new secret — checklist

1. `secretspec set <KEY>` (or `sops ~/home-manager/secrets.enc.yaml`) — value goes only into the provider.
2. Declare it in `~/.config/secretspec/secretspec.toml` under `[profiles.default]` with a description. The manifest itself is plaintext-safe and mise-tracked (`~/.config/mise/config.local.toml` tracks both `~/.config/secretspec/secretspec.toml` and `~/secretspec.toml`) — drift between the tracked manifest and live keys caused real breakage (2026-09-22 "manifest drift" fix).
3. Reference it in consumers via the env var name, using the table above.
4. Verify: new shell → `printenv <KEY>` non-empty; `secretspec get <KEY> --reason "manual check"`.

## Rotation after a key leaks into git history

Discovered plaintext in any repo (including private ones — `mise-setup` counts) → treat as compromised:

1. **Rotate at the provider first** — revoke/regenerate the key at the upstream service. History rewrite does not un-leak it.
2. Update the stored value: `secretspec set <KEY>` so the new value lands in sops/kdbx; commit the `secrets.enc.yaml` + `secretspec.toml` changes (real precedent: `home-manager` commit `ee3d864` — "rotate gptload keys (leaked in git history)").
3. Fix the source of the leak: convert the offending tracked file to `${VAR}`/`env_key`/`{{SECRET_*}}` before re-tracking.
4. Optional history cleanup (`git filter-repo` / jj equivalents) is cosmetic and secondary to rotation — do it if asked, never instead of rotation.
5. Restart/re-source affected consumers: new shell picks up the export; systemd units need `systemctl --user daemon-reload && systemctl --user restart <unit>`.

## Pitfalls observed on this host

- **Never swallow secretspec errors.** `eval "$(secretspec export ...)" 2>/dev/null` hid the `require_reason` failure and left every secret silently empty. Let the warning print.
- **`docker compose config` shows `${VAR}` defaults statically** — it may not reflect the `.env` override; verify runtime env inside the container instead (`docker exec <svc> env | grep X`).
- **secretspec.toml is runtime-mutable** — do not let nix/home-manager manage it as a read-only symlink (that caused dual-file drift); it is deliberately mise-tracked instead.
- **kdbx vs sops_file**: keys may exist in only one provider; `[profiles.default.defaults] providers` order decides resolution. A `secretspec get` miss is often "key declared but value never set in either provider" (e.g. `AGENVO_ADMIN_SECRET` placeholder).
