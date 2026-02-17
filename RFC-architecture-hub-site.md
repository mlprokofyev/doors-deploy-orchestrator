# RFC: Doors Hub Page & Multi-Game Architecture

**Status:** Draft  
**Date:** 2026-02-16  
**Context:** Architecture for a main website with a `/doors` hub page routing to multiple independent game scenes.

---

## 1. Overview

A website hosts a `/doors` page that acts as a visual hub — a tiled wall of pixel-art doors. Each door is an entry point to an independent web-game scene (e.g., `/doors/1`, `/doors/2`, ... `/doors/N`). The system must scale to ~100 game scenes plus other non-game content pages.

---

## 2. Target Architecture

### 2.1 Three-Tier URL Structure

```
yourdomain.com/                    → Main site (landing, about, etc.)
yourdomain.com/doors               → Doors hub page (this RFC)
yourdomain.com/doors/{number}      → Individual game scene
```

### 2.2 Composition Model: Static Micro-Frontends

Each game scene is an **independent static Vite build** deployed to its own sub-path. The main site (including `/doors`) is a separate project. Composition happens at the **build/deploy level** — a deploy orchestrator assembles all builds into a single directory tree served as one Render Static Site.

| Layer | Technology | Responsibility |
|---|---|---|
| Main site + `/doors` | Astro (recommended) or Next.js | Global layout, navigation, hub page, content pages |
| Game scenes | Independent Vite SPAs (TypeScript + Canvas) | Self-contained game experiences |
| Composition | Deploy orchestrator (GitHub Actions) | Assemble all builds into one static tree |
| Hosting | Render Static Site | Serve the assembled tree from a single origin |

### 2.3 No Runtime Coupling

- Games do not share a framework or runtime with the shell.
- Navigation between hub and game is **full page navigation** (`<a>` tags / `window.location`).
- No iframes. No shared SPA router across the boundary.
- Shared code (if any) is consumed via **npm packages at build time**.

---

## 3. Doors Hub Page — Functional Specification

### 3.1 Layout

- **Header:** Site logo + title ("Doors.")
- **Body:** A tiled grid of doors. Doors are placed edge-to-edge with **no gaps** between them — a continuous wall of doors. Each door has a visible **door frame** as part of its sprite.
- **Scrollable:** Vertical scroll. The page is a long wall of doors, not paginated.
- **Responsive:** Adapts column count to viewport width. Mobile-friendly (single or dual column on small screens, more columns on desktop).

### 3.2 Door States

Each door has two states:

| State | Appearance | Behavior |
|---|---|---|
| **Active** | Unique pixel-art design, colored, visually distinct per door | Clickable → triggers open animation → navigates to game |
| **Inactive** | Greyed-out / desaturated, uniform design | Not clickable, visually locked |

- Every active door has a **unique** pixel-art design (different color, texture, decorations).
- Inactive doors share the same grey template.
- All doors display their **number** (the route number, e.g., "8") as part of the door sprite or overlaid.

### 3.3 Door Numbering & Order

- Doors are numbered sequentially: 1, 2, 3, ...
- The number is part of the route: `/doors/8` opens game scene 8.
- Order is **meaningful and fixed** (e.g., progression, release order, narrative order — not random).
- The door number is visually rendered on each door (as a pixel-art plaque, engraving, or overlay).

### 3.4 Door Interactions

#### Click → Open → Navigate

1. User clicks an **active** door.
2. Door plays a **pixel-art opening animation** (door swings open, revealing a dark void behind it).
3. A **full-screen dark void transition** covers the viewport (fade to black / expanding darkness from the door).
4. During the dark void, the browser navigates to `/doors/{N}/` — the game scene loads directly.
5. The game scene takes over the full viewport. No hub UI is visible during gameplay.

#### Decorative Open/Close (Hover/Idle)

- Doors may have a subtle **decorative open/close animation** on the hub page itself (e.g., slight creak on hover, idle breathing animation).
- This is purely visual — it does not trigger navigation.
- Distinct from the click-to-enter animation.

### 3.5 Transition: Dark Void

After the door open animation completes:
- A **dark void / black screen** fills the viewport.
- This masks the page navigation latency.
- Implementation: CSS full-screen overlay with opacity transition, or canvas-drawn expanding black circle from the door's position.
- The game scene at `/doors/{N}/` loads directly (full page navigation, not an iframe or dynamic import).

---

## 4. Technical Implementation — Hub Page

### 4.1 Rendering Approach: HTML + CSS Grid + Sprite Sheets

**Not Canvas.** The hub page is a standard web page, not a game. Use:

- **CSS Grid** for the door layout (responsive columns, no gaps: `gap: 0`).
- **Pixel-art sprites** for each door (PNG sprite sheets or individual images).
- **CSS `image-rendering: pixelated`** for crisp pixel art at any scale.
- **CSS animations or JS sprite-frame animation** for door open/close.
- **CSS filter: `grayscale(1)` + `brightness(0.6)`** for inactive doors (one sprite, filtered via CSS — or separate grey sprite if the visual needs to differ more).

Rationale: CSS Grid handles responsive layout natively. Sprite-based doors are lightweight, cacheable, and don't require a canvas runtime for a static hub page.

### 4.2 Sprite Animation System

Each door's open animation is a **sprite sheet** (horizontal strip of frames):

```
door_8_open.png → [frame0][frame1][frame2][frame3][frame4]
```

Animation playback via:
- CSS `steps()` animation on `background-position`, or
- A lightweight JS controller that advances frames on a `requestAnimationFrame` loop and swaps `background-position`.

Frame count: ~6–10 frames for a smooth open. Duration: ~400–600ms.

### 4.3 Door Data Model

```typescript
interface DoorEntry {
  number: number;          // Door number (1-based), used in route
  status: 'active' | 'inactive';
  title?: string;          // Game title (for tooltip / aria-label)
  spriteSheet?: string;    // Path to unique door sprite sheet (active doors)
  // Inactive doors use a shared default sprite
}
```

Source: **Static JSON file** or **Astro content collection** (`.md` / `.yaml` files per door in `src/content/doors/`).

### 4.4 Responsive Grid

```css
.doors-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  gap: 0;
}
```

- `minmax(120px, 1fr)` — doors scale up to fill space, collapse columns on smaller screens.
- Exact min-width depends on the door sprite's native pixel dimensions × desired scale factor.
- Mobile: 2–3 columns. Tablet: 4–5. Desktop: 6–8+.

### 4.5 Dark Void Transition

```
[User clicks door]
  → Play door-open sprite animation (~500ms)
  → Trigger full-screen black overlay (CSS opacity 0→1, ~300ms)
  → On overlay `transitionend`, do `window.location.href = '/doors/{N}/'`
  → Game page loads under the black screen
```

The game page itself should start with a black background so there's no flash of white during load.

---

## 5. Technical Implementation — Game Scenes

### 5.1 Per-Game Requirements

Each game scene (like `perun-pixel-web-d4`) must:

1. **Set `base` in `vite.config.ts`** to its sub-path:
   ```typescript
   base: '/doors/8/'
   ```
2. **Use relative or base-aware asset paths.** Replace absolute `/assets/...` paths with `import.meta.env.BASE_URL + 'assets/...'` or relative paths.
3. **Start with a black/dark background** to seamlessly continue the dark void transition from the hub.
4. **Include a "back to hub" control** — a button/link that navigates to `/doors`.
5. **Build to `dist/`** as a fully self-contained static bundle.

### 5.2 Deployment

Each game builds independently in its own CI pipeline. The build artifact (`dist/`) is uploaded as a GitHub Actions artifact. A central **deploy orchestrator** then downloads all artifacts and assembles them into the final directory tree:

```
assembled/
  index.html              ← from main-site build
  doors/
    index.html            ← from main-site build (hub page)
    1/
      index.html          ← from door-1 artifact
      assets/...
    2/
      index.html          ← from door-2 artifact
      assets/...
    ...
```

This assembled tree is deployed as a **single Render Static Site**.

### 5.3 Render Static Site Configuration

The assembled tree is served directly by Render. No reverse proxy is needed — all files exist under a single origin.

Render rewrite rules (configured in `render.yaml` or the Render dashboard) handle SPA fallback for each game:

