set nocompatible
filetype indent plugin on
syntax on

set hidden
set wildmenu
set showcmd
set hlsearch
set ignorecase
set smartcase
set backspace=indent,eol,start
set autoindent
set nostartofline
set ruler
set laststatus=2
set confirm
set visualbell
set t_vb=
set mouse=a
set cmdheight=2
set number
set notimeout ttimeout ttimeoutlen=200
set grepprg=grep\ -nH\ $*

let g:tex_flavor='latex'
set shiftwidth=2
set softtabstop=2
set expandtab

map Y y$

packadd! dracula
syntax enable
colorscheme dracula
