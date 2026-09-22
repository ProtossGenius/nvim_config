-- Custom mason-registry "lua:" source.
--
-- mason.nvim resolves lua registries by requiring this module and expecting
-- it to return a table mapping package name -> module path containing the
-- actual RegistryPackageSpec. See mason-registry/sources/lua.lua.
return {
  jdtls = "user.mason_registry_jdtls_fix_spec",
}
