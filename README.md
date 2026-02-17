# Doors Deploy Orchestrator

Deploy orchestrator that assembles the [Doors](https://github.com/mlprokofyev/doors-web) main site and independent game scenes into a single static directory tree, deployed as one [Render](https://render.com) Static Site.

**This repo contains no application code** — only CI configuration, a deploy manifest, and an assembly script.

## Architecture

```
 doors-web              perun-web-game-demo      (future games...)
   (Astro)               (Vite + Canvas)
     │                        │
     ▼                        ▼
  npm run build            npm run build
     │                        │
     ▼                        ▼
   dist/                    dist/
     │                        │
     └────────────┬───────────┘
                  │
       ┌──────────▼──────────┐
       │  deploy-orchestrator │
       │                      │
       │  1. Read games.yaml  │
       │  2. Clone & build    │
       │  3. Assemble tree    │
       │  4. Push to deploy   │
       └──────────┬──────────┘
                  │
                  ▼
        Render Static Site
        (single origin)
```

The orchestrator clones each repo listed in `games.yaml`, runs its build command, and copies the output into the correct sub-path of an `assembled/` directory. That directory is force-pushed to the `deploy` branch, which Render watches and serves.

## Assembled Output

```
assembled/
  index.html                ← doors-web landing page
  doors/
    index.html              ← doors-web hub page (/doors)
    1/
      index.html            ← perun-web-game-demo (/doors/1/)
      assets/...
    2/                      ← future game
      index.html
      assets/...
```

Each game is a fully self-contained static bundle under `/doors/{N}/`. No runtime coupling between the main site and games — navigation is standard full-page `<a>` links.

## Repository Structure

```
doors-deploy-orchestrator/
├── games.yaml                    # Deploy manifest (single source of truth)
├── render.yaml                   # Render Static Site blueprint
├── scripts/
│   └── assemble.sh               # Clone, build, assemble all repos
├── .github/
│   └── workflows/
│       └── deploy.yml            # GitHub Actions: assemble → push → Render
├── .gitignore
└── README.md
```

## games.yaml — Deploy Manifest

The manifest defines every repo that gets assembled into the final site:

```yaml
main_site:
  repo: mlprokofyev/doors-web
  build_cmd: npm run build
  dist_dir: dist
  path: /

games:
  - number: 1
    repo: mlprokofyev/perun-web-game-demo
    build_cmd: npm run build
    dist_dir: dist
    path: /doors/1/
```

| Field       | Description                                      |
|-------------|--------------------------------------------------|
| `repo`      | GitHub `owner/name` (public or private with PAT) |
| `build_cmd` | Shell command to produce the static build         |
| `dist_dir`  | Output directory of the build (relative to repo root) |
| `path`      | URL path where the build is mounted               |
| `number`    | Door number — determines route `/doors/{number}/` |

## Adding a New Game

1. **Prepare the game repo.** Set `base: '/doors/{N}/'` in `vite.config.ts` so all asset paths resolve correctly under the sub-path. Ensure `npm run build` outputs to `dist/`.

2. **Add to `games.yaml`:**
   ```yaml
   games:
     # ... existing games ...
     - number: 2
       repo: mlprokofyev/my-new-game
       build_cmd: npm run build
       dist_dir: dist
       path: /doors/2/
   ```

3. **Add a Render rewrite rule** in `render.yaml`:
   ```yaml
   routes:
     # ... existing routes ...
     - type: rewrite
       source: /doors/2/*
       destination: /doors/2/index.html
   ```
   Also add this rewrite in the Render dashboard under Redirects/Rewrites.

4. **Push to `main`.** The workflow triggers automatically and deploys the updated site.

## CI/CD Pipeline

### Triggers

The `deploy.yml` workflow runs on:

- **`workflow_dispatch`** — triggered manually or by game repos after their own CI completes
- **Push to `main`** — when `games.yaml`, `scripts/`, `render.yaml`, or the workflow itself changes

### Workflow Steps

1. Checkout this repo
2. Setup Node.js 20 + yq
3. Run `scripts/assemble.sh` (clones all repos, installs deps, builds, assembles)
4. Force-push `assembled/` contents to the `deploy` branch
5. Render auto-deploys from `deploy`

### Triggering from Game Repos

Add this step to each game repo's CI workflow (after a successful build):

```yaml
- name: Trigger deploy orchestrator
  run: |
    gh workflow run deploy.yml \
      -R mlprokofyev/doors-deploy-orchestrator \
      -f trigger_repo=${{ github.repository }}
  env:
    GH_TOKEN: ${{ secrets.ORCHESTRATOR_DISPATCH_TOKEN }}
```

Requires a PAT with `actions:write` scope on this repo, stored as `ORCHESTRATOR_DISPATCH_TOKEN` in the game repo's secrets.

### Manual Deploy

```bash
gh workflow run deploy.yml -R mlprokofyev/doors-deploy-orchestrator
```

Or use the **Actions** tab → **Assemble & Deploy** → **Run workflow**.

## Render Setup

### Option A: Blueprint (render.yaml)

1. Render Dashboard → **Blueprints** → **New Blueprint**
2. Connect this repo, Render reads `render.yaml` and creates the Static Site

### Option B: Manual

1. Render Dashboard → **New** → **Static Site**
2. Connect `mlprokofyev/doors-deploy-orchestrator`, branch: **`deploy`**
3. Build command: `echo 'pre-built'`
4. Publish directory: `./`
5. Add rewrite rules under **Redirects/Rewrites**:

| Source         | Destination              | Type    |
|----------------|--------------------------|---------|
| `/doors/1/*`   | `/doors/1/index.html`    | Rewrite |

Add one rewrite per game scene for SPA fallback.

### Cache Headers

Configured in `render.yaml`. Hashed asset files (`/assets/*`, `/doors/*/assets/*`) get immutable year-long caching. HTML files use Render's default short cache.

## Secrets

| Secret      | Where          | Required | Purpose                                      |
|-------------|----------------|----------|----------------------------------------------|
| `GH_TOKEN`  | This repo      | Only for private source repos | PAT with `contents:read` on game repos |
| `GITHUB_TOKEN` | Auto-provided | Always   | Push to `deploy` branch (built-in Actions token) |
| `ORCHESTRATOR_DISPATCH_TOKEN` | Game repos | For auto-trigger | PAT with `actions:write` on this repo |

For public source repos (current setup), `GH_TOKEN` is not needed.

## Local Development

Run the assembly locally (requires Node.js 18+, npm, git, [yq](https://github.com/mikefarah/yq)):

```bash
./scripts/assemble.sh
```

The assembled site will be in `assembled/`. Serve it locally:

```bash
npx serve assembled
```

## Game Repo Requirements

Each game deployed under `/doors/{N}/` must:

1. Set `base: '/doors/{N}/'` in `vite.config.ts`
2. Use base-relative asset paths (`import.meta.env.BASE_URL + 'path'` or relative paths)
3. Start with a dark/black background (seamless transition from the hub's dark void animation)
4. Include a "back to hub" link navigating to `/doors`
5. Build to a self-contained static bundle via `npm run build`

## Failure Isolation

- If a game repo's build fails during assembly, the workflow fails and nothing is deployed. The previous successful deploy remains live on Render.
- A broken game build never affects other games' code — only the deploy pipeline is blocked until fixed.
- To deploy without a broken game, temporarily remove it from `games.yaml` and push.

## Scaling

| Scale        | Strategy                                                                 |
|--------------|--------------------------------------------------------------------------|
| 1–10 games   | Current pipeline. Orchestrator runs in under 2 minutes.                  |
| 10–50 games  | Still fast. Consider parallel builds in the assemble script.             |
| 50–100 games | Switch to artifact-based flow (each repo uploads pre-built tarballs).    |
| 100+ games   | Migrate to reverse-proxy architecture (Caddy/Nginx routing to per-game static sites). |

## Related Repos

| Repo | Description |
|------|-------------|
| [doors-web](https://github.com/mlprokofyev/doors-web) | Main site: landing page + `/doors` hub (Astro) |
| [perun-web-game-demo](https://github.com/mlprokofyev/perun-web-game-demo) | Door 1: pixel-art game scene (Vite + Canvas) |
