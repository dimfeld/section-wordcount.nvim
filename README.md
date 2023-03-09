# section-wordcount

This is a plugin for counting words in each section of a markdown or asciidoc file. It
is aware of header levels so, for example, the word count for a level 2 header will include
the words in all the level 3 and higher sections inside it.


## Installation

Use any package manager.

For VimPlug:

```
Plug 'dimfeld/section-wordcount.nvim'
```

## Usage

First the global setup function should be called to enable the plugin.

```lua
require('section-wordcount').setup{
    -- These are the default values and can be omitted
    highlight = "String",
    virt_text_pos = "eol",
}
```


For each file type that you want to enable, the `wordcounter` function can be called on the buffer
to enable it. The `header_char` option defaults to `'#'` for Markdown but can be customized for
other file formats:

```vim
augroup SectionWordcount
  au!
  au FileType markdown lua require('section-wordcount').wordcounter{}
  au FileType asciidoc lua require('section-wordcount').wordcounter{
  \   header_char = '=',
  \ }
augroup END
```
