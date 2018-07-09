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
  while a:data[i]['filename'] == a:fname
    let a:data[i]['idx'] = idx
    let idx += 1
    let i += 1
  endwhile
  return idx
endfunction " }}}

function! s:tex_filter_data(data) abort " {{{
  let od = {'kind': 'l', 'filename': '', 'lnum': -1}
  for d in a:data
    if d.kind == 'l'
      if d.text =~# '\\chapter\>'
        let d.kind = 'c'
      elseif d.text =~# '\\section\>'
        let d.kind = 's'
      elseif d.text =~# '\\subsection\>'
        let d.kind = 'u'
      elseif d.text =~# '\\subsubsection\>'
        let d.kind = 'b'
      endif
    elseif d.kind !~# '[csub]'
      throw Exception(d.kind)
    endif
    if od.lnum == d.lnum && od.filename == d.filename
      if od.kind == d.kind
        let od.kind = 'l'
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

function! outline#tex#sort(data, files) abort " {{{

  " 開いていないファイルの解析は, :enew? readfile?
  " NOTE readfile してから for すると倍くらい遅い
  " とりあえずおそい
  let files = split(a:files, ' ')

  let finfo = s:tex_get_finfo(files)

  " data の情報を追加
  " csub あたりが, l のほうが優先されてしまうので,
  " 更新する

  let data = s:tex_filter_data(a:data)

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

"  call s:debug('enew ' . len(fnames))
"  let winnr = win_getid()
"  new
"  try
"    let finfo = {}
"    let maininfo = []
"    for ftbl in fnames
"      silent % delete _
"      let fname = ftbl['fname']
"      call s:debug(fname)
"      silent! execute ':r ' . fname
"      silent 1 delete _
"      let finfo[fname] = []
"      while 1
"        let ret = search('\c^[^%]*\\\(input\|include\|documentclass\|documentstyle\)\>', 'We')
"        if ret == 0
"          break
"        endif
"        let text = getline('.')
"        let lnum = line('.')
"        if text =~# '\\input\>'
"          call add(finfo[fname], {'type': 'input', 'lnum': lnum, 'i': fname['i']})
"        else
"          call add(maininfo, {'type': 'main', 'lnum': lnum, 'i': fname['i']})
"        endif
"      endwhile
"    endfor
"  finally
"    quit!
"    call win_gotoid(winnr)
"  endtry
"  call s:debug('readfile ' . len(fnames))
"
"  try
"    let finfo = {}
"    let maininfo = []
"    for ftbl in fnames
"      let fname = ftbl['fname']
"      call s:debug(fname)
"      let lines = readfile(fname)
"      for i in range(len(lines))
"        if lines[i] =~# '\c^[^%]*\\input\>'
"          call add(finfo[fname], {'type': 'input', 'lnum': i, 'i': fname['i']})
"        elseif lines[i] =~# '\c^[^%]*\\document\(style\|class\)\>'
"          call add(maininfo, {'type': 'main', 'lnum': i, 'i': fname['i']})
"        endif
"      endfor
"    endfor
"  finally
"  endtry
endfunction " }}}


let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et ts=2 sts=2 sw=2 tw=0:
