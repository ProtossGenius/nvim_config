local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local mybatis = require('user.mybatis')
local my_test = mybatis._test

-- 1. Test the enhanced get_attribute_at_cursor cursor ranges
-- Line structure: <resultMap id="BaseResultMap" type="com.example.demo.model.User">
-- Index mapping:
-- type start: col 30 (0-indexed)
-- =: col 34
-- ": col 35
-- c: col 36
-- r: col 61
-- ": col 62
local test_line = '<resultMap id="BaseResultMap" type="com.example.demo.model.User">'

-- Test on attribute name "type"
local attr_name, attr_val = my_test.get_attribute_at_cursor(test_line, 30)
support.expect_equal('get_attribute_at_cursor on attr name (type)', { attr_name, attr_val }, { 'type', 'com.example.demo.model.User' })

-- Test on '='
local attr_name_eq, attr_val_eq = my_test.get_attribute_at_cursor(test_line, 34)
support.expect_equal('get_attribute_at_cursor on = sign', { attr_name_eq, attr_val_eq }, { 'type', 'com.example.demo.model.User' })

-- Test on opening double quote '"'
local attr_name_oq, attr_val_oq = my_test.get_attribute_at_cursor(test_line, 35)
support.expect_equal('get_attribute_at_cursor on opening quote', { attr_name_oq, attr_val_oq }, { 'type', 'com.example.demo.model.User' })

-- Test inside the value string 'com.example.demo.model.User'
local attr_name_val, attr_val_val = my_test.get_attribute_at_cursor(test_line, 45)
support.expect_equal('get_attribute_at_cursor inside string', { attr_name_val, attr_val_val }, { 'type', 'com.example.demo.model.User' })

-- Test on closing double quote '"'
local attr_name_cq, attr_val_cq = my_test.get_attribute_at_cursor(test_line, 62)
support.expect_equal('get_attribute_at_cursor on closing quote', { attr_name_cq, attr_val_cq }, { 'type', 'com.example.demo.model.User' })

-- Test out of bounds (before id attribute)
local attr_name_oob, attr_val_oob = my_test.get_attribute_at_cursor(test_line, 5)
support.expect_equal('get_attribute_at_cursor out of bounds', { attr_name_oob, attr_val_oob }, { nil, nil })

-- 2. Mock project root and Java class scanning/completing
-- We will write a temp directory with a few Java files, and test get_all_project_classes
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir .. '/src/main/java/com/example/demo/model', 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local user_class_path = temp_dir .. '/src/main/java/com/example/demo/model/User.java'
local order_class_path = temp_dir .. '/src/main/java/com/example/demo/model/Order.java'

vim.fn.writefile({ 'public class User {}' }, user_class_path)
vim.fn.writefile({ 'public class Order {}' }, order_class_path)

-- Mock project root
local original_root = require('user.project').root
require('user.project').root = function() return temp_dir end

-- Test class scanning FQN extraction
local classes = my_test.get_all_project_classes()
table.sort(classes)
support.expect_equal('class scanning FQN count', #classes, 2)
support.expect_equal('class scanning FQN [1]', classes[1], 'com.example.demo.model.Order')
support.expect_equal('class scanning FQN [2]', classes[2], 'com.example.demo.model.User')

-- 3. Test get_completion_context
-- Test parameter completion
local line_param = "select * from user where email = #{em"
local col_param = #line_param
local ctx_p, start_p = my_test.get_completion_context(line_param, col_param)
support.expect_equal('get_completion_context parameter', { ctx_p, start_p }, { 'parameter', 35 })

-- Test class attribute completion
-- type="com.ex"
-- t(0) y(1) p(2) e(3) =(4) "(5) c(6)
local line_class = 'type="com.ex"'
local ctx_c, start_c = my_test.get_completion_context(line_class, 8)
support.expect_equal('get_completion_context class', { ctx_c, start_c }, { 'class', 6 })

-- Test resultMap attribute completion
-- resultMap="Base"
-- r(0) ... p(8) =(9) "(10) B(11)
local line_rm = 'resultMap="Base"'
local ctx_rm, start_rm = my_test.get_completion_context(line_rm, 13)
support.expect_equal('get_completion_context resultMap', { ctx_rm, start_rm }, { 'resultmap', 11 })

-- Test refid attribute completion
-- refid="Base"
-- r(0) ... d(4) =(5) "(6) B(7)
local line_ref = 'refid="Base"'
local ctx_ref, start_ref = my_test.get_completion_context(line_ref, 9)
support.expect_equal('get_completion_context refid', { ctx_ref, start_ref }, { 'refid', 7 })

-- 4. Test omnifunc interface programmatically
-- Mock buffer lines for resultMap and sql refids
support.reset({
  '<mapper namespace="com.example.UserMapper">',
  '  <resultMap id="UserResultMap" type="com.example.User">',
  '  </resultMap>',
  '  <sql id="Base_Column_List">',
  '    id, name',
  '  </sql>',
  '</mapper>'
}, 'xml')

-- Mock project root
require('user.project').root = function() return temp_dir end

-- Check resultMap completion in omnifunc
-- Setup context as resultmap
mybatis._omnifunc_context = 'resultmap'
local rm_matches = mybatis.omnifunc(0, 'User')
support.expect_equal('omnifunc resultmap match count', #rm_matches, 1)
support.expect_equal('omnifunc resultmap match details', rm_matches[1], { word = 'UserResultMap', abbr = 'UserResultMap', menu = '[ResultMap]' })

-- Check sql refid completion in omnifunc
mybatis._omnifunc_context = 'refid'
local ref_matches = mybatis.omnifunc(0, 'Base')
support.expect_equal('omnifunc refid match count', #ref_matches, 1)
support.expect_equal('omnifunc refid match details', ref_matches[1], { word = 'Base_Column_List', abbr = 'Base_Column_List', menu = '[SQL]' })

-- Check class completion in omnifunc
mybatis._omnifunc_context = 'class'
local class_matches = mybatis.omnifunc(0, 'User')
-- User.java was in class list as com.example.demo.model.User
support.expect_equal('omnifunc class match count', #class_matches, 1)
support.expect_equal('omnifunc class match details', class_matches[1], { word = 'com.example.demo.model.User', abbr = 'User', menu = '[Class]', info = 'com.example.demo.model.User' })

-- 5. Test enclosing resultMap type lookup
support.reset({
  '<resultMap id="UserResultMap" type="com.example.demo.model.User">',
  '  <id column="id" property="id"/>',
  '  <result column="username" property="username"/>',
  '</resultMap>'
}, 'xml')

-- Set cursor to line 3 (index 2 in 0-based lines) on the property "username" (col 32)
vim.api.nvim_win_set_cursor(0, { 3, 30 })
local rm_type = my_test.find_enclosing_resultmap_type(0)
support.expect_equal('find_enclosing_resultmap_type inside resultMap', rm_type, 'com.example.demo.model.User')

-- Mock project root so find_java_file_by_fqn can find User.java under temp_dir
local original_root = require('user.project').root
require('user.project').root = function() return temp_dir end

-- Populate User.java with fields so the jump can locate 'username' on line 4
vim.fn.writefile({
  'package com.example.demo.model;',
  'public class User {',
  '  private Long id;',
  '  private String username;',
  '}'
}, user_class_path)

-- Set cursor to col 1 (which is `<` of line 3, NOT on the "property" string itself!)
vim.api.nvim_win_set_cursor(0, { 3, 1 })
vim.bo.modified = false
local jumped = my_test.try_jump_resultmap_property(0)
support.expect_equal('try_jump_resultmap_property from anywhere on the line', jumped, true)
-- Cursor should have jumped to User.java on line 3 (the username field!)
local current_buf = vim.api.nvim_get_current_buf()
local current_file = vim.api.nvim_buf_get_name(current_buf)
local current_cursor = vim.api.nvim_win_get_cursor(0)
support.expect_true('jumped to correct Model class file', current_file:find('User%.java$') ~= nil)
support.expect_equal('jumped to correct field line in Model class', current_cursor[1], 4)

-- Restore project root mock
require('user.project').root = original_root

-- Restore buffer to xml for next tests
support.reset({
  '<mapper namespace="com.example.UserMapper">',
  '  <resultMap id="UserResultMap" type="com.example.User">',
  '  </resultMap>',
  '  <sql id="Base_Column_List">',
  '    id, name',
  '  </sql>',
  '</mapper>'
}, 'xml')

-- Test field declaration matching
local java_lines = {
  'public class User {',
  '  private Long id;',
  '  private String username;',
  '  private List<String> roles = new ArrayList<>();',
  '}'
}
local field_ln1 = my_test.find_field_declaration_line(java_lines, 'id')
support.expect_equal('find_field_declaration_line for id', field_ln1, 2)
local field_ln2 = my_test.find_field_declaration_line(java_lines, 'username')
support.expect_equal('find_field_declaration_line for username', field_ln2, 3)
local field_ln3 = my_test.find_field_declaration_line(java_lines, 'roles')
support.expect_equal('find_field_declaration_line for roles with generics', field_ln3, 4)

-- 6. Test get_placeholder_at_cursor
local placeholder_line = 'select * from user where name = #{user.name } and status = ${status}'
-- Cursor inside user.name (col 36)
local p1 = my_test.get_placeholder_at_cursor(placeholder_line, 36)
support.expect_equal('get_placeholder_at_cursor user.name', p1, 'user.name')
-- Cursor inside status (col 60)
local p2 = my_test.get_placeholder_at_cursor(placeholder_line, 60)
support.expect_equal('get_placeholder_at_cursor status', p2, 'status')
-- Cursor outside braces (col 10)
local p3 = my_test.get_placeholder_at_cursor(placeholder_line, 10)
support.expect_equal('get_placeholder_at_cursor out of bounds', p3, nil)

-- 7. Test FQN resolution in Java files
-- Create a mock Java file to read imports
local mock_java_path = temp_dir .. '/src/main/java/com/example/demo/model/UserMapper.java'
vim.fn.writefile({
  'package com.example.demo.model;',
  'import com.example.demo.model.User;',
  'import com.example.demo.dto.UserQuery;',
  'public interface UserMapper {}'
}, mock_java_path)

local param_user = { type = 'User', full_type = 'User' }
local fqn_user = my_test.resolve_param_type_fqn(param_user, mock_java_path)
support.expect_equal('resolve_param_type_fqn from import', fqn_user, 'com.example.demo.model.User')

local param_query = { type = 'UserQuery', full_type = 'UserQuery' }
local fqn_query = my_test.resolve_param_type_fqn(param_query, mock_java_path)
support.expect_equal('resolve_param_type_fqn from import 2', fqn_query, 'com.example.demo.dto.UserQuery')

-- Cleanup project root mock and temp files
require('user.project').root = original_root
vim.fn.delete(temp_dir, 'rf')

support.flush()
