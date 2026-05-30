; inherits: xml

((tag
   (start_tag
     (tag_name) @tag_name)
   (content) @injection.content)
 (#any-of? @tag_name "select" "insert" "update" "delete" "sql")
 (#set! injection.language "sql"))
