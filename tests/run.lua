local bootstrap = require("tests.bootstrap")
local harness = require("tests.TestHarness")

bootstrap.install_package_paths()

local suites = {
  require("tests.suites.contract"),
}

harness.run_all(suites)
