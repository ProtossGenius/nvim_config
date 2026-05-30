local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local mybatis = require('user.mybatis')
local my_test = mybatis._test

-- 1. Test is_model_type
support.expect_equal('is_model_type String is false', my_test.is_model_type('String'), false)
support.expect_equal('is_model_type int is false', my_test.is_model_type('int'), false)
support.expect_equal('is_model_type List is false', my_test.is_model_type('List'), false)
support.expect_equal('is_model_type User is true', my_test.is_model_type('User'), true)
support.expect_equal('is_model_type com.example.User is true', my_test.is_model_type('com.example.User'), true)

-- 2. Test fqn_to_path
support.expect_equal('fqn_to_path simple FQN', my_test.fqn_to_path('com.example.User'), 'com/example/User.java')

-- 3. Test get_attribute_at_cursor
local line = '<resultMap id="BaseResultMap" type="com.example.model.User">'
-- Index of com.example.model.User starts at 36 (0-indexed column 35)
support.expect_equal('get_attribute_at_cursor type FQN', { my_test.get_attribute_at_cursor(line, 40) }, { 'type', 'com.example.model.User' })
support.expect_equal('get_attribute_at_cursor id attr', { my_test.get_attribute_at_cursor(line, 18) }, { 'id', 'BaseResultMap' })
support.expect_equal('get_attribute_at_cursor out of bounds', { my_test.get_attribute_at_cursor(line, 5) }, { nil, nil })

-- 4. Test parse_method_params and extract_model_fields with temp files
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir .. '/src/main/java/com/example', 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local mapper_path = temp_dir .. '/src/main/java/com/example/UserMapper.java'
local model_path = temp_dir .. '/src/main/java/com/example/User.java'

vim.fn.writefile({
  'package com.example;',
  'import org.apache.ibatis.annotations.Param;',
  'import java.util.List;',
  'public interface UserMapper {',
  '    User selectUserById(@Param("id") Long id);',
  '    int insertUser(User user);',
  '    List<User> selectUsers(@Param("status") Integer status, @Param("role") String role);',
  '}',
}, mapper_path)

vim.fn.writefile({
  'package com.example;',
  'import lombok.Data;',
  '@Data',
  'public class User {',
  '    private Long id;',
  '    private String username;',
  '    private String email;',
  '    public static final long serialVersionUID = 1L;',
  '}',
}, model_path)

-- Test parse_method_params
local select_params = my_test.parse_method_params(mapper_path, 'selectUserById')
support.expect_equal('parse_method_params selectUserById count', #select_params, 1)
support.expect_equal('parse_method_params selectUserById name', select_params[1].name, 'id')
support.expect_equal('parse_method_params selectUserById type', select_params[1].type, 'Long')
support.expect_equal('parse_method_params selectUserById annotation', select_params[1].param_annotation, 'id')

local insert_params = my_test.parse_method_params(mapper_path, 'insertUser')
support.expect_equal('parse_method_params insertUser count', #insert_params, 1)
support.expect_equal('parse_method_params insertUser type', insert_params[1].type, 'User')
support.expect_equal('parse_method_params insertUser name', insert_params[1].name, 'user')

local multiple_params = my_test.parse_method_params(mapper_path, 'selectUsers')
support.expect_equal('parse_method_params selectUsers count', #multiple_params, 2)
support.expect_equal('parse_method_params selectUsers [1] name', multiple_params[1].name, 'status')
support.expect_equal('parse_method_params selectUsers [2] name', multiple_params[2].name, 'role')

-- Test extract_model_fields
local fields = my_test.extract_model_fields(model_path)
support.expect_equal('extract_model_fields fields count', #fields, 3)
support.expect_true('extract_model_fields contains id', vim.tbl_contains(fields, 'id'))
support.expect_true('extract_model_fields contains username', vim.tbl_contains(fields, 'username'))
support.expect_true('extract_model_fields contains email', vim.tbl_contains(fields, 'email'))
support.expect_true('extract_model_fields serialVersionUID is ignored', not vim.tbl_contains(fields, 'serialVersionUID'))

-- Cleanup
vim.fn.delete(temp_dir, 'rf')

support.flush()
