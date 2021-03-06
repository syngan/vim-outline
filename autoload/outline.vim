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
      \ 'cmdopt': '',
      \ 'format': '%l: %m'}
let s:def['python'] = {'kinds': '+cfm-vIixzl'}
" csub が l に紛れることがあるので, l 必須
" i は \input を返してくれない
let s:def['tex'] = {'kinds': '+pcsubl-PG', 'files': '*.tex', 'format': '%f:%l: %m'}
if has('python3')
  let s:def['tex']['sort'] = function('outline#tex#sort')
endif
let s:def['vim'] = {'kinds': '+acf-vmn'}

function! outline#msg(mesg) abort " {{{
  echo 'outline: ' . a:mesg
endfunction " }}}

function! s:debug(mes) abort " {{{
  if s:get('debug')
    silent! call vimconsole#log(printf('%s: %s', strftime("%T"), a:mes))
  endif
endfunction " }}}

function! s:get(key) abort " {{{
  " 引数 -> g:outline -> s:def
  for def in [s:arg_conf, get(g:, 'outline', {}), s:def]
    for ft in [&ft, '_']
      if has_key(def, ft) && has_key(def[ft], a:key)
        return def[ft][a:key]
      endif
    endfor
  endfor
  throw 'outline: unknown key: ' . a:key
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

function! s:get_kinds() abort " {{{
  " +- がないときは, + だけが指定されたとして, - を補完する.
  let kinds = s:get('kinds')
  if kinds =~# '^[A-Za-z]\+$' && has_key(s:def, &ft) && !has_key(s:def[&ft], 'kinds')
    let org = substitute(s:def[&ft].kinds, '[+-]', '', 'g')
    let org = substitute(org, '[' . kinds . ']', '', 'g')
    let kinds = printf('+%s-%s', kinds, org)
  endif
  return kinds
endfunction " }}}

function! s:format(d, format) abort " {{{
  let t = a:format
  let t = substitute(t, '%k', a:d.kind, 'g')
  let t = substitute(t, '%l', a:d.lnum, 'g')
  let t = substitute(t, '%m', a:d.text, 'g')
  let t = substitute(t, '%f', fnamemodify(a:d.filename, ':t'), 'g')
  let t = substitute(t, '%F', fnamemodify(a:d.filename, ':p'), 'g')
  return t
endfunction " }}}

function! s:parse_ctags(tempfiles) abort " {{{
  let tempfiles = a:tempfiles
  let ret = []
  let liness = map(tempfiles, {key, val -> readfile(val.f)})

  let format = s:get('format')
  let dold = {'filename': '', 'lnum': -1}

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
      throw 'outline: unmatch'
    endif
    if m[2] !~# '^\s*$'
      let d = {}
      let d.filename = m[1]
      let d.text = substitute(m[2], '\\\\', '\\', 'g')
      let d.text = substitute(d.text, '\$$', '', '')
      let d.kind = m[3]
      let tsv = split(liness[1][i], '\t')
      let d.lnum = str2nr(matchstr(tsv[2], '^\d\+\ze;"'))
      let d.ftxt = s:format(d, format)
      if dold.lnum != d.lnum || dold.filename != d.filename
        let ret += [d]
        let dold = d
      endif
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

function! s:output(data, conf) abort " {{{
  " data -- a list of dict
  " see :h setqflist()
  let outputter = s:get('outputter')
  if outputter == 'quickfix'
    return setqflist(a:data, 'r')
  elseif outputter == 'loclist'
    return setloclist(s:get('nr'), a:data, 'r')
  else
    return outline#buffer#output(a:data, a:conf, s:get('split'), s:get('bufname'))
  endif
endfunction " }}}

function! outline#disp(ch, msg) abort " {{{
  echom a:ch . ": " . a:msg
endfunction " }}}

function! outline#do(conf) abort " {{{
  let s:arg_conf = {&ft: a:conf}
  let kinds = s:get_kinds()
  let f = s:get('files')
  if f =~# '%'
    let files = glob(f)
  else
    let dir = expand(s:get('dir'))
    let files = glob(printf('%s/%s', dir, s:get('files')))
  endif
  let files = substitute(files, '\n', ' ', 'g')

  if kinds =~# '^\s*$'
    let cmd = printf('-u %s', s:get('cmdopt'))
  else
    let cmd = printf('-u --kinds-%s=%s %s', &ft, kinds, s:get('cmdopt'))
  endif

  let tempfiles = [{'c': ''}, {'c': ' -n'}]
  for dat in tempfiles
    let dat.f = tempname()
    let cmd2 = printf('%s %s -f %s%s %s', s:get('command'), cmd, dat.f, dat.c, files)
  " let cmd = s:get('command') . ' -f ' . tempfile . ' -u -n '
    call s:debug(cmd2)
    let dat.j = job_start(cmd2, {"callback": "outline#disp"})
  endfor

  for dat in tempfiles
    while job_status(dat.j) == "run"
      sleep 100m
    endwhile
  endfor

  call s:debug("end")

  let ret = s:parse_ctags(tempfiles)
  if s:has('sort')
    call s:debug('sort start')
    let ret = s:get('sort')(ret, files, s:get('kinds'))
    call s:debug('sort end')
  endif
  return s:output(ret, a:conf)
endfunction " }}}

function! s:stol(str) " {{{
  let list = []
  let str = a:str
  while str !~# '^\s*$'
    let str = matchstr(str, '^\s*\zs.*$')
    let key = matchstr(str, '^-\zs[a-z][a-z_]*\ze=')
    if key == ''
      break
    endif
    let str = str[strlen(key) + 2: ]
    if str[0] == "'"
      let arg = matchstr(str, '\v''\zs[^'']*\ze''')
      echo arg
      let str = str[strlen(arg) + 2 :]
    elseif str[0] == '"'
      let arg = matchstr(str, '\v"\zs[^"]*\ze"')
      let str = str[strlen(arg) + 2 :]
    else
      let arg = matchstr(str, '\S\+')
      let str = str[strlen(arg) + 0 :]
    endif
    call add(list, [key, arg])
  endwhile

  return [list, str]
endfunction " }}}

function! s:parse_cmdline(str) abort " {{{
  let [s, rest] = s:stol(a:str)
  if rest !~# '^\s*$'
    echomsg 'outline: invalid key: ' . rest
    return [{}, []]
  endif
  let s:arg_conf = {}
  let conf = {}
  for i in range(len(s))
    let conf[s[i][0]] = s[i][1]
    try
      call s:get(s[i][0])
    catch
      echomsg 'outline: invalid key: ' . s[i][0]
      return [{}, []]
    endtry
  endfor
  return conf
endfunction " }}}

function! outline#command(qargs) abort " {{{
  let conf = s:parse_cmdline(a:qargs)
  return outline#do(conf)
endfunction " }}}

function! outline#complete(arg, ...) abort " {{{
  if a:arg =~# '^-outputter='
    return map(['buffer', 'quickfix', 'loclist'], '"-outputter=" . v:val')
  elseif a:arg =~# '^-format='
    return map(['%l: %m', '%f:%l: %m', '%F:%l: %m'], '"-format=''" . v:val . "''"')
  else
    return ['-format=', '-cmdopt=', '-kinds=', '-outputter=', '-split=', '-bufname=']
  endif
endfunction " }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et ts=2 sts=2 sw=2 tw=0:
