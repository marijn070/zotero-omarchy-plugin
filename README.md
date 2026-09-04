# Zotero Search for Omarchy

A small Omarchy top-bar widget for searching the local Zotero library and copying Better BibTeX citation keys.

## Requirements

- Zotero running locally with its local API enabled.
- Better BibTeX enabled in Zotero for citation keys.
- `wl-copy` available for clipboard writes.

The plugin uses Zotero's local-only HTTP server at `127.0.0.1:23119`:

- Better BibTeX: `/better-bibtex/export?library.json`
- Zotero fallback search: `/api/users/0/items?...`

No Zotero account login, API key, or external authentication is needed. The fallback can search titles without citation keys, but copying keys requires Better BibTeX.

## Install manually

```bash
omarchy plugin add <plugin-repository-url> --enable --yes
```

For this local copy, add `marijn.zotero` to a bar layout in `~/.config/omarchy/shell.json`, then run:

```bash
omarchy-shell shell rescanPlugins
```

Left click searches. Click a result or its copy icon to copy the citation as `@citekey`, ready to paste into Typst. Right click refreshes the local library snapshot.

## Shortcuts

- `Ctrl + Super + Z`: toggle the search panel.
- `Ctrl + N`: select the next result, wrapping at the end.
- `Ctrl + P`: select the previous result, wrapping at the beginning.
- `Enter`: copy the selected citation key.
- `Escape`: close the panel.
