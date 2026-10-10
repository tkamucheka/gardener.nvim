# gardener.nvim

Tree-sitter parser management for Neovim, on the `main` branch of
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).
gardener installs parsers, including on demand when a file of a new
filetype is opened; registers custom parsers and keeps them registered across
nvim-treesitter updates; and starts highlighting, folds, and indentation in
every buffer whose parser is installed.

## Requirements

* Neovim 0.12 or later
* nvim-treesitter, `main` branch, with its requirements (`curl`, `tar`, the
  tree-sitter CLI, and a C compiler)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "tkamucheka/gardener.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  lazy = false,
  opts = {
    ensure_installed = { "lua", "vim", "vimdoc", "query" },
  },
}
```

With another plugin manager, install both plugins and call
`require("gardener").setup(opts)`.

## Configuration

| Option | Default | Meaning |
|--------|---------|---------|
| `ensure_installed` | `{}` | Parsers installed at startup: a list of languages, or a map from language to the filetypes that use it, such as `{ qmljs = { "qml" } }`. |
| `custom_parsers` | `{}` | Parsers that nvim-treesitter does not provide, by language (below). |
| `auto_install` | `true` | Install the parser of a filetype when a file of that type is opened. |
| `never_install` | `{}` | Languages that are never installed. |
| `ignore_filetypes` | `{}` | Filetypes that gardener leaves alone. |
| `manage_folds` | `false` | Set tree-sitter folding (`foldmethod=expr`) in managed buffers. |
| `manage_indent` | `false` | Set nvim-treesitter's `indentexpr` in managed buffers. |
| `silent` | `false` | Suppress gardener's notifications. |

### Custom parsers

A custom parser takes the `install_info` of nvim-treesitter (`url` or `path`,
and optionally `revision`, `branch`, `location`, `generate`, and `queries`)
and the filetypes it serves:

```lua
opts = {
  custom_parsers = {
    dottr = {
      install_info = {
        url = "https://github.com/tkamucheka/tree-sitter-dottr",
        queries = "queries",
      },
      filetypes = { "dottr" },
    },
  },
}
```

With `path`, gardener uses a local checkout and warns if its queries
directory has no `highlights.scm`.
