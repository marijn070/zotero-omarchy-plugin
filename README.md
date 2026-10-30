# Zotero Search for Omarchy

A top-bar widget for [Omarchy](https://omarchy.org/) that searches your local Zotero library and copies a Better BibTeX citekey to the clipboard, as Typst (`@citekey`) or LaTeX (`\cite{citekey}`).

- Click the bar icon to open the search panel, or bind a key to it (see Open with a key).
- Pinned papers are listed first and recently copied papers below them. Start typing and both are replaced by search results; clear the search to bring them back.
- Click a paper or press `Enter` to copy its citekey.

## Requirements

- Omarchy with shell plugin support (developed on Omarchy 4.5, Quickshell based).
- Zotero installed at `/usr/bin/zotero`, with its local API enabled (Zotero settings, Advanced: allow other applications on this computer to communicate with Zotero).
- [Better BibTeX](https://retorque.re/zotero-better-bibtex/) in Zotero to get citekeys. Without it you can still find papers, but copying a citekey is not possible.
- `wl-copy` (package `wl-clipboard`) for clipboard writes.
- `curl`, which Omarchy already ships.

## Install

```bash
omarchy plugin add https://github.com/marijn070/zotero-omarchy-plugin --enable --yes
```

Pick the bar section when asked, or add the widget yourself in `~/.config/omarchy/shell.json`:

```json
{
  "id": "marijn.zotero"
}
```

The shell hot-reloads `shell.json`. If the widget does not appear, run `omarchy-shell shell rescanPlugins`.

To update later: `omarchy plugin update marijn.zotero --yes`.

## Remove

```bash
omarchy plugin remove marijn.zotero --yes
```

Remove the `marijn.zotero` entry from `~/.config/omarchy/shell.json` if it is still there. Optionally delete the settings file `~/.config/omarchy/zotero-search.json` (see Local data below).

## Usage

- Left click the bar icon: open or close the panel. Right click: refresh the library snapshot.
- Type to search titles, authors and citekeys. Results replace the pinned and recent lists until the search box is empty again.
- Each row has a pin button that pins or unpins the paper. Pinned papers stay at the top, newest pin first.
- Recent papers are the last 10 papers whose citekey you copied with this plugin, newest first. A pinned paper is not repeated under Recent.
- A pinned paper that is no longer in your Zotero library stays listed as "No longer in your Zotero library" so you can unpin it; a missing recent paper is hidden.
- Pinned and recent papers are listed even while Zotero is closed, and copying works from the saved citekey. A Start Zotero button appears when the local API cannot be reached.
- Use the Copy format dropdown to choose Typst or LaTeX output.

### Shortcuts in the panel

| Key | Action |
| --- | --- |
| `Escape` | Close the panel (closes an open dropdown first) |
| `Enter` | Copy the selected paper |
| `Up` / `Down` | Move the selection |
| `Ctrl + N` / `Ctrl + P` | Next / previous paper, wrapping around |
| `Ctrl + B` | Pin or unpin the selected paper |

## Open with a key

The plugin does not install a global key binding. To open the panel from the keyboard, bind a key to the shell's toggle command in `~/.config/hypr/bindings.lua`, for example:

```lua
o.bind("SUPER + CTRL + Z", "Zotero search", "omarchy-shell shell toggle marijn.zotero")
```

## Copy formats

- `typst`: copies `@citekey`.
- `latex`: copies `\cite{citekey}`.

Both need the Better BibTeX citation key. The retired `citation` setting maps to Typst.

## Local data and privacy

The plugin only talks to Zotero on loopback (`127.0.0.1:23119`): the Better BibTeX library export (`/better-bibtex/export?library.json`), with Zotero's ordinary local API (`/api/users/0/items`) as fallback. It uses no accounts, API keys or external services, and nothing leaves your machine.

Your copy format, pins and recents are saved in `~/.config/omarchy/zotero-search.json`:

```json
{
  "schemaVersion": 1,
  "copyFormat": "typst",
  "pinned": [
    {
      "zoteroKey": "ABCD2345",
      "citationKey": "smithRobots2024",
      "title": "Robots and RDF",
      "authors": "Smith, Ada",
      "year": "2024",
      "container": "Journal of RDF"
    }
  ],
  "recent": []
}
```

Entries are matched to your library by Zotero item key or citation key. The file is written asynchronously with atomic replacement, holds at most 50 pins and 10 recents, and a missing or unreadable file safely falls back to Typst with no pins. The old inline `copyFormat` entry in `shell.json` is still read as a fallback when no settings file exists.

The only command the plugin starts is the fixed `/usr/bin/zotero` (Start Zotero button), plus `wl-copy` for the clipboard and `curl` for the loopback requests. No command text comes from search input or library data. Zotero-provided text is always rendered as plain text.

## Development

```bash
omarchy plugin validate .
node --test tests/model.test.cjs
tests/qml/run.sh
```

`tests/qml/run.sh` needs the Qt 6 `qmltestrunner` (package `qt6-declarative`). It runs the real `Panel.qml` offscreen against test doubles of the shell types in `tests/qml/stubs`, so it needs neither the Omarchy shell nor Zotero.

## License

[MIT](LICENSE). Copyright (c) 2026 Marijn.
