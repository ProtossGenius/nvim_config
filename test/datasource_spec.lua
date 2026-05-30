local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local datasource = require('user.datasource')

-- 1. Test M.snake_to_camel
support.expect_equal('snake_to_camel simple', datasource.snake_to_camel('user_name'), 'userName')
support.expect_equal('snake_to_camel uppercase', datasource.snake_to_camel('CREATED_AT'), 'createdAt')
support.expect_equal('snake_to_camel single word', datasource.snake_to_camel('id'), 'id')
support.expect_equal('snake_to_camel empty', datasource.snake_to_camel(''), '')

-- 2. Test M.mysql_type_to_java
support.expect_equal('mysql_type_to_java varchar', datasource.mysql_type_to_java('varchar(64)'), 'String')
support.expect_equal('mysql_type_to_java bigint', datasource.mysql_type_to_java('bigint(20) unsigned'), 'Long')
support.expect_equal('mysql_type_to_java datetime', datasource.mysql_type_to_java('datetime'), 'Date')
support.expect_equal('mysql_type_to_java decimal', datasource.mysql_type_to_java('decimal(10,2)'), 'BigDecimal')

-- 3. Test M.mysql_type_to_jdbc
support.expect_equal('mysql_type_to_jdbc varchar', datasource.mysql_type_to_jdbc('varchar(64)'), 'VARCHAR')
support.expect_equal('mysql_type_to_jdbc bigint', datasource.mysql_type_to_jdbc('bigint'), 'BIGINT')
support.expect_equal('mysql_type_to_jdbc datetime', datasource.mysql_type_to_jdbc('datetime'), 'TIMESTAMP')

-- 4. Create temp files to test find_table_name, parse_resultmap, parse_model_fields, and apply_fix
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local model_path = temp_dir .. '/User.java'
local mapper_xml_path = temp_dir .. '/UserMapper.xml'

vim.fn.writefile({
  'package com.example.model;',
  'import javax.persistence.Table;',
  'import lombok.Data;',
  '',
  '@Table(name = "t_user")',
  '@Data',
  'public class User {',
  '    private Long id;',
  '    private String userName;',
  '}',
}, model_path)

vim.fn.writefile({
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<mapper namespace="com.example.mapper.UserMapper">',
  '    <resultMap id="BaseResultMap" type="com.example.model.User">',
  '        <id column="id" property="id" jdbcType="BIGINT"/>',
  '        <result column="user_name" property="userName" jdbcType="VARCHAR"/>',
  '    </resultMap>',
  '</mapper>',
}, mapper_xml_path)

-- Test M.find_table_name
local table_name_model = datasource.find_table_name(model_path, { class = 'Table', field = 'name' })
support.expect_equal('find_table_name from model annotation', table_name_model, 't_user')

-- Test M.parse_resultmap
local entries, metas = datasource.parse_resultmap(mapper_xml_path)
support.expect_equal('parse_resultmap metas count', #metas, 1)
support.expect_equal('parse_resultmap metas type', metas[1].type, 'com.example.model.User')
support.expect_equal('parse_resultmap entries count', #entries, 2)
support.expect_equal('parse_resultmap entries[1] column', entries[1].column, 'id')
support.expect_equal('parse_resultmap entries[2] property', entries[2].property, 'userName')

-- Test M.parse_model_fields
local fields, has_data = datasource.parse_model_fields(model_path)
support.expect_equal('parse_model_fields has_data annotation', has_data, true)
support.expect_equal('parse_model_fields fields count', #fields, 2)
support.expect_equal('parse_model_fields fields[1] name', fields[1].name, 'id')
support.expect_equal('parse_model_fields fields[2] type', fields[2].type, 'String')

-- 5. Test M.compute_diff
local db_columns = {
  { name = 'id', type = 'bigint' },
  { name = 'user_name', type = 'varchar(64)' },
  { name = 'email', type = 'varchar(128)' }, -- missing in both model and resultMap
}

local diff = datasource.compute_diff(db_columns, entries, fields)
support.expect_equal('compute_diff missing in resultMap count', #diff.missing_in_resultmap, 1)
support.expect_equal('compute_diff missing in resultMap column', diff.missing_in_resultmap[1].column, 'email')
support.expect_equal('compute_diff missing in model count', #diff.missing_in_model, 1)
support.expect_equal('compute_diff missing in model name', diff.missing_in_model[1].name, 'email')

-- Cleanup
vim.fn.delete(temp_dir, 'rf')

support.flush()
