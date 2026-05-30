" MyBatis Mapper XML - Enhanced SQL and tag highlighting
" Activates for any XML file that contains a <mapper> root element

" Check if the file contains a <mapper tag (broader than just Mapper.xml naming)
let s:is_mybatis = 0
for s:line in getline(1, min([50, line('$')]))
  if s:line =~# '<mapper\>'
    let s:is_mybatis = 1
    break
  endif
endfor

if !s:is_mybatis
  finish
endif

" --- Embedded SQL highlighting ---
if exists('b:current_syntax')
  let s:xml_current_syntax = b:current_syntax
  unlet b:current_syntax
endif

syntax include @MyBatisSql syntax/sql.vim

if exists('s:xml_current_syntax')
  let b:current_syntax = s:xml_current_syntax
  unlet s:xml_current_syntax
endif

" SQL blocks inside <select>, <insert>, <update>, <delete>, <sql> tags
syntax region mybatisSqlBlock
      \ start=+<\z(\%(select\|insert\|update\|delete\|sql\)\)\%(\_s\+[^>]*\)\?>+rs=e+1
      \ end=+</\z1>+me=s-1
      \ keepend
      \ contains=@MyBatisSql,mybatisParamHolder,mybatisDollarHolder,mybatisDynamicTag,mybatisDynamicTagEnd

" --- MyBatis placeholder highlighting ---
" #{propertyName} and #{propertyName,jdbcType=VARCHAR}
syntax match mybatisParamHolder /#{[^}]*}/ contained containedin=mybatisSqlBlock
highlight default link mybatisParamHolder Special

" ${propertyName}
syntax match mybatisDollarHolder /\${[^}]*}/ contained containedin=mybatisSqlBlock
highlight default link mybatisDollarHolder PreProc

" --- MyBatis dynamic SQL tags inside SQL blocks ---
syntax match mybatisDynamicTag /<\%(if\|where\|set\|foreach\|choose\|when\|otherwise\|trim\|bind\)\%(\s[^>]*\)\?\s*\/\?>/ contained containedin=mybatisSqlBlock
syntax match mybatisDynamicTagEnd /<\/\%(if\|where\|set\|foreach\|choose\|when\|otherwise\|trim\|bind\)>/ contained containedin=mybatisSqlBlock
highlight default link mybatisDynamicTag Keyword
highlight default link mybatisDynamicTagEnd Keyword

" --- resultMap tag highlighting ---
" Highlight the type attribute value in <resultMap type="com.example.User" ...>
syntax match mybatisResultMapType /\<type\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisResultMapType Type

" Highlight resultType and parameterType attribute values
syntax match mybatisTypeAttr /\<\%(resultType\|parameterType\)\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisTypeAttr Type

" Highlight id attribute values (for sql, resultMap, etc.)
syntax match mybatisIdAttr /\<id\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisIdAttr Identifier

" Highlight refid attribute values (for <include refid="..."/>)
syntax match mybatisRefIdAttr /\<refid\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisRefIdAttr Identifier

" Highlight namespace attribute value
syntax match mybatisNamespace /\<namespace\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisNamespace Type

" Highlight column/property attributes in result mappings
syntax match mybatisColumnAttr /\<column\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisColumnAttr String

syntax match mybatisPropertyAttr /\<property\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisPropertyAttr Identifier

syntax match mybatisJdbcTypeAttr /\<jdbcType\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisJdbcTypeAttr Constant

" Highlight resultMap attribute reference in statement tags
syntax match mybatisResultMapRef /\<resultMap\s*=\s*"[^"]*"/ containedin=xmlTag
highlight default link mybatisResultMapRef Identifier
