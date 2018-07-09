let s:save_cpo = &cpo
set cpo&vim

let s:def = {}
let s:def['_'] = {
      \ 'debug': 0,
      \ 'bufname': '[outline]',
      \ 'split': '',
      \ 'outputter': 'buffer',
      \ 'command': 'ctags',
      \ 'dir': '%:h', 'files': '%',
      \ 'nr': 0,
      \ 'kinds': '',
      \ 'cmdopt': ''}
let s:def['python'] = {'kinds': '+cfm-vIixzl'}
let s:def['tex'] = {'kinds': '+csubl-pPGi', 'files': '*.tex', 'sort': function('outline#tex#sort')}
let s:def['vim'] = {'kinds': '+acf-vmn'}

function! s:debug(mes) abort " {{{
  if s:get('debug')
    silent! call vimconsole#log(printf('%s: %s', strftime("%T"), a:mes))
  endif
endfunction " }}}

function! s:get(key) abort " {{{
  for def in [s:arg_conf, get(g:, 'outline', {}), s:def]
    for ft in [&ft, '_']
      if has_key(def, ft) && has_key(def[ft], a:key)
        return def[ft][a:key]
      endif
    endfor
  endfor
  throw 'unknown key: ' . a:key
endfunction " }}}

function! s:has(key) abort " {{{
  for def in [s:arg_conf, get(g:, 'outline', {}), s:def]
    for ft in [&ft, '_']
      if has_key(def, ft) && has_key(def[ft], a:key)
        return 1
      endif
    endfor
  endfor
  return 0
endfunction " }}}

function! s:parse_ctags(tempfiles) abort " {{{
  let tempfiles = a:tempfiles
  let ret = []
  let liness = [readfile(tempfiles[0][0]), readfile(tempfiles[1][0])]
  for i in range(len(liness[0]))
    let line = liness[0][i]
    if line[0] ==# '!'
      " infomation of universal-ctags
      continue
    endif
    " NOTE: pattern に \t が含まれていることがあるので,
    "       split() で分割できない.
    "     : text  filename  /^pattern$/;"  label
    " -n  : text  filename  lnum;"         label
    "     - label = lcsub
    "     - pattern /^ \\caption....
    let m = matchlist(line, '^.*\t\(\f\+\)\t/\^\(.*\)/;"\t\(\k\)')
    if len(m) == 0
      call s:debug(line)
      throw 'unmatch'
    endif
    let d = {}
    let d.filename = m[1]
    let d.text = substitute(m[2], '\\\\', '\\', 'g')
    let d.text = substitute(d.text, '\$$', '', '')
    let d.kind = m[3]
    let line = liness[1][i]
    let tsv = split(line, '\t')
    let d.lnum = str2nr(matchstr(tsv[2], '^\d\+\ze;"'))
    if d.text !~# '^\s*$'
      let ret += [d]
    endif
  endfor
  return ret
endfunction " }}}

function! outline#reflesh() abort " {{{
  let winnr = win_getid()
  let conf = b:outline_conf
  try
    call win_gotoid(b:outline_winid)
    return outline#do(conf)
  finally
    call win_gotoid(winnr)
  endtry
endfunction " }}}

function! outline#preview_or_jmp(preview) abort " {{{
  let winnr = win_getid()
  let info = b:outline_data[line('.') - 1]
  try
    call win_gotoid(b:outline_winid)
    execute info.lnum
    execute 'normal!' 'zz'
  finally
    if a:preview
      call win_gotoid(winnr)
    endif
  endtry
endfunction " }}}

function! s:set_local() abort " {{{
  nnoremap <buffer> q <C-w>c
  nnoremap <silent> <buffer> <CR> :<c-u>call outline#preview_or_jmp(0)<CR>
  nnoremap <silent> <buffer> p    :<c-u>call outline#preview_or_jmp(1)<CR>
  nnoremap <silent> <buffer> <C-l> :<c-u>call outline#reflesh()<CR>
  setlocal bh=hide bt=nofile ff=unix fdm=manual
  setlocal noswapfile nobuflisted nomodifiable
endfunction " }}}

