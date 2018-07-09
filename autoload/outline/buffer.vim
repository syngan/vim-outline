scriptencoding utf-8

" バッファへの結果出力
" p: preview
" P: preview with 'zo'
" q: quit

let s:save_cpo = &cpo
set cpo&vim

function! s:preview_or_jmp(preview, foldopen) abort " {{{
  let winnr = win_getid()
  let info = b:outline_data[line('.') - 1]
  try
    if win_gotoid(b:outline_winid)
      execute ':e' '+' . info.lnum info.filename
      execute 'normal!' 'zz'
      if a:foldopen
        execute 'normal!' 'zo'
      endif
    else
      call outline#msg('window not found. do :Output')
    endif
  finally
    if a:preview
      call win_gotoid(winnr)
    endif
  endtry
endfunction " }}}

function! s:set_local() abort " {{{
  nnoremap <buffer> q <C-w>c
  nnoremap <silent> <buffer> <CR> :<c-u>call <SID>preview_or_jmp(0, 0)<CR>
  nnoremap <silent> <buffer> p    :<c-u>call <SID>preview_or_jmp(1, 0)<CR>
  nnoremap <silent> <buffer> P    :<c-u>call <SID>preview_or_jmp(1, 1)<CR>
  nnoremap <silent> <buffer> <C-l> :<c-u>call outline#reflesh()<CR>
  setlocal bh=hide bt=nofile ff=unix fdm=manual
  setlocal noswapfile nobuflisted nomodifiable
endfunction " }}}

function! s:open_window(sp, name) abort " {{{
  if !bufexists(a:name)
    execute a:sp 'split'
    edit `=a:name`
    call s:set_local()
    return
  endif
  let name_ = '^' . substitute(a:name, '[', '\\[', 'g') . '$'
  if bufwinnr(name_) != -1
    execute bufwinnr(name_) 'wincmd w'
  else
    execute a:sp 'split'
    execute 'buffer' bufnr(name_)
  endif
endfunction " }}}

function! outline#buffer#output(data, conf, split, bufname) abort " {{{
  let winnr = win_getid()
  let ft = &ft
  call s:open_window(a:split, a:bufname)

  let data = []
  for d in a:data
    call add(data, d.ftxt)
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


let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et ts=2 sts=2 sw=2 tw=0:
