# Noctalia Overview

A Noctalia v5 Luau port of Hypr Overview. The `workspaces` bar widget is a single icon in the bar: hover it for a live window-thumbnail preview, or click it to open the interactive overview. The `toggle` control-center shortcut opens the same overview.

Each workspace card shows a live thumbnail for every window, arranged to mirror the workspace's real tiling (side-by-side, stacked, master/stack, and so on) using each window's Hyprland geometry; floating or overlapping windows fall back to a compact grid. Cards are sized to the number of workspaces actually shown, so a monitor with two or three workspaces gets large thumbnails that fill the row instead of a sparse fixed-column grid. Window titles appear as tooltips rather than caption strips. The hover preview and the click overview use the same card scale and height buckets, so both open at the same size for a given monitor; each picks the smallest height variant that fits, then grows the card thumbnails to fill the panel so the previews use the whole window instead of leaving dead space at the bottom. This requires Hyprland's foreign-toplevel capture support and a `grim` build with `-T` (`grim -h` lists it). If a window cannot be captured, its application icon or name remains visible. The preview is read-only apart from clicking a workspace or window; the overview supports window-to-workspace drag and drop, keyboard workspace navigation, and workspace/window focus.

## Install and use

This directory is a complete standalone Noctalia v5 plugin. From inside this directory, copy it to Noctalia's local plugin directory, then enable it in a running Noctalia session:

```sh
plugin_dest="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/noctalia-overview"
mkdir -p "$plugin_dest"
cp -a plugin.toml *.luau lib translations README.md "$plugin_dest/"
noctalia msg config-reload
noctalia msg plugins enable alchemistaloha/noctalia-overview
```

If you use Noctalia's `NOCTALIA_DATA_HOME` override, install under its `plugins/noctalia-overview/` directory instead. Repeat the copy and config reload after updating the plugin files. Source repositories need a `catalog.toml`; this local drop-in does not.

Add `alchemistaloha/noctalia-overview:workspaces` to a bar in Noctalia's widget picker. Add `alchemistaloha/noctalia-overview:toggle` to Control Center if desired.

Open the overview from a keybind or terminal with:

```sh
noctalia msg panel-toggle alchemistaloha/noctalia-overview:overview
```

The panels come in height variants: `overview` (475), `overview-375`, `overview-320`, `overview-265`, `overview-220`, plus the matching `preview-*` ids. The bar widget and the `toggle` shortcut read the monitor's workspaces and open the smallest variant that fits, so the window is sized to the previews and the hover and click panels match.

For an on-screen hover preview, move the pointer over the plugin's `workspaces` widget in the bar. The built-in Noctalia `workspaces` widget cannot be extended by a plugin, so replace it with this widget if you want previews on workspace hover.

## Settings and controls

Settings → Plugins → Noctalia Overview exposes rows, columns, empty and special workspaces, hover preview, capture interval, and a capture-count limit. The overview has previous/next page controls, drag-to-move windows, and a focus/floating action for a selected window. Arrow keys or H/J/K/L select a workspace; Enter opens it; number keys 1–0 jump to slots 1–10. Escape closes the panel.

This v5 native panel cannot reproduce the v4 QML overlay's exact window geometry, shader effects, per-monitor full-screen surfaces, and retile visualization. The port keeps live window content and the core navigation/move behavior within the v5 declarative UI.

## Requirements

- Noctalia v5 with plugin API 24 or newer
- Hyprland and `hyprctl`
- `grim` with the `-T` foreign-toplevel capture option

The original v4 `hypr-overview` is a separate legacy plugin and is not needed to run this one.
