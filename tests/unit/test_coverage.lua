local bootstrap = require("tests.support.bootstrap")
local coverage = require("crap4lua.coverage")
local harness = require("tests.support.harness")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local function _test_coverage_collect_tracks_only_tracked_sources_and_accumulates_hits()
  helpers.with_temp_fixture({
    ["support/untracked.lua"] = table.concat({
      "local helper = {}",
      "",
      "function helper.bump(flag)",
      "  if flag then",
      "    return 10",
      "  end",
      "  return 20",
      "end",
      "",
      "return helper",
    }, "\n"),
    ["src/tracked.lua"] = table.concat({
      "local helper = assert(loadfile(" .. string.format("%q", "TMP_ROOT/support/untracked.lua") .. "))()",
      "local tracked = {}",
      "",
      "function tracked.run(flag)",
      "  local total = helper.bump(flag)",
      "  if flag then",
      "    total = total + 1",
      "  end",
      "  return total",
      "end",
      "",
      "return tracked",
    }, "\n"),
  }, function(tmp_root)
    local tracked_path = tmp_root .. "/src/tracked.lua"
    local support_path = tmp_root .. "/support/untracked.lua"
    local content = assert(io.open(tracked_path, "rb"))
    local text = content:read("*a")
    content:close()
    assert(require("crap4lua.common").write_file(tracked_path, text:gsub("TMP_ROOT/support/untracked.lua", support_path)))

    local tracked = assert(loadfile(tracked_path))()
    local suites = {
      {
        name = "synthetic.coverage",
        tests = {
          { name = "truthy_first", run = function() helpers.assert_eq(tracked.run(true), 11, "tracked fixture should take truthy branch") end },
          { name = "falsy", run = function() helpers.assert_eq(tracked.run(false), 20, "tracked fixture should take falsy branch") end },
          { name = "truthy_second", run = function() helpers.assert_eq(tracked.run(true), 11, "tracked fixture should allow repeated calls") end },
        },
      },
    }

    local result = coverage.collect({
      project_root = tmp_root,
      tracked_sources = { "src/tracked.lua" },
      lanes = { "unit" },
      adapter = {
        resolve_suites = function(lane, mode)
          helpers.assert_eq(lane, "unit", "coverage should request configured lane")
          helpers.assert_eq(mode, nil, "coverage should preserve explicit mode input")
          return suites, "synthetic"
        end,
        run = function(run_suites, opts)
          return harness.run_all(run_suites, opts)
        end,
        debug_api = debug,
      },
    })

    local tracked_hits = result.line_hits["src/tracked.lua"]
    assert(tracked_hits ~= nil, "tracked fixture should collect hit lines")
    assert(tracked_hits[5] == true, "tracked fixture should record helper call line")
    assert(tracked_hits[6] == true, "tracked fixture should record branch line")
    assert(tracked_hits[7] == true, "tracked fixture should record truthy branch body")
    assert(tracked_hits[9] == true, "tracked fixture should record return line")
    helpers.assert_eq(result.line_hits["support/untracked.lua"], nil, "untracked helper should not be recorded")
    helpers.assert_eq(result.lanes[1].total, 3, "synthetic coverage lane should report all executed cases")
  end)
end

local function _test_coverage_collect_uses_injected_debug_api_and_runner()
  local sethook_calls = {}
  local fake_debug = {
    sethook = function(hook, mask)
      sethook_calls[#sethook_calls + 1] = {
        hook = hook,
        mask = mask,
      }
    end,
    getinfo = function()
      return nil
    end,
  }

  local run_called = false
  local result = coverage.collect({
    project_root = helpers.fixture_path("basic_project"),
    tracked_sources = {},
    lanes = { "unit" },
    adapter = {
      resolve_suites = function()
        return {}, "synthetic_mode"
      end,
      run = function(suites, opts)
        run_called = suites ~= nil and opts.mode == "synthetic_mode"
        opts.before_case({ full_name = "synthetic.case" })
        opts.after_case({ full_name = "synthetic.case" }, true, nil, { lines = {} })
        return {
          total = 0,
          failures = {},
          failed = false,
        }
      end,
      debug_api = fake_debug,
    },
  })

  assert(run_called == true, "coverage should delegate through injected runner")
  helpers.assert_eq(#sethook_calls, 3, "coverage should set and clear hooks through injected debug api")
  helpers.assert_eq(sethook_calls[1].mask, "l", "coverage should install line hook mask")
  helpers.assert_eq(sethook_calls[2].mask, nil, "coverage should clear hook after case")
  helpers.assert_eq(sethook_calls[3].mask, nil, "coverage should clear hook after lane completion")
  helpers.assert_eq(result.lanes[1].mode, "synthetic_mode", "coverage should report injected lane mode")
end

return {
  name = "crap4lua.unit.coverage",
  tests = {
    { name = "coverage_collect_tracks_only_tracked_sources_and_accumulates_hits", run = _test_coverage_collect_tracks_only_tracked_sources_and_accumulates_hits },
    { name = "coverage_collect_uses_injected_debug_api_and_runner", run = _test_coverage_collect_uses_injected_debug_api_and_runner },
  },
}