function! s:open_window() abort " {{{
  let sp = s:get('split')
  let name = s:get('bufname')
  if !bufexists(name)
    execute sp 'split'
    edit `=name`
    call s:set_local()
    return
  endif
  let name_ = '^' . substitute(name, '[', '\\[', 'g') . '$'
  if bufwinnr(name_) != -1
    execute bufwinnr(name_) 'wincmd w'
  else
    execute sp 'split'
    execute 'buffer' bufnr(name_)
  endif
endfunction " }}}

function! s:output_buffer(data, conf) abort " {{{
  let winnr = win_getid()
  let ft = &ft
  call s:open_window()

  let data = []
  for d in a:data
    call add(data, printf('%4d: %s', d.lnum, d.text))
  endfor
  let b:outline_winid = winnr
  let b:outline_data = a:data
  let b:outline_conf = a:conf
  setlocal modifiable
  silent % delete _
  silent put = data
  silent 1 delete _
  setlocal nomodifiable nomodified
  execute 'setlocal ft='. ft
endfunction " }}}

function! s:output(data, conf) abort " {{{
  " data -- a list of dict
  " see :h setqflist()
  let outputter = s:get('outputter')
  if outputter == 'quickfix'
    return setqflist(a:data, 'r')
  elseif outputter == 'loclist'
    return setloclist(s:get('nr'), a:data, 'r')
  else
    return s:output_buffer(a:data, a:conf)
  endif
endfunction " }}}

function! outline#do(conf) abort " {{{
  let s:arg_conf = {&ft: a:conf}
  let kinds = s:get('kinds')
  if kinds == ''
    echo printf('dare? ft=%s bufname=%s', &ft, bufname(''))
    return
  endif
  let f = s:get('files')
  if f =~# '%'
    let files = glob(f)
  else
    let dir = expand(s:get('dir'))
    let files = glob(printf('%s/%s', dir, s:get('files')))
  endif
  let files = substitute(files, '\n', ' ', 'g')
  let cmd = printf(' -u --kinds-%s=%s %s ', &ft, kinds, s:get('cmdopt'))

  let tempfiles = [[tempname(), ''], [tempname(), ' -n']]
  call s:debug(tempfiles)
  for dat in tempfiles
    let cmd2 = printf('%s %s%s -f %s %s', s:get('command'), cmd, dat[1], dat[0], files)
  " let cmd = s:get('command') . ' -f ' . tempfile . ' -u -n '
    call s:debug(cmd2)
    call system(cmd2)
  endfor

  let ret = s:parse_ctags(tempfiles)
  if s:has('sort')
    call s:debug('sort start')
    let ret = s:get('sort')(ret, files)
    call s:debug('sort end')
  endif
  return s:output(ret, a:conf)
endfunction " }}}

function! s:stol(str) " {{{
  let list = []
  let str = a:str
  while str !~# '^\s*$'
    let str = matchstr(str, '^\s*\zs.*$')
    if str[0] == "'"
      let arg = matchstr(str, '\v''\zs[^'']*\ze''')
      let str = str[strlen(arg) + 2 :]
    elseif str[0] == '"'
      let arg = matchstr(str, '\v"\zs[^"]*\ze"')
      let str = str[strlen(arg) + 2 :]
    else
      let arg = matchstr(str, '\S\+')
      let str = str[strlen(arg) + 0 :]
    endif
    call add(list, arg)
  endwhile

  return list
endfunction " }}}

function! s:parse_cmdline(str) abort " {{{
  let s = s:stol(a:str)
  let s:arg_conf = {}
  let conf = {}
  let brk = -1
  for i in range(len(s))
    if s[i] == '--'
      let brk = i + 1
      break
    endif
    let l = matchlist(s[i], '^-\([a-z][a-z_]\+\)=\(.\+\)$')
    if l == []
      let brk = i
      break
    endif
    let conf[l[1]] = l[2]
    try
      call s:get(l[1])
    catch
      echomsg 'invalid key: ' . l[1]
      return [{}, []]
    endtry
  endfor
  if brk == -1
    let s = []
  else
    let s = s[brk : ]
  endif
  return [conf, s]
endfunction " }}}

function! outline#command(qargs) abort " {{{
  let [conf, _] = s:parse_cmdline(a:qargs)
  return outline#do(conf)
endfunction " }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et ts=2 sts=2 sw=2 tw=0:
