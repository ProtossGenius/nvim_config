if expand('%:t') !~# 'Mapper\.xml$'
  finish
endif

if exists('b:current_syntax')
  let s:xml_current_syntax = b:current_syntax
  unlet b:current_syntax
endif

syntax include @MyBatisSql syntax/sql.vim

if exists('s:xml_current_syntax')
  let b:current_syntax = s:xml_current_syntax
  unlet s:xml_current_syntax
endif

syntax region mybatisSqlBlock
      \ start=+<\z(\%(select\|insert\|update\|delete\|sql\)\)\%(\_s\+[^>]*\)\?>+rs=e+1
      \ end=+</\z1>+me=s-1
      \ keepend
      \ contains=@MyBatisSql
