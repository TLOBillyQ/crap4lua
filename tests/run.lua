local bootstrap = require("tests.support.bootstrap")
local harness = require("tests.support.harness")

bootstrap.install_package_paths()

local suites = {
  require("tests.unit.test_bridge"),
  require("tests.unit.test_coverage"),
  require("tests.unit.test_config"),
}

harness.run_all(suites)
