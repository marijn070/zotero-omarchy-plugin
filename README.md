# Zotero Search for Omarchy

A standalone Omarchy top-bar widget for searching a local Zotero library and copying either a Better BibTeX citekey or a readable citation.

## Requirements

- Zotero running locally with its local API enabled.
- `wl-copy` available for clipboard writes.
- Better BibTeX enabled in Zotero when copying citekeys.

The plugin only contacts Zotero on loopback (`127.0.0.1:23119`):

- Better BibTeX library export: `/better-bibtex/export?library.json`
- Zotero fallback search: `/api/users/0/items?...`

It does not use Zotero accounts, API keys, credentials, or external services. The fallback can search local titles and metadata without Better BibTeX; citekey output still requires Better BibTeX.

## Install manually

```bash
omarchy plugin add <public-plugin-repository-url> --enable --yes
```

To place it in the bar, add an entry to the relevant layout in `~/.config/omarchy/shell.json`:

```json
{
  "id": "marijn.zotero",
  "copyFormat": "citekey"
}
```

Settings are inline properties on the widget entry, not a separate settings file. `copyFormat` accepts `citekey` (the default) or `citation`. After editing the layout, rescan the shell:

```bash
omarchy-shell shell rescanPlugins
```

Left click opens the search panel. Click a result or press Enter to copy the selected output. Right click refreshes the local library snapshot.

## Copy formats

- `citekey`: copies `@citekey`, preserving the original Typst-oriented behavior.
- `citation`: copies a deterministic citation assembled from local fields as `Author; Author (Year). Title. Container.` Missing fields are omitted; items without an author use `Title (Year). Container.`

Citation output works with Zotero fallback results. Citekey output requires a citation key from Better BibTeX.

## Shortcuts

- `Ctrl + Super + Z`: toggle the search panel.
- `Ctrl + N`: select the next result, wrapping at the end.
- `Ctrl + P`: select the previous result, wrapping at the beginning.
- `Enter`: copy the selected output using `copyFormat`.
- `Escape`: close the panel.

## Marketplace readiness

No remote repository or publication has been performed. This checkout's origin is local-only, so public marketplace distribution still needs:

- the public repository URL to replace `<public-plugin-repository-url>`;
- a stable `1.0.0` release tag or commit; and
- the maintainer profile or contact details required by the marketplace listing.
