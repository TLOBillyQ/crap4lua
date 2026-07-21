return {
  project_name = "Fixture App",
  project_root = ".",
  source_roots = { "src" },
  coverage = {
    lanes = { "unit" },
    mode = "fixture",
    adapter = "adapter.lua",
  },
}
