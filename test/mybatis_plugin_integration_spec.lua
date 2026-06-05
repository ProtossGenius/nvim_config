local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')

-- 1. Check plugin is loaded and config options are initialized correctly
local has_mybatis_xml, mybatis_xml = pcall(require, 'mybatis-xml')
support.expect_true('mybatis-xml plugin can be required', has_mybatis_xml)

local config = require('mybatis-xml.config')
support.expect_true('mybatis-xml configuration is initialized', config.options ~= nil)
support.expect_equal('mybatis-xml default auto_complete setting', config.options.auto_complete, true)
support.expect_equal('mybatis-xml default virtual_java setting', config.options.virtual_java.enabled, true)

-- 2. Check user commands are registered
local commands = vim.api.nvim_get_commands({})
support.expect_true('DatasourceSync user command is registered', commands.DatasourceSync ~= nil)

-- 3. Check utilities are loaded and functional
local util = require('mybatis-xml.util')
support.expect_equal('is_model_type returns true for non-primitive types', util.is_model_type('com.example.User'), true)
support.expect_equal('is_model_type returns false for primitive types', util.is_model_type('String'), false)

-- 4. Check XML buffer detection setup
support.reset({
  '<?xml version="1.0" encoding="UTF-8" ?>',
  '<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "http://mybatis.org/dtd/mybatis-3-mapper.dtd">',
  '<mapper namespace="com.example.UserMapper">',
  '</mapper>'
}, 'xml', 'xml')

support.expect_true('mybatis-xml detects valid mybatis mapper xml buffer', util.is_mybatis_mapper(0))

support.flush()
