# Changelog

## 4.0.0 — 2026-08-23

- Rebuilt on Omarchy 4's service plus bar-widget architecture. The resident
  service owns the creature, conversation, IPC, and state; every bar
  renders a lightweight control onto that one source of truth.
- Replaced the status-file-driven menu with a native overview and settings
  panel that talks to the service directly, stays open while choices change,
  and supports keyboard navigation.
- Made agent turns explicit and at-most-once: no silent retry, no replacement
  of a running order, a real Stop action, and no stale timeout or cleanup that
  can terminate a later turn.
- Fixed clean installs so bundled Gritty is discovered without a pet copied
  into the user's config. Legacy settings and duplicate shell entries migrate
  into one canonical bar entry.
- Removed the Claude hook installer and its edits to external settings.
  Existing OmaPets-compatible state remains an optional, passive input.
- Restored the approved Quattro artwork with complete upstream Omarchy MIT
  attribution, made the car face inward on either side of a screen, and
  restored the deliberately stark head-on Gritty portrait. Python caches and
  other local build artefacts are excluded from releases and checked in CI.
- Added an isolated HOME/XDG cold-start gate, service/widget contract tests,
  strict pet schema checks, pinned CI actions, and least-privilege workflow
  permissions.

## 3.38.0 — 2026-08-23

- Last release of the original panel plus status-file bar architecture.
- Added multi-monitor placement, bubble conversations, Quake-console
  escalation, persistent state, theme-aware pets, idle expressions, and
  agent/rate-limit mood states across the 2.x–3.x series.
- Added inline `shell.json` settings and discovery of Omarchy's configured
  agents and compatible pet folders.

Version 4 migrates supported 3.x settings automatically. The Git history
retains the detailed development log for the earlier experimental releases.
