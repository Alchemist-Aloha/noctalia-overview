# Noctalia Overview

A Noctalia v5 Luau port of Hypr Overview. The `workspaces` bar widget is a single icon in the bar: click it to open the interactive overview. The `toggle` control-center shortcut opens the same overview.

Each workspace card shows a live thumbnail for every window, arranged to mirror the workspace's real tiling (side-by-side, stacked, master/stack, and so on) using each window's Hyprland geometry; floating windows are left out of the layout and overlapping windows fall back to a compact grid. The overview supports window-to-workspace drag and drop, keyboard workspace navigation, and workspace/window focus.

## Install and use

Install and update through Noctalia's plugin sources. In a running Noctalia session, open **Settings → Plugins → Sources**, click **Add Source**, and enter:

```
https://github.com/Alchemist-Aloha/noctalia-overview
```

After updating the repository, Browse the plugin catalog and install `Noctalia Overview`. Add `alchemistaloha/noctalia-overview:workspaces` to a bar in Noctalia's widget picker. For an on-screen preview, click the plugin's `workspaces` widget in the bar.

Open the overview from a keybind or terminal with:

```sh
noctalia msg panel-toggle alchemistaloha/noctalia-overview:overview
```

## Settings and controls

Settings → Plugins → Noctalia Overview exposes empty and special workspaces, capture interval, and a capture-count limit. The overview has previous/next chevrons that scroll the previews, drag-to-move windows, and a focus/floating action for a selected window. Arrow keys or H/J/K/L select a workspace, Up/Down or K/J scroll the previews; Enter opens it; number keys 1–0 jump to slots 1–10. Escape closes the panel.

This v5 native panel cannot reproduce the v4 QML overlay's exact window geometry, shader effects, per-monitor full-screen surfaces, and retile visualization. The port keeps live window content and the core navigation/move behavior within the v5 declarative UI.

## Requirements

- Noctalia v5 with plugin API 24 or newer
- Hyprland and `hyprctl`
- `grim` with the `-T` foreign-toplevel capture option

## License

MIT — see [LICENSE](LICENSE).
