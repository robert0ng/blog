# Migrating off classic GitHub Pages to a GitHub Actions deploy

Status: not started. Written 2026-09-10 as a reference for a future session (human or
LLM) picking this up. Nothing in this document has been executed.

## Why this exists

This site currently deploys via **GitHub's classic Pages build**: GitHub watches the
`master` branch and, on every push, builds the site itself using the `github-pages`
gem — a fixed, whitelisted bundle of Jekyll + plugin versions that GitHub controls,
not whatever is in this repo's `Gemfile.lock`. There is no deploy step in
`.github/workflows/` (only `build-check.yml`, which verifies but does not deploy).

That constraint is the root cause of two things discovered on 2026-09-10:

1. **Toolchain pain.** The `github-pages` gem currently pins Jekyll 3.9.0, which in
   turn pins `liquid 4.0.3`. That `liquid` version calls `String#tainted?`, a method
   Ruby removed in 3.2. So this repo can only ever build on Ruby ≤3.1 — no local Ruby
   newer than that can run `jekyll build` at all, regardless of what's installed.
   `.ruby-version` pins 3.1.4 specifically because of this, not by preference.
2. **The reading-time bug (real motivating example).** Jekyll's `number_of_words`
   filter in 3.9.0 is just `input.split.length` — pure whitespace splitting. Chinese
   text has no spaces between words, so a full-length Chinese post collapses to
   "~1 min read". Modern Jekyll (4.x) fixed this properly: `number_of_words(input,
   "auto")` uses Unicode-aware regex (`\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}`) to
   count CJK characters and Latin words separately. We cannot use that fix here
   because upgrading Jekyll locally wouldn't change what GitHub's classic Pages
   build actually runs — the live site would still use old Jekyll regardless of what
   this repo's Gemfile says. (Current state: `_includes/read-time.html` was patched
   with a pure-Liquid character-counting workaround, tuned for this
   predominantly-Chinese site, with a known trade-off — it overestimates
   English/code-heavy posts. See git history for `_includes/read-time.html` around
   2026-09-10 for that workaround if it needs revisiting.)

Migrating to a GitHub Actions-based deploy removes the `github-pages` gem
constraint entirely: you control exactly which Jekyll (and Ruby) version builds the
site, because *you* build it in the Actions runner and just hand GitHub the static
HTML output to serve.

## What "classic Pages" vs "Actions-based Pages" means concretely

- **Classic (current):** repo Settings → Pages → source = "Deploy from a branch"
  (`master`). GitHub's own infrastructure clones the branch and runs
  `github-pages`-gem Jekyll on it. This repo's `Gemfile`/`Gemfile.lock` are
  irrelevant to what actually gets served — they only matter for **local**
  `bundle exec jekyll build` and for `build-check.yml`'s CI check, which is why
  those two paths can silently drift from what's live (as `Gemfile.lock` already did
  once, discovered and fixed today — see `Gemfile.lock`'s git history for the
  Bundler-4.0.11-vs-Ruby-3.1.4 incident).
- **Actions-based (target):** repo Settings → Pages → source = "GitHub Actions". A
  workflow builds the site (any Jekyll version, any Ruby version, any gem) and
  uploads `_site` as a Pages artifact; a second job deploys that artifact. What's
  live is exactly what the workflow built — no separate hidden build service.

## Migration plan

### 1. Update the Gemfile to a modern Jekyll, off the `github-pages` gem

- Replace the `github-pages` gem dependency with a directly-pinned modern `jekyll`
  (4.x) plus whichever of its currently-bundled plugins are still wanted
  (`jekyll-feed`, `jekyll-seo-tag`, `jekyll-sitemap`, `jekyll-paginate` — check
  `jekyll-paginate` specifically, it's in maintenance mode; `jekyll-paginate-v2` or
  built-in Jekyll 4 pagination may be worth considering instead).
- Bump `.ruby-version` to something current (whatever this machine already has
  working — 3.3.12 was confirmed to build cleanly during today's session).
- Run `bundle install` fresh, generating a new `Gemfile.lock` against the new
  Jekyll/Ruby. Expect other transitive gems (`kramdown`, `nokogiri`, `rouge`, etc.)
  to bump too.
- **Test locally first:** `bundle exec jekyll build --strict_front_matter`, then
  visually diff a sample of pages against the current live site. Jekyll 3→4 has
  known breaking changes worth specifically checking:
  - Sass/SCSS processing (Jekyll 4 dropped the old `sass` gem in favor of
    `jekyll-sass-converter` v2+, which requires `sassc` or `dart-sass`; check
    `_sass/`/`assets/stylesheets/` still compile).
  - `remote_theme: mmistakes/jekyll-theme-basically-basic` — confirm this theme (and
    the `_includes/cv/*.html` overrides already in this repo) still render correctly
    under Jekyll 4. The theme hasn't been checked for Jekyll-4 compatibility as of
    this writing.
  - Liquid strictness/deprecations between the old bundled `liquid` and whatever
    modern Jekyll pulls in.
- Re-verify with `script/verify.sh` (may need updating: the Ruby-version warning
  logic reads `.ruby-version` generically, should keep working; the
  `bundle _2.3.26_ install` workaround used during today's session becomes
  unnecessary once Bundler itself is current).

### 2. Fix the reading-time filter properly, now that CJK-aware `number_of_words` exists

Once on Jekyll 4.x, replace the character-counting workaround in
`_includes/read-time.html` with the real fix:

```liquid
{% assign words = page.content | strip_html | number_of_words: "auto" %}
```

(Same for the `post.content` branch.) This correctly handles both the mostly-Chinese
posts and English/code-heavy posts like `rsync-to-android` without the trade-off
documented in this repo's `_includes/read-time.html` comment block.

### 3. Add the Actions deploy workflow

Something along these lines (verify current recommended syntax against GitHub's own
docs at migration time — this API has evolved):

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [master]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      - run: script/verify.sh
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: ./_site

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

This can likely replace `build-check.yml` entirely (build-check-then-deploy becomes
one workflow), or stay as a separate deploy workflow if you want PR builds to keep
running without deploying. Decide at migration time.

### 4. Flip the Pages source setting (manual, one-time, in GitHub's UI)

Repo Settings → Pages → Build and deployment → Source → change from "Deploy from a
branch" to "GitHub Actions". This is a web UI action, not something scriptable via
git — whoever does this migration needs actual repo admin access in the browser.

**Ordering matters:** land the new workflow file and confirm it runs successfully on
a push (it'll be inert / not deploy anything meaningful until the source is flipped,
or it may fail outright depending on how GitHub gates unused Pages-Actions
permissions — check this in a low-stakes moment) before flipping the source, so
there's a working artifact ready the moment classic Pages stops being the source of
truth.

### 5. Verify and roll back if needed

- After flipping the source, confirm `https://robertnotes.com` (the custom domain,
  per `CNAME`) still resolves and renders correctly — DNS/CNAME handling differs
  slightly between the two Pages source types in some edge cases, worth a direct
  check rather than assuming.
- Rollback is just flipping the Settings → Pages source back to "Deploy from a
  branch" — classic Pages will resume building from `master` on the next push. No
  data loss risk; this is a build-pipeline change, not a content change.

## Open questions for whoever picks this up

- Confirm current `mmistakes/jekyll-theme-basically-basic` compatibility with Jekyll
  4.x before starting — if the theme is unmaintained/stuck on Jekyll 3 conventions,
  this could turn into a bigger theme-migration project than a simple version bump.
- Decide whether to keep `jekyll-paginate` or move to `jekyll-paginate-v2` /
  Jekyll 4's built-in pagination.
- Decide whether `build-check.yml` and the new deploy workflow should merge into one
  file or stay separate (separate is simpler to reason about for PR-only builds that
  shouldn't deploy).
