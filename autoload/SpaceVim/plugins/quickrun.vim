"=============================================================================
" quickrun.vim --- code quickrun for SpaceVim
" Copyright (c) 2016-2020 Heachen Bear
" Author: Heachen Bear < mrbeardad@qq.com >
" URL: https://spacevim.org
" License: GPLv3
"=============================================================================

" init quickrun variables for buffers
function! SpaceVim#plugins#quickrun#init(ft)
  let b:QuickRun_Compiler = g:quickrun_default_flags[a:ft].compiler
  let b:QuickRun_CompileFlag = g:quickrun_default_flags[a:ft].compileFlags
  let b:QuickRun_debugCompileFlag = g:quickrun_default_flags[a:ft].debugCompileFlags
  let b:QuickRun_debugCmd = g:quickrun_default_flags[a:ft].debugCmd
  let b:QuickRun_Cmd = g:quickrun_default_flags[a:ft].cmd
  let b:QuickRun_Args = g:quickrun_default_flags[a:ft].cmdArgs
  let b:QuickRun_Redir = g:quickrun_default_flags[a:ft].cmdRedir
endfunction

" provide commands to change quickrun variables
function! SpaceVim#plugins#quickrun#do(var, str) abort
  if a:str ==# ''
    exe 'let '. a:var
  else
    exe 'let '. a:var .' =  a:str'
  endif
endfunction

" add extended compile flags
function! s:extend_compile_arguments(regex, flags)
  let cntr = 0
  let ret = ''
  for thisRegex in a:regex
    if execute('g/'.thisRegex.'/echo 1') =~# '1'
      let ret = ret . ' ' . a:flags[cntr]
    endif
    let cntr += 1
  endfor
  return ret
endfunction

function! s:open_termwin() abort
  if s:bufnr != 0 && bufexists(s:bufnr)
    execute 'bd! ' . s:bufnr
  endif

  belowright 12 split __quickrun__
  setlocal buftype=nofile bufhidden=wipe nobuflisted list nomodifiable noim
        \ noswapfile
        \ nowrap
        \ cursorline
        \ nospell
        \ nonu
        \ norelativenumber
        \ winfixheight
        \ nomodifiable
endfunction

function! s:get_timestamp(file)
  python3 << EOF
filePath = vim.eval('a:file')
vim.command("let l:tmp = '" + time.strftime('%M:%H:%S', time.localtime(os.path.getmtime(filePath))) + "'")
EOF
  return l:tmp
endfunction

function! s:parse_flags(str, srcfile, exefile)
  let tmp = substitute(a:str, '\\\@<!\${thisFile}', a:srcfile, 'g')
  let tmp = substitute(tmp, '\\\@<!\${exeFile}', a:exefile, 'g')
  let tmp = substitute(tmp, '\\\@<!\${workspaceFolder}', SpaceVim#plugins#projectmanager#current_root(), 'g')
  return tmp
endfunction

let s:bufnr = 0
let s:Quickrun_Path = {}

function! SpaceVim#plugins#quickrun#QuickRun()
  if !isdirectory(g:QuickRun_Tempdir)
    call mkdir(g:QuickRun_Tempdir)
  endif

  let src_file_path = expand('%:p')
  let exe_file_path = g:QuickRun_Tempdir . expand('%:t') .'.'. s:get_timestamp(src_file_path).'.exe'
  let qr_cl = s:parse_flags(b:QuickRun_Compiler, src_file_path, exe_file_path)
  let qr_cf = s:parse_flags(b:QuickRun_CompileFlag, src_file_path, exe_file_path) .' '. s:parse_flags(s:extend_compile_arguments(g:quickrun_default_flags[&ft].extRegex, g:quickrun_default_flags[&ft].extFlags), src_file_path, exe_file_path)
  let qr_cmd = s:parse_flags(b:QuickRun_Cmd, src_file_path, exe_file_path)
  let qr_args = s:parse_flags(b:QuickRun_Args, src_file_path, exe_file_path)
  let qr_rd = s:parse_flags(b:QuickRun_Redir, src_file_path, exe_file_path)

  let qr_compile = ''
  if qr_cl !=# ''
    let qr_compile = 'echo "[1;32m[Compile] [34m' . qr_cl . '[0m ' . qr_cf . '";' . qr_cl .' '. qr_cf .';'
  endif

  let qr_prepare = ''
  if (has('unix') || has('wsl')) && !isdirectory('/sys/fs/cgroup/memory/quickrun')
    call jobstart('sudo mkdir /sys/fs/cgroup/memory/quickrun')
    let qr_prepare = 'echo $$ | sudo tee /sys/fs/cgroup/memory/test/cgroup.procs > /dev/null;echo 500M | sudo tee /sys/fs/cgroup/memory/test/memory.limit_in_bytes > /dev/null;echo 500M | sudo tee /sys/fs/cgroup/memory/test/memory.memsw.limit_in_bytes > /dev/null;'
  endif

  let qr_running = 'echo "[1;32m[Running] [34m' . qr_cmd . '[0m ' . qr_args .' '. qr_rd .'"; echo;echo "[31m--[34m--[35m--[33m--[32m--[36m--[37m--[36m--[32m--[33m--[35m--[34m--[31m--[34m--[35m--[33m--[32m--[36m--[37m--[36m--[32m--[33m--[35m--[34m--[31m--[34m--[35m--[33m--[32m--[36m--[37m--[36m--[32m--[33m--[m";quickrun_time ' . qr_cmd .' '. qr_args .' '. qr_rd .';'
  if has('nvim')
    let qr_running = qr_running . 'echo;echo "[38;5;242mPress any keys to close terminal or press <ESC> to avoid close it ..."'
  endif

  " 若当前文件为改动，且之前通过QuickRun运行过，且自上次编译之后未改动过文件内容，则直接运行上次编译的可执行文件；否则重新编译
  if &modified == 0 && has_key(s:Quickrun_Path, src_file_path) && s:Quickrun_Path[src_file_path] =~# s:get_timestamp(src_file_path)
    call s:open_termwin()
    call termopen(qr_prepare .'echo "[1;33m[Note]: Neither the buffer nor the file timestamp has changed. Rerunning last compiled program![m";'. qr_running)
  else
    if &modified == 1
      write
    endif
    call s:open_termwin()
    let s:Quickrun_Path[src_file_path] = exe_file_path
    call termopen(qr_compile . qr_prepare . qr_running)
  endif
  let s:bufnr = bufnr('%')
  wincmd p
endfunction

let s:last_input_winid = -1

function! SpaceVim#plugins#quickrun#OpenInputWin()
  let inputfile = g:QuickRun_Tempdir . expand('%:t') . '.input'
  if execute('echo winlayout()') =~# s:last_input_winid
    call win_gotoid(s:last_input_winid)
    if &modified == 1
      write
    endif
    edit openfile
  else
    execute "QuickrunRedir < " . inputfile
    let defxWinNr = win_findbuf(buffer_number('[defx] -0'))
    if defxWinNr != []
      call win_gotoid(defxWinNr[0])
    else
      Defx
    endif
    exe 'abo 20 split ' . inputfile
    setlocal nobuflisted ft=Input
        \ noswapfile
        \ nowrap
        \ cursorline
        \ nospell
        \ nu
        \ norelativenumber
        \ winfixheight
    let s:last_input_winid = win_getid()
  endif
endfunction

function! SpaceVim#plugins#quickrun#compile4debug()
  let src_file_path = expand('%:p')
  let exe_file_path = expand('%:r').'.exe'
  let qr_cl = s:parse_flags(b:QuickRun_Compiler, src_file_path, exe_file_path)
  let qr_cf = s:parse_flags(b:QuickRun_debugCompileFlag, src_file_path, exe_file_path) .' '. s:parse_flags(s:extend_compile_arguments(g:quickrun_default_flags[&ft].extRegex, g:quickrun_default_flags[&ft].extFlags), src_file_path, exe_file_path)
  let qr_cmd = s:parse_flags(b:QuickRun_debugCmd, src_file_path, exe_file_path)

  if &modified == 0 && filereadable(exe_file_path) && py3eval('os.path.getmtime("'.exe_file_path.'")') > py3eval('os.path.getmtime("'.src_file_path.'")')
    if qr_cmd =~# '^!'
      call jobstart(substitute(qr_cmd, '^!', '', ''))
    else
      call s:open_termwin()
      call termopen(qr_cmd)
    endif
  else
    if &modified == 1
      write
    endif
    if qr_cmd =~# '^!'
      call jobstart(qr_cl.' '.qr_cf.';'. substitute(qr_cmd, '^!', '', ''))
    else
      call s:open_termwin()
      call termopen(qr_cl.' '.qr_cf.';'. substitute(qr_cmd, '^!', '', ''))
    endif
  endif
endfunction

function! s:term_enter()
  if buffer_name() =~# 'term://'
    call feedkeys("\<c-\>\<c-n>:call setpos('.', b:pos)\<cr>:\<cr>")
  endif
endfunction

function! s:HasOpenFileWindows() abort
    for i in range(1, winnr('$'))
        let buf = winbufnr(i)

        " skip unlisted buffers, except for netrw
        if !buflisted(buf) && getbufvar(buf, '&filetype') != 'netrw'
            continue
        endif

        " skip temporary buffers with buftype set
        if getbufvar(buf, '&buftype') != ''
            continue
        endif

        " skip the preview window
        if getwinvar(i, '&previewwindow')
            continue
        endif

        return 1
    endfor

    return 0
endfunction

function WindowIsOnlyWindow()
  if !s:HasOpenFileWindows()
      quitall
  endif
endfunction

function! SpaceVim#plugins#quickrun#prepare()
  augroup QuickRun
    autocmd!
    for thisFT in keys(g:quickrun_default_flags)
      exe 'autocmd FileType '.thisFT.' call SpaceVim#plugins#quickrun#init(&ft)'
    endfor
    if has('nvim')
      au WinEnter * call s:term_enter()
      au WinLeave * let b:pos = getcurpos()
    endif
    au BufLeave *.input w
    au TermEnter * setlocal list nonu norelativenumber
    au WinEnter * call WindowIsOnlyWindow()
  augroup END

  " 终端模式
  if has('nvim')
    tnoremap <esc> <c-\><c-n>
    " tnoremap <c-up> <c-\><c-n><c-up>
    " tnoremap <c-down> <c-\><c-n><c-down>
    " tnoremap <c-right> <c-\><c-n><c-right>
    " tnoremap <c-left> <c-\><c-n><c-left>
    " tnoremap <c-w> <c-\><c-n><c-w>
    " tnoremap <silent><tab> <c-\><c-n>:winc w<cr>
    " tnoremap <silent><s-tab> <c-\><c-n>:winc p<cr>
    " tnoremap <c-a> <c-\><c-n><home>
    " tnoremap <c-e> <c-\><c-n><end>
    " tnoremap <up> <c-\><c-n><up>
    " tnoremap <down> <c-\><c-n><down>
    " tnoremap <left> <c-\><c-n><left>
    " tnoremap <right> <c-\><c-n><right>
    " tnoremap <silent><s-down> :call <SID>Scroll(1)<cr>
    " tnoremap <silent><s-up> :call <SID>Scroll(0)<cr>
  endif
  command! -nargs=? -complete=file QuickrunCompiler call SpaceVim#plugins#quickrun#do('b:QuickRun_Compiler', <q-args>)
  command! -nargs=? -complete=file QuickrunCompileFlag call SpaceVim#plugins#quickrun#do('b:QuickRun_CompileFlag', <q-args>)
  command! -nargs=? -complete=file QuickrunCompileFlagAdd let b:QuickRun_CompileFlag = b:QuickRun_CompileFlag . <q-args>
  command! -nargs=? -complete=file QuickrunDebugCompileFlag call SpaceVim#plugins#quickrun#do('b:QuickRun_debugCompileFlag', <q-args>)
  command! -nargs=? -complete=file QuickrunDebugCompileFlagAdd let b:QuickRun_debugCompileFlag = b:QuickRun_debugCompileFlag . <q-args>
  command! -nargs=? -complete=file QuickrunDebugCmd call SpaceVim#plugins#quickrun#do('b:QuickRun_debugCmd', <q-args>)
  command! -nargs=? -complete=file QuickrunCmd call SpaceVim#plugins#quickrun#do('b:QuickRun_Cmd', <q-args>)
  command! -nargs=? -complete=file QuickrunArgs call SpaceVim#plugins#quickrun#do('b:QuickRun_Args', <q-args>)
  command! -nargs=? -complete=file QuickrunRedir call SpaceVim#plugins#quickrun#do('b:QuickRun_Redir', <q-args>)
  py3 import tempfile
  py3 import time
  py3 import datetime
  py3 import os
  let g:QuickRun_Tempdir = py3eval('tempfile.gettempdir()') . '/QuickRun/'
endfunction