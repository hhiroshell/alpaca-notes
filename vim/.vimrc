"---------------------------------------------------------------------------
" プラグイン（プラグインに依存する設定が.vimrcに書かれる場合もあるため、冒頭に
" 記述する）:
"
call plug#begin()
" iceberg: https://cocopon.github.io/iceberg.vim/
Plug 'cocopon/iceberg.vim'
call plug#end()

"---------------------------------------------------------------------------
" 日本語対応のための設定
"
" MacOS Xメニューの日本語化 (メニュー表示前に行なう必要がある)
if has('mac')
  set langmenu=japanese
endif

" 非GUI日本語コンソールを使っている場合の設定
if !has('gui_running') && &encoding != 'cp932' && &term == 'win32'
  set termencoding=cp932
endif

"---------------------------------------------------------------------------
" 検索の挙動に関する設定:
"
" 検索時に大文字小文字を無視 (noignorecase:無視しない)
set ignorecase
" 大文字小文字の両方が含まれている場合は大文字小文字を区別
set smartcase

"---------------------------------------------------------------------------
" 編集に関する設定:
"
" タブの画面上での幅
set tabstop=4
" タブをスペースに展開する (noexpandtab:展開しない)
set expandtab
" 自動的にインデントする (noautoindent:インデントしない)
set autoindent
" シフトオペレータ(>>)やautoindentで挿入される量
set shiftwidth=4
" タブキーを押下した時にスペース何個分カーソルが進むか（0:tabstopと同じ値）
set softtabstop=0
" バックスペースでインデントや改行を削除できるようにする
set backspace=indent,eol,start
" 検索時にファイルの最後まで行ったら最初に戻る (nowrapscan:戻らない)
set wrapscan
" 括弧入力時に対応する括弧を表示 (noshowmatch:表示しない)
set showmatch
" コマンドライン補完するときに強化されたものを使う(参照 :help wildmenu)
set wildmenu
" テキスト挿入中の自動折り返しを日本語に対応させる
set formatoptions+=mM


"---------------------------------------------------------------------------
" GUI固有ではない画面表示の設定:
"
" 行番号を非表示 (nonumber:非表示)
set number
" ルーラーを表示 (noruler:非表示)
set ruler
" タブや改行を表示 (nolist:非表示)
set list
" どの文字でタブや改行を表示するかを設定
set listchars=tab:>-,extends:<,trail:-,eol:<
" 長い行を折り返して表示 (nowrap:折り返さない)
set wrap
" 常にステータス行を表示 (詳細は:he laststatus)
set laststatus=2
" コマンドラインの高さ (Windows用gvim使用時はgvimrcを編集すること)
set cmdheight=2
" コマンドをステータス行に表示
set showcmd
" タイトルを表示
set title
" 画面を黒地に白にする (次行の先頭の " を削除すれば有効になる)
colorscheme iceberg

"---------------------------------------------------------------------------
" ファイル操作に関する設定:
"
" バックアップファイルを作成しない (次行の先頭の " を削除すれば有効になる)
"set nobackup
" バックアップファイル（~ファイル）の出力先
set backupdir=/Users/hirhayak/.vimfiles/tmp
" undoファイル（un~ファイル）の出力先
set undodir=/Users/hirhayak/.vimfiles/tmp
" _viminfoファイルの出力先
set viminfo+=n/Users/hirhayak/.vimfiles/tmp/viminfo.txt
" バッファの文字コードをUTF-8に設定する
set encoding=utf-8
" ファイル書き込み時の文字コードをUTF-8に設定する
set fileencoding=utf-8
" ファイル読み込み時に、UTF-8->shift_jisの順で読み込みを試みる
set fileencodings=utr-8,shift_jis
" 改行コードにunix形式を利用
set fileformat=unix

