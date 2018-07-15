scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

function! s:tex_sort_main(fname, idx, finfo, data) abort " {{{
  let i = get(a:finfo[a:fname], 'i', 0)
  let idx = a:idx
  for inputs in a:finfo[a:fname]['input']
    while a:data[i]['filename'] == a:fname && a:data[i]['lnum'] < inputs[0]
      let a:data[i]['idx'] = idx
      let idx += 1
      let i += 1
    endwhile
    if has_key(a:finfo, inputs[1])
      let idx = s:tex_sort_main(inputs[1], idx, a:finfo, a:data)
    elseif has_key(a:finfo, inputs[1] . '.tex')
      let idx = s:tex_sort_main(inputs[1] . '.tex', idx, a:finfo, a:data)
    else
      let fmt = printf('.*/%s.tex', inputs[1])
      for key in keys(a:finfo)
        if key =~# fmt
          let idx = s:tex_sort_main(key, idx, a:finfo, a:data)
          break
        endif
      endfor
    endif
  endfor
  while i < len(a:data) && a:data[i]['filename'] == a:fname
    let a:data[i]['idx'] = idx
    let idx += 1
    let i += 1
  endwhile
  return idx
endfunction " }}}

function! s:make_patterns(pkinds) abort " {{{
  let pkinds = '^[' . a:pkinds . ']$'
  let patterns = []
  for [kind, pattern] in [
        \ ['c', 'chapter'],
        \ ['s', 'section'],
        \ ['u', 'subsection'],
        \ ['b', 'subsubsection'],
        \ ['p', 'part']]
    if pkinds =~# kind
      call add(patterns, [kind, '\\' . pattern . '\>'])
    endif
  endfor
  return patterns
endfunction " }}}

function! s:tex_filter_data(data, pkinds) abort " {{{
  let od = {'kind': 'l', 'filename': '', 'lnum': -1}
  let patterns = s:make_patterns(a:pkinds)

  for d in a:data
    if d.kind == 'l'
      for [kind, pattern] in patterns
        if d.text =~# pattern
          let d.kind = kind
        endif
      endfor
    elseif d.kind !~# '[csubi]'
      throw printf('Outline: tex: unknown kind: %s', d.kind)
    endif
    if od.lnum == d.lnum && od.filename == d.filename
      " 重複を見つけた.
      if od.kind == d.kind
        let od.kind = 'l'  " od を消す
      else
        for k in ['c', 's', 'u', 'b']
          if od.kind == k
            let d.kind = 'l'
            break
          elseif d.kind == k
            let od.kind = 'l'
            break
          endif
        endfor
      endif
    endif
    let od = d

  endfor
  return filter(a:data, 'v:val.kind != "l"')
endfunction " }}}

function! s:tex_get_finfo(files) abort " {{{
" 開いていないファイルの解析は, :enew? readfile?
" NOTE readfile してから for すると倍くらい遅い
" とりあえずおそい
  let finfo = {}
  python3 << endpython
import re, vim
files = vim.eval('a:files')
ret = {}

for fname in files:
  if fname in ret:
    continue
  dic = {'main': 0, 'input': []}
  ret[fname] = dic
  setf = False
  with open(fname, 'r') as f:
    for i, line in enumerate(f):
      if re.match(r'\s*\\document(class|style)\b', line):
        dic['main'] = 1
        setf = True
        continue
      line = line[: line.find('%')]
      m = re.search(r'\\in(put|clude)\b{?([^%}]+)\b}?', line)
      if not m:
        continue
      setf = True
      dic['input'].append([i, m.group(2)])
vim.command('let finfo = {}'.format(ret))
endpython
  return finfo
endfunction " }}}

function! s:parse_kinds(kinds) abort " {{{
  let ret = ['', '']
  let idx = 0  " +=0, -=1
  for c in split(a:kinds, '\zs')
    if c == '+'
      let idx = 0
    elseif c == '-'
      let idx = 1
    else
      let ret[idx] .= c
    endif
  endfor
  return ret
endfunction " }}}

function! outline#tex#sort(data, files, kinds) abort " {{{
  " data: ctags の解析結果 (string)
  " files: ctags の引数で渡したファイル
  " kinds: ctags --kinds=$kinds
  let files = split(a:files, ' ')
  let kinds = s:parse_kinds(a:kinds)

  " main(\documentclass), \include
  let finfo = s:tex_get_finfo(files)

  " data の情報を追加
  " csub より, l のほうが優先されてしまうことがある
  let data = s:tex_filter_data(a:data, kinds[0])

  let fname = ''
  for i in range(len(data))
    if data[i].filename != fname
      let fname = data[i].filename
      let finfo[fname]['i'] = i
    endif
  endfor

  let idx = 0
  for i in range(len(files))
    if finfo[files[i]]['main'] != 0
      let idx = s:tex_sort_main(files[i], idx, finfo, data)
    endif
  endfor
  for d in data
    if get(d, 'idx', -1) < 0
      let d['idx'] = idx
      let idx += 1
    endif
  endfor
  return sort(data, {i1, i2 -> i1.idx - i2.idx})
endfunction " }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et ts=2 sts=2 sw=2 tw=0:
