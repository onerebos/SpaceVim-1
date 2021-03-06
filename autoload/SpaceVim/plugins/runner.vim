"=============================================================================
" runner.vim --- code runner for SpaceVim
" Copyright (c) 2016-2020 Wang Shidong & Contributors
" Author: Shidong Wang < wsdjeg at 163.com >
" URL: https://spacevim.org
" License: GPLv3
"=============================================================================

let s:runners = {}

let s:JOB = SpaceVim#api#import('job')
let s:BUFFER = SpaceVim#api#import('vim#buffer')
let s:STRING = SpaceVim#api#import('data#string')
let s:FILE = SpaceVim#api#import('file')
let s:VIM = SpaceVim#api#import('vim')
let s:SYS = SpaceVim#api#import('system')
let s:ICONV = SpaceVim#api#import('iconv')

let s:LOGGER =SpaceVim#logger#derive('runner')

" use code runner buffer for tab
"
"

let s:bufnr = 0
" @fixme win_getid requires vim 7.4.1557
let s:winid = -1
let s:target = ''
let s:lines = 0
let s:runner_jobid = 0
let s:status = {
      \ 'is_running' : 0,
      \ 'has_errors' : 0,
      \ 'exit_code' : 0
      \ }

function! s:open_win() abort
  if s:bufnr !=# 0 && bufexists(s:bufnr) && index(tabpagebuflist(), s:bufnr) !=# -1
    return
  endif
  botright split __runner__
  let lines = &lines * 30 / 100
  exe 'resize ' . lines
  setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap cursorline nospell nonu norelativenumber winfixheight nomodifiable
  set filetype=SpaceVimRunner
  nnoremap <silent><buffer> q :call <SID>close()<cr>
  nnoremap <silent><buffer> i :call <SID>insert()<cr>
  nnoremap <silent><buffer> <C-c> :call <SID>stop_runner()<cr>
  augroup spacevim_runner
    autocmd!
    autocmd BufWipeout <buffer> call <SID>stop_runner()
  augroup END
  let s:bufnr = bufnr('%')
  if exists('*win_getid')
    let s:winid = win_getid(winnr())
  endif
  wincmd p
endfunction

function! s:insert() abort
  call inputsave()
  let input = input('input >')
  if !empty(input) && s:status.is_running == 1
    call s:JOB.send(s:runner_jobid, input)
  endif
  normal! :
  call inputrestore()
endfunction


let s:running_cmd = ''

function! s:async_run(runner, ...) abort
  if type(a:runner) == type('')
    " the runner is a string, the %s will be replaced as a file name.
    try
      let cmd = printf(a:runner, get(s:, 'selected_file', bufname('%')))
    catch
      let cmd = a:runner
    endtry
    call SpaceVim#logger#info('   cmd:' . string(cmd))
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , -1, 0, ['[Running] ' . cmd, '', repeat('-', 20)])
    let s:lines += 3
    let s:start_time = reltime()
    let opts = get(a:000, 0, {})
    let s:runner_jobid =  s:JOB.start(cmd,extend({
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_exit'),
          \ }, opts))
  elseif type(a:runner) ==# type([]) && len(a:runner) ==# 2
    " the runner is a list with two items
    " the first item is compile cmd, and the second one is running cmd.

    let s:target = s:FILE.unify_path(tempname(), ':p')
    let dir = fnamemodify(s:target, ':h')
    if !isdirectory(dir)
      call mkdir(dir, 'p')
    endif
    if type(a:runner[0]) == type({})
      if type(a:runner[0].exe) == type(function('tr'))
        let exe = call(a:runner[0].exe, [])
      elseif type(a:runner[0].exe) ==# type('')
        let exe = [a:runner[0].exe]
      endif
      let usestdin = get(a:runner[0], 'usestdin', 0)
      let compile_cmd = exe + [get(a:runner[0], 'targetopt', '')] + [s:target]
      if usestdin
        let compile_cmd = compile_cmd + a:runner[0].opt
      else
        let compile_cmd = compile_cmd + a:runner[0].opt + [get(s:, 'selected_file', bufname('%'))]
      endif
    elseif type(a:runner[0]) ==# type('')
      let usestdin =  0
      let compile_cmd = substitute(printf(a:runner[0], bufname('%')), '#TEMP#', s:target, 'g')
    endif
    if type(compile_cmd) == type([])
      let compile_cmd_info = string(compile_cmd + (usestdin ? ['STDIN'] : []))
    else
      let compile_cmd_info = compile_cmd . (usestdin ? ' STDIN' : '') 
    endif
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , -1, 0, [
          \ '[Compile] ' . compile_cmd_info,
          \ '[Running] ' . s:target,
          \ '',
          \ repeat('-', 20)])
    let s:lines += 4
    let s:start_time = reltime()
    let s:runner_jobid =  s:JOB.start(compile_cmd,{
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_compile_exit'),
          \ })
    if usestdin && s:runner_jobid > 0
      let range = get(a:runner[0], 'range', [1, '$'])
      call s:JOB.send(s:runner_jobid, call('getline', range))
      call s:JOB.chanclose(s:runner_jobid, 'stdin')
    endif
  elseif type(a:runner) == type({})
    " the runner is a dict
    " keys:
    "   exe : function, return a cmd list
    "         string
    "   usestdin: true, use stdin
    "             false, use file name
    "   range: empty, whole buffer
    "          getline(a, b)
    if type(a:runner.exe) == type(function('tr'))
      let exe = call(a:runner.exe, [])
    elseif type(a:runner.exe) ==# type('')
      let exe = [a:runner.exe]
    endif
    let usestdin = get(a:runner, 'usestdin', 0)
    if usestdin
      let cmd = exe + a:runner.opt
    else
      let cmd = exe + a:runner.opt + [get(s:, 'selected_file', bufname('%'))]
    endif
    call SpaceVim#logger#info('   cmd:' . string(cmd))
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , -1, 0, ['[Running] ' . join(cmd) . (usestdin ? ' STDIN' : ''), '', repeat('-', 20)])
    let s:lines += 3
    let s:start_time = reltime()
    let s:runner_jobid =  s:JOB.start(cmd,{
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_exit'),
          \ })
    if usestdin && s:runner_jobid > 0
      let range = get(a:runner, 'range', [1, '$'])
      call s:JOB.send(s:runner_jobid, call('getline', range))
      call s:JOB.chanclose(s:runner_jobid, 'stdin')
    endif
  endif
  if s:runner_jobid > 0
    let s:status = {
          \ 'is_running' : 1,
          \ 'has_errors' : 0,
          \ 'exit_code' : 0
          \ }
  endif
endfunction

" @vimlint(EVL103, 1, a:id)
" @vimlint(EVL103, 1, a:data)
" @vimlint(EVL103, 1, a:event)
function! s:on_compile_exit(id, data, event) abort
  if a:id !=# s:runner_jobid
    " make sure the compile exit callback is for current compile command.
    return
  endif
  if a:data == 0
    let s:runner_jobid =  s:JOB.start(s:target,{
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_exit'),
          \ })
    if s:runner_jobid > 0
      let s:status = {
            \ 'is_running' : 1,
            \ 'has_errors' : 0,
            \ 'exit_code' : 0
            \ }
    endif
  else
    let s:end_time = reltime(s:start_time)
    let s:status.is_running = 0
    let s:status.exit_code = a:data
    let done = ['', '[Done] exited with code=' . a:data . ' in ' . s:STRING.trim(reltimestr(s:end_time)) . ' seconds']
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, done)
  endif
  call s:update_statusline()
endfunction
" @vimlint(EVL103, 0, a:id)
" @vimlint(EVL103, 0, a:data)
" @vimlint(EVL103, 0, a:event)

function! s:update_statusline() abort
  redrawstatus!
endfunction

function! SpaceVim#plugins#runner#reg_runner(ft, runner) abort
  if has('nvim') && get(g:, 'spacevim_terminal_runner', 0)
    call SpaceVim#plugins#quickrun#prepare()
    return
  endif
  let s:runners[a:ft] = a:runner
  let desc = printf('%-10S', a:ft) . string(a:runner)
  let cmd = "call SpaceVim#plugins#runner#set_language('" . a:ft . "')"
  call add(g:unite_source_menu_menus.RunnerLanguage.command_candidates, [desc,cmd])
endfunction

function! SpaceVim#plugins#runner#get(ft) abort
  return deepcopy(get(s:runners, a:ft , ''))
endfunction

" this func should support specific a runner
" the runner can be a string
function! SpaceVim#plugins#runner#open(...) abort
  call s:stop_runner()
  let s:runner_jobid = 0
  let s:lines = 0
  let s:status = {
        \ 'is_running' : 0,
        \ 'has_errors' : 0,
        \ 'exit_code' : 0
        \ }
  let s:selected_language = &filetype
  let runner = get(a:000, 0, get(s:runners, s:selected_language, ''))
  let opts = get(a:000, 1, {})
  if !empty(runner)
    call s:open_win()
    call s:async_run(runner, opts)
    call s:update_statusline()
  else
    let s:selected_language = get(s:, 'selected_language', '')
  endif
endfunction

" @vimlint(EVL103, 1, a:job_id)
" @vimlint(EVL103, 1, a:data)
" @vimlint(EVL103, 1, a:event)
function! s:on_stdout(job_id, data, event) abort
  if a:job_id !=# s:runner_jobid
    " that means, a new runner has been opennd
    " this is previous runner exit_callback
    return
  endif
  if bufexists(s:bufnr)
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, a:data)
  endif
  let s:lines += len(a:data)
  if s:winid >= 0
    call s:VIM.win_set_cursor(s:winid, [s:VIM.buf_line_count(s:bufnr), 1])
  endif
  call s:update_statusline()
endfunction

function! s:on_stderr(job_id, data, event) abort
  if a:job_id !=# s:runner_jobid
    " that means, a new runner has been opennd
    " this is previous runner exit_callback
    return
  endif
  let s:status.has_errors = 1
  if bufexists(s:bufnr)
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, a:data)
  endif
  let s:lines += len(a:data)
  if s:winid >= 0
    call s:VIM.win_set_cursor(s:winid, [s:VIM.buf_line_count(s:bufnr), 1])
  endif
  call s:update_statusline()
endfunction

function! s:on_exit(job_id, data, event) abort
  if a:job_id !=# s:runner_jobid
    " that means, a new runner has been opennd
    " this is previous runner exit_callback
    return
  endif
  let s:end_time = reltime(s:start_time)
  let s:status.is_running = 0
  let s:status.exit_code = a:data
  let done = ['', '[Done] exited with code=' . a:data . ' in ' . s:STRING.trim(reltimestr(s:end_time)) . ' seconds']
  if bufexists(s:bufnr)
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, done)
    call s:VIM.win_set_cursor(s:winid, [s:VIM.buf_line_count(s:bufnr), 1])
    call s:update_statusline()
  endif
endfunction
" @vimlint(EVL103, 0, a:job_id)
" @vimlint(EVL103, 0, a:data)
" @vimlint(EVL103, 0, a:event)

function! SpaceVim#plugins#runner#status() abort
  if s:status.is_running == 0
    return 'exit code : ' . s:status.exit_code 
          \ . '    time: ' . s:STRING.trim(reltimestr(s:end_time))
          \ . '    language: ' . get(s:, 'selected_language', &ft)
  endif
  return ''
endfunction

function! s:close() abort
  call s:stop_runner()
  if s:bufnr != 0 && bufexists(s:bufnr)
    exe 'bd ' s:bufnr
  endif
endfunction

function! s:stop_runner() abort
  if s:status.is_running == 1
    call s:JOB.stop(s:runner_jobid)
  endif
endfunction

function! SpaceVim#plugins#runner#select_file() abort
  let s:lines = 0
  let s:status = {
        \ 'is_running' : 0,
        \ 'is_exit' : 0,
        \ 'has_errors' : 0,
        \ 'exit_code' : 0
        \ }
  let s:selected_file = browse(0,'select a file to run', getcwd(), '')
  let runner = get(a:000, 0, get(s:runners, &filetype, ''))
  let s:selected_language = &filetype
  if !empty(runner)
    call SpaceVim#logger#info('Code runner startting:')
    call SpaceVim#logger#info('selected file :' . s:selected_file)
    call s:open_win()
    call s:async_run(runner)
    call s:update_statusline()
  endif
endfunction

let g:unite_source_menu_menus =
      \ get(g:,'unite_source_menu_menus',{})
let g:unite_source_menu_menus.RunnerLanguage = {'description':
      \ 'Custom mapped keyboard shortcuts                   [SPC] p p'}
let g:unite_source_menu_menus.RunnerLanguage.command_candidates =
      \ get(g:unite_source_menu_menus.RunnerLanguage,'command_candidates', [])

function! SpaceVim#plugins#runner#select_language() abort
  " @todo use denite or unite to select language
  " and set the s:selected_language
  " the all language is keys(s:runners)
  if SpaceVim#layers#isLoaded('denite')
    Denite menu:RunnerLanguage
  elseif SpaceVim#layers#isLoaded('leaderf')
    Leaderf menu --name RunnerLanguage
  endif
endfunction

function! SpaceVim#plugins#runner#set_language(lang) abort
  " @todo use denite or unite to select language
  " and set the s:selected_language
  " the all language is keys(s:runners)
  let s:selected_language = a:lang
endfunction


function! SpaceVim#plugins#runner#run_task(task) abort
  let isBackground = get(a:task, 'isBackground', 0)
  if !empty(a:task)
    let cmd = get(a:task, 'command', '') 
    let args = get(a:task, 'args', [])
    let opts = get(a:task, 'options', {})
    if !empty(args) && !empty(cmd)
      let cmd = cmd . ' ' . join(args, ' ')
    endif
    let opt = {}
    if !empty(opts) && has_key(opts, 'cwd') && !empty(opts.cwd)
      call extend(opt, {'cwd' : opts.cwd})
    endif
    if !empty(opts) && has_key(opts, 'env') && !empty(opts.env)
      call extend(opt, {'env' : opts.env})
    endif
    if has('nvim') && get(g:, 'spacevim_terminal_runner', 0) && 0
      call SpaceVim#plugins#quickrun#run_task(cmd, opt, isBackground)
    else
      if isBackground
        call s:run_backgroud(cmd, opt)
      else
        call SpaceVim#plugins#runner#open(cmd, opt) 
      endif
    endif
  endif
endfunction

function! s:on_backgroud_exit(job_id, data, event) abort
  let s:end_time = reltime(s:start_time)
  let exit_code = a:data
  echo 'task finished with code=' . a:data . ' in ' . s:STRING.trim(reltimestr(s:end_time)) . ' seconds'
endfunction

function! s:run_backgroud(cmd, ...) abort
  echo 'task running'
  let opts = get(a:000, 0, {})
  let s:start_time = reltime()
  call s:JOB.start(a:cmd,extend({
        \ 'on_exit' : function('s:on_backgroud_exit'),
        \ }, opts))
endfunction
