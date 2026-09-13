# Noctalia Overview

A Noctalia v5 Luau port of Hypr Overview. The `workspaces` bar widget is a single icon in the bar: click it to open the interactive overview. The `toggle` control-center shortcut opens the same overview.

Each workspace card shows a live thumbnail for every window, arranged to mirror the workspace's real tiling (side-by-side, stacked, master/stack, and so on) using each window's Hyprland geometry; floating windows are left out of the layout and overlapping windows fall back to a compact grid. Every preview keeps the same fixed 16:9 aspect ratio and stays on a single row: the panel always shows three previews, and the two chevron buttons scroll that window through the monitor's workspaces, so there are no pages to keep track of and nothing wraps into extra rows. Empty workspaces keep the same preview height. Window titles appear as tooltips rather than caption strips. The window size is a plain `width`/`height` pair on the `overview` panel in `plugin.toml`, and the previews scale to whatever you set. This requires Hyprland's foreign-toplevel capture support and a `grim` build with `-T` (`grim -h` lists it). If a window cannot be captured, its application icon or name remains visible. The overview supports window-to-workspace drag and drop, keyboard workspace navigation, and workspace/window focus.

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

Set the window size directly with the `width` and `height` on the `overview` `[[panel]]` block in `plugin.toml`; the thumbnails adapt automatically.

For an on-screen preview, click the plugin's `workspaces` widget in the bar. The built-in Noctalia `workspaces` widget cannot be extended by a plugin, so replace it with this widget if you want thumbnails.

## Settings and controls

Settings → Plugins → Noctalia Overview exposes empty and special workspaces, capture interval, and a capture-count limit. The overview has previous/next chevrons that scroll the previews, drag-to-move windows, and a focus/floating action for a selected window. Arrow keys or H/J/K/L select a workspace, Up/Down or K/J scroll the previews; Enter opens it; number keys 1–0 jump to slots 1–10. Escape closes the panel.

This v5 native panel cannot reproduce the v4 QML overlay's exact window geometry, shader effects, per-monitor full-screen surfaces, and retile visualization. The port keeps live window content and the core navigation/move behavior within the v5 declarative UI.

## Requirements

- Noctalia v5 with plugin API 24 or newer
- Hyprland and `hyprctl`
- `grim` with the `-T` foreign-toplevel capture option

The original v4 `hypr-overview` is a separate legacy plugin and is not needed to run this one.
