# AuraBind

![Cover Art](preview.png)

An application for managing Hyprland keybindings on the fly with a robust searchable key selector.

Supports full key combinations (SUPER, CTRL, ALT, SHIFT + any key), a searchable binding list, and write-through to your `~/.config/hypr/bindings.lua` file using a managed fence block that coexists with hand-edited content.

## Features

- **Searchable key selector** — easily find and bind any standard, media, or mouse key via a searchable dropdown, completely avoiding Wayland global key interception issues.
- **Smart action types** — Execute Commands, Kill Active Window, run Lua/Dispatchers, open Web Apps, or Unbind (disable a default binding).
- **Search & filter** your bindings by category or text.
- **Conflict detection** — warns you before overriding an existing custom keybinding.
- **Disabled bindings manager** — easily view and re-enable default bindings you've previously disabled.
- **Vim-style navigation** — `j`/`k` to move, `Enter` to edit, `Delete` to remove, `Esc` to close.
- **Instant apply** — saves to `bindings.lua` and runs `hyprctl reload` automatically.
- **Error checking** — runs `hyprctl configerrors` after every reload to catch syntax mistakes.
- **Launcher registration** — accessible from `SUPER+SPACE` (Omarchy menu) and other desktop launchers.

---

## Installation

### Omarchy

```bash
omarchy plugin clone thatpikaga.aurabind
```
That's it. Cloning switches the bar to your local copy and the panel becomes available.

**Manual install**
If omarchy plugin clone isn't an option, clone the repo directly:

```bash
git clone https://github.com/ThatPikaga/AuraBind.git ~/.config/omarchy/plugins/thatpikaga.aurabind
```
Then force the shell to pick it up:

```bash
omarchy-shell shell rescanPlugins
```

### General Install
If you are not using Omarchy, simply clone the repository directly into your home directory:

```bash
git clone https://github.com/ThatPikaga/AuraBind.git ~/AuraBind
```

---

## Usage
### Omarchy
Open AuraBind from the Omarchy menu (SUPER+SPACE) by searching "AuraBind", or toggle it from a terminal:

```bash
omarchy-shell shell toggle thatpikaga.aurabind
```
### General Usage
If you installed AuraBind to your home directory, navigate to the folder and launch the interface directly using Quickshell:

```bash
cd ~/AuraBind
quickshell
```
>Note: General usage requires a Wayland compositor with wlr-layer-shell support and Quickshell installed on your system.

---

### Adding a binding
Click + Add Binding at the bottom of the window.

- Toggle your desired Modifiers (SUPER, ALT, CTRL, SHIFT) and set the number of keys in the combo.

- Click the searchable dropdown and type to find your key (e.g., type "XF86" for media keys, or "SPACE").

- Enter a description and choose an Action type (Command, Kill Win, Lua/Dsp, Web App, or Unbind).

- Fill in the Action details (e.g., the terminal command or URL).

- Click Save.

### Editing
Tap the Edit (✎) button on any row, or highlight it and press Enter.

### Removing / Disabling
Tap the Disable (⊘) or Delete (✕) button, or highlight a row and press Delete/Backspace. Disabled default bindings can be restored later via the "⚠ Disabled" menu at the bottom right.

---

## Compatibility

Built for Hyprland. Requires `hyprctl` on your PATH.

## Previews

![Default Screen — main binding list](screenshots/preview.png)

*Default screen showing the searchable binding list and action toolbar.*

![Add New Binding Screen](screenshots/preview2.png)

*The Add/Edit binding panel with key assigning, description field, and action type selector.*

![Disabled Keybindings](screenshots/preview3.png)

*View showing disabled keybindings in the list.*
