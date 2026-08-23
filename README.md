# AuraBind v2.0

An overlay for creating, editing, and deleting Omarchy keybindings on the fly with live key capture.

**Now shows ALL default Omarchy keybindings** — not just your custom overrides. Browse, search, and filter every binding loaded from your Hyprland configuration.

## Features

- **Full binding browser** — scans Lua config files and shows all ~200+ default Omarchy keybindings alongside your custom overrides
- **Category filter** — group bindings by Applications, Window Management, Media & Audio, Workspaces, System & Menus, and more
- **Search & filter** — search across key combinations, descriptions, and commands
- **Live key capture** — press any key combination to record it
- **6 action types** — Open App, Custom Command, Workspace, Plugin/Shell, Dispatcher/Lua, Web App, or Unbind (disable a default)
- **App picker** — browse installed applications from your system and pick the correct exec command
- **Conflict detection** — warns when a key combo is already used by another custom binding
- **Edit or override defaults** — click any default binding to override it with a custom one
- **Visual distinction** — custom bindings are highlighted with accent color, disabled bindings shown with red border
- **Category badges** — each binding shows its category at a glance
- **Vim-style navigation** — `j`/`k` to move, `Enter` to edit, `Delete`/`Backspace` to disable
- **Instant apply** — saves to `~/.config/hypr/bindings.lua` and runs `hyprctl reload` automatically
- **Error checking** — runs `hyprctl configerrors` after every reload
- **Launcher registration** — accessible from SUPER+SPACE (Omarchy menu)

## Installation

```bash
omarchy plugin clone pikaga.aurabind
```

That's it. Cloning switches the bar to your local copy and the panel becomes available.

### Manual install

If `omarchy plugin clone` isn't an option, clone the repo directly:

```bash
git clone https://github.com/ThatPikaga/AuraBind.git ~/.config/omarchy/plugins/pikaga.aurabind
```

Then force the shell to pick it up:

```bash
omarchy-shell shell rescanPlugins
```

## Usage

Open AuraBind from the Omarchy menu (SUPER+SPACE) by searching "AuraBind", or toggle it from a terminal:

```bash
omarchy-shell shell toggle pikaga.aurabind
```

Or directly from the default keybinding: **SUPER + K** (configurable in Omarchy settings).

### Browsing bindings

When AuraBind opens, it scans all your default Omarchy bindings and any custom overrides. You'll see:

- **Key combination** in accent color (left column)
- **Category badge** (e.g. "Applications", "Window Management")
- **Description** of what the binding does
- **Command** that the binding executes
- **Custom badge** on bindings you've overridden

Use the **search bar** to filter by any text, or use the **category dropdown** to show only bindings in a specific category.

### Adding a binding

1. Click **+ Add Binding** (or navigate to an empty spot and press Enter)
2. Click **Click to capture** and press your desired key combination
3. Enter a description
4. Choose an action type:
   - **Open App** — pick from installed apps with the **Browse Apps** button
   - **Custom Command** — type any shell command
   - **Workspace** — e.g. `1`, `2`
   - **Plugin / Shell** — e.g. `omarchy.shell toggle`
   - **Dispatcher / Lua** — Hyprland dispatcher or Lua expression
   - **Web App** — URL for a web app
   - **Unbind** — disable a default binding
5. Click **Save**

### Editing

Tap **Edit** on any row, or highlight it and press Enter. The dialog pre-fills with the binding's current values.

### Disabling default bindings

Tap **Unbind** on any default binding, or highlight it and press Delete/Backspace. This adds an `hl.unbind()` call to your config.

### Removing custom bindings

Tap **Del** on a custom binding to remove it.

## Compatibility

Omarchy only. Requires `hyprctl` and `lua` on your PATH.