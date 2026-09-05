# Zotero Search for Omarchy

A standalone Omarchy top-bar widget for searching a local Zotero library and copying a Better BibTeX citekey in Typst or LaTeX format.

## Requirements

- Zotero installed with its local API enabled.
- `wl-copy` available for clipboard writes.
- Better BibTeX enabled in Zotero when copying citekeys.

The plugin only contacts Zotero on loopback (`127.0.0.1:23119`):

- Better BibTeX library export: `/better-bibtex/export?library.json`
- Zotero fallback search: `/api/users/0/items?...`

It does not use Zotero accounts, API keys, credentials, or external services. On each refresh the plugin first requests the Better BibTeX export, then probes and searches Zotero's ordinary local API if that export is unavailable. If Zotero is running without Better BibTeX, the panel says `Searching Zotero library` and does not show a startup warning. Citekey output still requires Better BibTeX.

The Start Zotero button is shown only when the local Zotero API probe fails. It launches the fixed local `/usr/bin/zotero` application command and keeps the panel responsive while retrying the API. No command or launch path is taken from user input.

## Install manually

```bash
omarchy plugin add <public-plugin-repository-url> --enable --yes
```

To place it in the bar, add an entry to the relevant layout in `~/.config/omarchy/shell.json`:

```json
{
  "id": "marijn.zotero"
}
```

The in-panel Copy format dropdown persists to `~/.config/omarchy/zotero-search.json` using this schema:

```json
{
  "schemaVersion": 1,
  "copyFormat": "typst"
}
```

The file is written asynchronously with atomic replacement. Missing, malformed, or unsupported files safely use Typst. The old inline `copyFormat` shell entry remains a migration fallback: `citekey` and the retired `citation` value both map to Typst, while `typst` and `latex` map directly. A valid dedicated file takes precedence. After editing the bar layout, rescan the shell:

```bash
omarchy-shell shell rescanPlugins
```

Left click opens the search panel. Click a result or press Enter to copy the selected output. Right click refreshes the local library snapshot.

## Copy formats

Use the in-panel dropdown to choose:

- `typst`: copies `@citekey`.
- `latex`: copies the literal `\cite{citekey}`.

Both formats require a citation key from Better BibTeX. The previous human-readable `citation` mode is retired; its legacy setting maps to the safe Typst default rather than silently producing a different format.

## Shortcuts

- `Ctrl + Super + Z`: toggle the search panel.
- `Ctrl + N`: select the next result, wrapping at the end.
- `Ctrl + P`: select the previous result, wrapping at the beginning.
- `Enter`: copy the selected output using the chosen format.
- `Escape`: close the panel.

## Official Omarchy distribution checklist

No remote repository or publication has been performed. The installed Omarchy release provides git-based plugin installation and manifest validation, but no local command for registering a plugin in an official catalog. Before public marketplace distribution:

1. Publish a public git repository and replace `<public-plugin-repository-url>` in the install example.
2. Tag the reviewed commit as `1.0.0` and confirm `omarchy plugin validate .` passes from that tag.
3. Submit the plugin id `marijn.zotero`, repository URL, version, license, README, and maintainer profile or contact to the current official Omarchy plugin catalog maintainers.
4. After acceptance, verify installation from the public URL with `omarchy plugin add <url> --enable --yes`; do not rely on local checkout paths.