```yaml
# render.yaml (in deploy-orchestrator repo)
services:
  - type: web
    name: doors-site
    env: static
    buildCommand: "echo 'pre-built'"
    staticPublishPath: ./assembled
    routes:
      - type: rewrite
        source: /doors/1/*
        destination: /doors/1/index.html
      - type: rewrite
        source: /doors/2/*
        destination: /doors/2/index.html
      # Add a rewrite rule for each game
```

As game count grows, these rewrite rules can be auto-generated by the orchestrator script from `games.yaml`.

---

## 6. Repository & CI/CD Strategy

### 6.1 Polyrepo + Deploy Orchestrator

| Repo | Contents |
|---|---|
| `main-site` | Astro project: landing page, `/doors` hub, content pages |
| `door-1-game-name` | Vite game project for door 1 |
| `door-2-game-name` | Vite game project for door 2 |
| ... | ... |
| `deploy-orchestrator` | CI config, `games.yaml` manifest, Render deploy hook. **No application code.** |

### 6.2 Deploy Manifest

The `deploy-orchestrator` repo contains a manifest that is the single source of truth for all deployed games:

```yaml
# games.yaml
main_site:
  repo: your-org/main-site
  path: /

games:
  - number: 1
    repo: your-org/door-1-perun-pixel
    path: /doors/1/
  - number: 2
    repo: your-org/door-2-future-game
    path: /doors/2/
```

Adding a new game = adding 3 lines to this file.

### 6.3 CI/CD Pipeline

#### Step 1: Game Repo CI (runs in each game repo on push to `main`)

1. `npm ci`
2. `npm run build` (Vite build with `base: '/doors/N/'`)
3. Upload `dist/` as a **GitHub Actions artifact** (retained 30–90 days)
4. Trigger the orchestrator via `workflow_dispatch` on the `deploy-orchestrator` repo

Same flow for `main-site` (Astro build → artifact → trigger orchestrator).

#### Step 2: Orchestrator CI (runs in `deploy-orchestrator`)

Triggered by any game/main-site repo, or manually:

1. Read `games.yaml` to get the list of all repos
2. For each repo, download the **latest successful build artifact** (via GitHub API, cross-repo artifact download with `actions:read` permission)
3. Assemble the directory tree under `assembled/`
4. Deploy to Render via **deploy hook** (POST to Render's deploy URL) or push to a `deploy` branch that Render watches

#### Pipeline Diagram

```
 door-1 repo          door-2 repo          main-site repo
   push to main         push to main         push to main
       │                    │                    │
       ▼                    ▼                    ▼
   [Build CI]           [Build CI]           [Build CI]
   npm run build        npm run build        npm run build
       │                    │                    │
       ▼                    ▼                    ▼
   Upload artifact      Upload artifact      Upload artifact
       │                    │                    │
       └────────────────────┼────────────────────┘
                            │
                   trigger workflow_dispatch
                            │
                            ▼
                ┌───────────────────────┐
                │  deploy-orchestrator  │
                │                       │
                │  1. Read games.yaml   │
                │  2. Download all      │
                │     artifacts         │
                │  3. Assemble tree     │
                │  4. Deploy to Render  │
                └───────────────────────┘
                            │
                            ▼
                   ┌─────────────────┐
                   │  Render Static  │
                   │  Site (single)  │
                   │                 │
                   │  yourdomain.com │
                   └─────────────────┘
```

#### Failure Isolation

- If game 5's build fails, its artifact isn't updated. The orchestrator uses the **last successful artifact** for each game. Other games are unaffected.
- A broken game build never blocks deployment of other games.
- Manual full redeploy: run the orchestrator workflow manually to re-download all latest artifacts.

### 6.4 Why Not Monorepo

At 100 games, a monorepo would:
- Have slow CI (every push rebuilds/tests everything unless carefully filtered).
- Create merge conflicts across unrelated games.
- Couple deploy cycles.

Polyrepo keeps blast radius small and deploy cycles independent. The `deploy-orchestrator` is the only coupling point, and it contains no application code.

### 6.5 Shared Code

If multiple games share engine code, rendering utilities, or sprite systems:
- Extract into a **private npm package** (e.g., `@yourdomain/game-engine`).
- Publish to GitHub Packages or a private registry.
- Each game consumes it as a `devDependency`.
- Version independently — games opt into engine upgrades.

### 6.6 Scaling Considerations

| Scale | Strategy |
|---|---|
| **1–10 games** | Current pipeline works trivially. Orchestrator runs in ~30s. |
| **10–50 games** | Still fast. Parallel artifact downloads take seconds. |
| **50–100 games** | Consider switching artifact storage from GitHub Actions artifacts to an object store (S3/R2) for faster downloads. |
| **100+ games** | Migrate to a reverse-proxy architecture (Render Web Service with Caddy/Nginx proxying to individual Render Static Sites) to eliminate the assembly step entirely. Game builds and repo structure remain unchanged — only the orchestrator and hosting layer change. |

---

## 7. Asset Pipeline for Doors

### 7.1 Door Sprites

Each active door needs:
- **Closed sprite** (single frame or idle animation loop) — unique per door.
- **Open animation sprite sheet** (6–10 frames) — unique per door.
- **Number overlay** — either baked into the sprite or rendered via CSS/HTML.

Inactive doors need:
- **One shared grey door sprite** (closed state only).
- **Number overlay.**

### 7.2 Sprite Naming Convention

```
public/
  assets/
    doors/
      door-default-inactive.png       # Shared inactive door
      door-1-closed.png               # Door 1 closed state
      door-1-open.png                 # Door 1 open animation strip
      door-2-closed.png
      door-2-open.png
      ...
```

### 7.3 Optimization

- Sprite sheets should be power-of-2 width for GPU-friendly rendering.
- Use **WebP** with PNG fallback for smaller file sizes.
- Lazy-load door sprites below the fold (`loading="lazy"` on `<img>` or Intersection Observer for background images).
- Total asset budget for 100 doors: ~100 × (closed ~2KB + open ~10KB) ≈ ~1.2MB. Acceptable with lazy loading.

---

## 8. Accessibility & SEO

- Each door is a semantic `<a>` tag wrapping the sprite, with `aria-label="Door {N}: {game title}"`.
- Inactive doors use `aria-disabled="true"` and `tabindex="-1"`.
- Page has proper `<h1>` ("Doors"), meta description, and structured heading hierarchy.
- Each game scene's `index.html` has its own `<title>` and meta tags.

---

## 9. Summary of Action Items

### To set up the deploy infrastructure:

1. Create the `deploy-orchestrator` repo with `games.yaml` manifest.
2. Write the orchestrator GitHub Actions workflow (download artifacts → assemble → deploy).
3. Create a Render Static Site, connect it to the `deploy-orchestrator` repo (or configure deploy hook).
4. Configure Render rewrite rules for SPA fallback per game.

### To start the main site / doors hub project:

1. Initialize Astro project in the `main-site` repo.
2. Implement the doors grid layout (CSS Grid, no gaps, responsive).
3. Create the door component (sprite rendering, active/inactive states, number display).
4. Implement the door open animation (sprite sheet playback).
5. Implement the dark void transition (full-screen overlay → navigate).
6. Set up the door data model (JSON or content collection).
7. Create the initial set of door pixel-art sprites.
8. Set up CI: build → upload artifact → trigger orchestrator.

### To prepare each game for deployment under `/doors/{N}/`:

1. Set `base` in `vite.config.ts` to `/doors/{N}/`.
2. Make all asset paths relative to `base`.
3. Ensure the game starts with a dark/black screen.
4. Add a "back to hub" navigation element.
5. Set up CI: build → upload artifact → trigger orchestrator.
6. Add the game entry to `games.yaml` in `deploy-orchestrator`.

---

## 10. Open Questions

- **Authentication / user accounts?** If games track progress, need to decide on auth strategy (shared cookies, JWT, etc.).
- **Analytics?** Shared analytics script loaded by each game, or only on the hub?
- **Door unlocking logic?** Are doors unlocked by progression (complete door N to unlock N+1), or independently? This affects the data model.
- **Sound?** Door creak sound effect on the hub page when opening?
