let s:save_cpo = &cpo
set cpo&vim

command! -nargs=* -complete=customlist,outline#complete Outline call outline#command(<q-args>)

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et ts=2 sts=2 sw=2 tw=0:
