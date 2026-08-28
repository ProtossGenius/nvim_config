local support = dofile(vim.fn.stdpath('config') .. '/test/spec_support.lua')
local search = require('user.java_class_search')

-- Clear state for deterministic testing
search._cache = {}
search._cache_set = {}
search._state = {
  package_priorities = {},
  prefix_associations = {},
}
search._state_loaded = true

-- 1. Test character matching rules
support.expect_true('char_matches lowercase matches lowercase', search._test.char_matches(('a'):byte(), ('a'):byte()))
support.expect_true('char_matches lowercase matches uppercase', search._test.char_matches(('a'):byte(), ('A'):byte()))
support.expect_true('char_matches uppercase matches uppercase', search._test.char_matches(('A'):byte(), ('A'):byte()))
support.expect_equal('char_matches uppercase does NOT match lowercase', search._test.char_matches(('A'):byte(), ('a'):byte()), false)
support.expect_true('char_matches dot matches dot', search._test.char_matches(('. '):byte(1), ('. '):byte(1)))

-- 2. Test subsequence matching with casing rules
-- User requirement: "spring 用spg也能够可以搜到"
local ok_spg, score_spg = search._test.match_subsequence('spg', 'spring')
support.expect_true('spg matches spring', ok_spg)

-- User requirement: "springframework. 也可以用spf.来匹配出来"
local ok_spf, score_spf = search._test.match_subsequence('spf.', 'springframework.')
support.expect_true('spf. matches springframework.', ok_spf)

-- User requirement: "aA 可以匹配 aA和AA，但是不可以匹配aa"
local ok_aA_aA = search._test.match_subsequence('aA', 'aA')
support.expect_true('aA matches aA', ok_aA_aA)

local ok_aA_AA = search._test.match_subsequence('aA', 'AA')
support.expect_true('aA matches AA', ok_aA_AA)

local ok_aA_aa = search._test.match_subsequence('aA', 'aa')
support.expect_equal('aA does NOT match aa', ok_aA_aa, false)

-- Test uppercase requirement
local ok_Aa_AA = search._test.match_subsequence('Aa', 'AA')
support.expect_true('Aa matches AA', ok_Aa_AA)

local ok_Aa_aa = search._test.match_subsequence('Aa', 'aa')
support.expect_equal('Aa does NOT match aa', ok_Aa_aa, false)

-- 3. Test caching & deduplication
search._test.add_to_cache({
  fqn = 'com.example.demo.service.UserService',
  container = 'com.example.demo.service',
  name = 'UserService',
  is_project = true,
  uri = 'file:///path/to/UserService.java',
})

search._test.add_to_cache({
  fqn = 'org.springframework.context.ApplicationContext',
  container = 'org.springframework.context',
  name = 'ApplicationContext',
  is_project = false,
  uri = 'jdt://contents/ApplicationContext.class',
})

search._test.add_to_cache({
  fqn = 'org.apache.commons.lang3.StringUtils',
  container = 'org.apache.commons.lang3',
  name = 'StringUtils',
  is_project = false,
  uri = 'jdt://contents/StringUtils.class',
})

-- Duplicate add should be ignored
local cache_count_before = #search._cache
search._test.add_to_cache({
  fqn = 'com.example.demo.service.UserService',
  container = 'com.example.demo.service',
  name = 'UserService',
  is_project = true,
})
support.expect_equal('Duplicate item is not added twice', #search._cache, cache_count_before)

-- 4. Test filtering and ranking
local results_user = search._test.filter_entries('User', search._cache, {})
support.expect_equal('Filter User finds UserService', results_user[1].name, 'UserService')

local results_app = search._test.filter_entries('app', search._cache, {})
support.expect_equal('Filter app finds ApplicationContext', results_app[1].name, 'ApplicationContext')

-- 5. Test package priority ranking
-- Initially, no package has priority. Let's add two classes with similar names in different packages.
search._test.add_to_cache({
  fqn = 'pkg.alpha.Helper',
  container = 'pkg.alpha',
  name = 'Helper',
  is_project = false,
})
search._test.add_to_cache({
  fqn = 'pkg.beta.Helper',
  container = 'pkg.beta',
  name = 'Helper',
  is_project = false,
})

-- Search 'Helper' before priority: alpha and beta have equal package score, sorted alphabetically
local helper_results = search._test.filter_entries('Helper', search._cache, {})
support.expect_equal('First Helper is alpha alphabetically', helper_results[1].container, 'pkg.alpha')

-- Now user selects pkg.beta.Helper -> boosts pkg.beta priority
search._test.record_selection('Helper', {
  fqn = 'pkg.beta.Helper',
  container = 'pkg.beta',
  name = 'Helper',
})

support.expect_equal('pkg.beta priority increased to 1', search._state.package_priorities['pkg.beta'], 1)

-- Re-running search for 'Helper' should now prioritize pkg.beta over pkg.alpha!
local helper_results_boosted = search._test.filter_entries('Helper', search._cache, search._state.package_priorities)
support.expect_equal('pkg.beta is now ranked first due to priority', helper_results_boosted[1].container, 'pkg.beta')

-- 6. Test search history prefix-to-package associations & ghost text suggestions
search._test.record_selection('spf.', {
  fqn = 'org.springframework.context.ApplicationContext',
  container = 'org.springframework.context',
  name = 'ApplicationContext',
})

local suggestion, count = search._test.get_prefix_suggestion('spf.')
support.expect_equal('get_prefix_suggestion for spf. returns org.springframework.context', suggestion, 'org.springframework.context')
support.expect_true('suggestion count is at least 1', count >= 1)

local suggestion_clean = search._test.get_prefix_suggestion('spf')
support.expect_equal('get_prefix_suggestion for spf without dot also matches', suggestion_clean, 'org.springframework.context')

-- 7. Test scanning project directory
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir .. '/src/main/java/com/demo/test', 'p')
local test_file = temp_dir .. '/src/main/java/com/demo/test/TestApp.java'
vim.fn.writefile({
  'package com.demo.test;',
  '',
  'public class TestApp {}',
}, test_file)

search._test.scan_project_classes(temp_dir)
local test_app_item = search._cache_set['com.demo.test.TestApp']
support.expect_true('scan_project_classes finds TestApp', test_app_item ~= nil)
support.expect_equal('TestApp container is com.demo.test', test_app_item.container, 'com.demo.test')
support.expect_equal('TestApp is_project is true', test_app_item.is_project, true)

-- 8. Test picker open and abort/close (Esc simulation)
local ok_picker, err_picker = pcall(function()
  search.search({
    attach_mappings = function(prompt_bufnr, map)
      vim.schedule(function()
        pcall(require('telescope.actions').close, prompt_bufnr)
      end)
      return true
    end
  })
  vim.wait(100)
end)
support.expect_true('Picker open and abort/close succeeds without error', ok_picker)

-- Clean up temp dir
vim.fn.delete(temp_dir, 'rf')

support.flush()
