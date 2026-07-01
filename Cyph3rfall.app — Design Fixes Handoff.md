# Cyph3rfall.app — Design Fixes Handoff

**Source files:** `/Users/gstock/MatrixRainSaver/docs/` **Files to edit:** `index.html` (primary), `changelog.html` (secondary) **Context:** All CSS is inline in each HTML file. No separate stylesheet. No build step — edits go directly in the HTML.

This handoff addresses findings from an audit against the [vibecoded-design-tells](https://github.com/vibecoded-design-tells) catalog. The site is in strong shape overall — the fixes below are targeted and surgical. Do not change the color palette, font stack, layout structure, or anything not listed here.

------

## Fix 1 — Replace emoji icons with SVG icons (HIGH PRIORITY)

### What to do

Replace every emoji used as a UI icon with an inline SVG. The emoji-as-icons pattern is the highest-signal tell in the catalog for a technical audience.

Use **Lucide icons** — they are MIT licensed, monoline, and match the app's aesthetic well. Fetch the SVG paths from `https://lucide.dev/icons/` or use the raw SVG source at `https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/<name>.svg`.

### Icon mapping for `index.html` — features grid

Replace each `.feature-icon` span. The SVG should be rendered at `24px × 24px`, stroke `currentColor`, no fill, stroke-width `1.5`. Apply a class or inline style to set the color to `var(--green-dim)` and `display: block; margin-bottom: 0.75rem;`.

| Current emoji | Feature title               | Suggested Lucide icon name |
| ------------- | --------------------------- | -------------------------- |
| ☰             | Lives in the Menu Bar       | `menu`                     |
| ⏱             | Idle Activation             | `timer`                    |
| ⌨️             | Global Shortcut             | `keyboard`                 |
| 🖥             | Multi-Monitor               | `monitor`                  |
| 🎨             | 9 Color Presets             | `palette`                  |
| 🌈             | Chromafall                  | `rainbow`                  |
| 🌅             | Spectrafall                 | `sun-medium`               |
| 💬             | Message Overlay             | `message-square`           |
| 🕐             | Clock Overlay               | `clock`                    |
| 🔒             | Password Lock               | `lock`                     |
| 🎛             | Deep Customisation          | `sliders-horizontal`       |
| 🪄             | No Frameworks               | `sparkles`                 |
| 🔄             | Auto Update Check           | `refresh-cw`               |
| ⬛️             | Column Spacing (Dense Mode) | `columns-2`                |
| 🎨             | Clock Color Presets         | `swatch-book`              |
| 💾             | Settings Backup             | `hard-drive-download`      |

### Icon mapping for `index.html` — What's New changelog items

Same treatment for `.changelog-icon` spans:

| Current emoji | Changelog title        | Suggested Lucide icon name |
| ------------- | ---------------------- | -------------------------- |
| 🗂️             | Sidebar Navigation     | `panel-left`               |
| 🔤             | Any Font for the Clock | `type`                     |
| 🖥️             | Smoother Multi-Monitor | `monitor-check`            |
| 📋             | Full Changelog         | `scroll-text`              |

### SVG template to use

```html
<svg class="feature-icon" xmlns="http://www.w3.org/2000/svg" width="24" height="24"
  viewBox="0 0 24 24" fill="none" stroke="currentColor"
  stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"
  aria-hidden="true">
  <!-- paste path(s) from lucide.dev here -->
</svg>
```

### CSS changes required

The existing `.feature-icon` rule sets `font-size: 1.6rem; margin-bottom: 0.75rem; display: block;`. SVGs don't use font-size, so update the rule:

```css
/* REPLACE existing .feature-icon rule with: */
.feature-icon {
  width: 24px;
  height: 24px;
  margin-bottom: 0.75rem;
  display: block;
  color: var(--green-dim);
}
```

Same update for `.changelog-icon`:

```css
/* REPLACE existing .changelog-icon rule with: */
.changelog-icon {
  width: 24px;
  height: 24px;
  flex-shrink: 0;
  margin-top: 0.1rem;
  color: var(--green-dim);
}
```

### Also check `changelog.html`

Scan `changelog.html` for any emoji used as section markers or icons and apply the same treatment.

------

## Fix 2 — Remove / reduce glow effects on hero heading and button (HIGH PRIORITY)

### Hero title — remove text-shadow entirely

Find `.hero-title` in the `<style>` block. Remove the `text-shadow` property.

**Before:**

```css
.hero-title {
  font-size: clamp(3rem, 8vw, 5.5rem);
  font-weight: 700;
  letter-spacing: -0.02em;
  color: var(--head);
  text-shadow: 0 0 40px rgba(0, 224, 20, 0.6), 0 0 80px rgba(0, 224, 20, 0.25);
  line-height: 1.1;
}
```

**After:**

```css
.hero-title {
  font-size: clamp(3rem, 8vw, 5.5rem);
  font-weight: 700;
  letter-spacing: -0.02em;
  color: var(--head);
  line-height: 1.1;
}
```

### Download button — remove resting glow, keep hover glow but reduce it

**Before:**

```css
.btn-download {
  /* ... other properties ... */
  box-shadow: 0 0 30px rgba(0, 224, 20, 0.5);
}

.btn-download:hover {
  background: var(--head);
  box-shadow: 0 0 50px rgba(0, 224, 20, 0.7);
  transform: translateY(-2px);
}
```

**After:**

```css
.btn-download {
  /* ... other properties ... */
  /* no box-shadow at rest */
}

.btn-download:hover {
  background: var(--head);
  box-shadow: 0 0 24px rgba(0, 224, 20, 0.4);
  transform: translateY(-2px);
}
```

### App icon — reduce glow radius

Find `.app-icon`. The current shadow radiates 120px. Pull it back:

**Before:**

```css
.app-icon {
  width: 120px;
  height: 120px;
  border-radius: 26px;
  box-shadow: 0 0 60px rgba(0, 224, 20, 0.35), 0 0 120px rgba(0, 224, 20, 0.15);
}
```

**After:**

```css
.app-icon {
  width: 120px;
  height: 120px;
  border-radius: 26px;
  box-shadow: 0 0 20px rgba(0, 224, 20, 0.25);
}
```

------

## Fix 3 — Replace pill border-radius on screenshot tabs (MEDIUM PRIORITY)

The screenshot tab switcher uses `border-radius: 999px`, making them full pills. They should use the site's established `--radius` token (12px) to feel like part of the design system.

Find `.screenshot-tab` in the `<style>` block:

**Before:**

```css
.screenshot-tab {
  padding: 0.35rem 1rem;
  border-radius: 999px;
  /* ... */
}
```

**After:**

```css
.screenshot-tab {
  padding: 0.35rem 1rem;
  border-radius: var(--radius);
  /* ... */
}
```

The `.badge` pills in the hero (`border-radius: 999px`) can stay — small metadata badges read fine as pills. Only the interactive tab controls need the change.

------

## Fix 4 — Break up the features grid with a dominant screenshot (MEDIUM PRIORITY)

Currently the features section goes: section header → symmetric grid of 15 equal-weight cards. Adding a dominant screenshot above the grid breaks the template skeleton without changing the copy or card content.

### What to add

Before the `<div class="features-grid">` opening tag, insert a full-width screenshot block. Use the existing `settings-dark.png` image (already in the docs folder and already used in the gallery further up). Give it a distinct label so it reads as a deliberate showcase, not a repeat.

```html
<!-- Insert this BEFORE <div class="features-grid"> -->
<div class="screenshot-wrap" style="margin-top: 3rem; margin-bottom: 3.5rem;">
  <img class="settings-screenshot" src="settings-dark.png"
    alt="Cyph3rfall Settings panel — sidebar navigation with General, Message, Clock, Import/Export and About tabs; live rain preview on the right.">
</div>
```

The `screenshot-wrap` and `settings-screenshot` classes are already defined in the CSS, so no new styles are needed.

### Optional — reduce grid column count on large screens

15 cards in an auto-fit grid at 280px minimum gets dense. After the screenshot, a 3-column max reads more considered:

Find `.features-grid`:

```css
/* BEFORE */
.features-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 1.25rem;
  margin-top: 3.5rem;
}

/* AFTER */
.features-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  max-width: 900px;
  gap: 1.25rem;
  margin-top: 0;
}
```

------

## What NOT to change

- The color palette (`--green`, `--green-dim`, `--green-dark`, `--head`, `--bg`). These are brand-justified and cleared by the audit.
- The font stack (`-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial`). This is a deliberate platform-native choice.
- The card `border-radius: var(--radius)` (12px). Consistent and appropriate.
- The rain canvas animation in the hero. Untouched.
- The About / Story section. The copy and layout are strong.
- The install steps, requirements section, nav, or footer layout.
- The `💡` emoji in the install callout — this is prose context, not a UI icon, and is acceptable.
- `privacy.html` — no icon emoji are used there; no changes needed.

------

## Verification checklist

After making changes, confirm:

- [ ] No emoji appear in `.feature-icon` or `.changelog-icon` positions
- [ ] All SVG icons render at 24×24 and are visible in `--green-dim` color
- [ ] Hero heading has no `text-shadow`
- [ ] Download button has no `box-shadow` at rest
- [ ] App icon shadow is a single, tight shadow (no 120px spread)
- [ ] Screenshot tab buttons use `var(--radius)` not `999px`
- [ ] A screenshot appears above the features grid
- [ ] No other visual elements were changed outside this list