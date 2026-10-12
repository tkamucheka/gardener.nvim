# gardener.nvim

Tree-sitter parser management for Neovim, built on the `main` branch of
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter), which
installs parsers but leaves starting them to the user.

* Installs a list of parsers at startup, and the parser of any other
  filetype when a file of that type is first opened.
* Registers parsers that nvim-treesitter does not provide, and keeps them
  registered across nvim-treesitter updates.
* Detects the filetype of files that Neovim does not recognize, by
  extension or file name, for custom parsers.
* Maps filetypes to the languages that parse them.
* Starts highlighting, and optionally folds and indentation, in every buffer
  whose parser is installed, including a buffer whose parser was just
  installed.

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
and, optionally:

| Field | Meaning |
|-------|---------|
| `filetypes` | Filetypes that use the parser. Default: the filetype named after the language. |
| `extensions` | File extensions, such as `"dotfile"`, detected as the first of `filetypes`. |
| `filenames` | File names, such as `"Dotfile"`, detected as the first of `filetypes`. |

```lua
opts = {
  custom_parsers = {
    dottr = {
      install_info = {
        url = "https://github.com/tkamucheka/tree-sitter-dottr",
        queries = "queries",
      },
      filetypes = { "dottr" },
      extensions = { "dotfile" },
    },
  },
}
```

Files ending in `.dotfile` are then detected as the filetype `dottr`, and
gardener installs and starts the `dottr` parser in them.

With `path`, gardener uses a local checkout and warns if its queries
directory has no `highlights.scm`.

## License

MIT; see [LICENSE](LICENSE).
