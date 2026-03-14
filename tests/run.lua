local bootstrap = require("tests.support.bootstrap")
local harness = require("tests.support.harness")

bootstrap.install_package_paths()

local suites = {
  require("tests.unit.test_report"),
  require("tests.unit.test_coverage"),
  require("tests.unit.test_config"),
  require("tests.unit.test_viewer"),
  require("tests.integration.test_cli"),
}

harness.run_all(suites)
