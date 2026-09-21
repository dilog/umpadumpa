# 05: App version in sidebar and About

**What to build:** Show the marketing version in small text by the UmpaDumpa name in the sidebar (e.g. `1.0.0`). Add macOS About (UmpaDumpa → About UmpaDumpa) with name, marketing version, and build when the bundle provides it. Parent spec: `.scratch/trial-ux-fixes/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Sidebar: marketing version only, small, by the product name
- [x] About menu item with name + version (+ build if available)
- [x] Values from the app bundle, not hard-coded strings in the view

## Comments

## Answer

Sidebar shows the marketing version (`CFBundleShortVersionString`) in small text beside the product name from the app bundle. UmpaDumpa → About UmpaDumpa opens the standard macOS About panel with name, marketing version, and build (`CFBundleVersion`) from the same Info dictionary. `AppVersion` is the seam; unit tests cover dictionary → label mapping.