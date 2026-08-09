# crap4lua

`crap4lua` 是纯 Lua 的 CRAP（Change Risk Anti-Patterns，变更风险反模式）热点分析工具，
面向 Lua 代码。它通过 luacheck 的真实 Lua AST 计算圈复杂度，
从宿主测试运行产出的标准 `luacov.report.out` 中读取行覆盖率，
并生成 JSON 报告。

库模块位于 `src/` 下，自包含：不硬编码任何宿主专属路径或默认值。
宿主通过配置文件和一个薄入口脚本接入自己的 adapter 和默认值。

## CLI

库本身不附带可执行文件；宿主提供一个小的入口脚本（见下文"接入新项目"）。
假设该脚本名为 `crap.lua`：

```sh
lua crap.lua report [--lane NAME] [--out FILE] [--top N]
lua crap.lua collect [--lane NAME] --out FILE
lua crap.lua dry-run [--lane NAME]
lua crap.lua summary --in-json FILE [--tier-config FILE] [--gate] [--gate-threshold N]
```

`--gate` 在任一覆盖率分档不达标，或报告中的最大 CRAP 值超过
`--gate-threshold`（默认 **5.0**）时，以退出码 `2` 退出。

## 上游对齐（Upstream Alignment）

`crap4lua` 遵循"Lua 忠实实现上游规格"的总纲：crap4clj / crap4go / crap4java
完全一致的部分即为规格，逐字照抄；任何不同之处均为有意偏离，在此记录，并附理由。
跨仓决策以 ADR 形式存放在 luatools notes 仓（`projects/luatools/docs/adr/`）。

**对齐不变量**

- CRAP 公式 `CC² × (1 − cov)³ + CC`；覆盖率缺失时得分为空，显示为 `N/A`
  ——绝不当作 0（JSON 中为 `null`，排序沉底）。
- 风险带 `1–5 low / 5–30 moderate / 30+ high`。
- 五阶段骨架：查找源文件 → 解析函数边界 → 计算圈复杂度
  → 将覆盖率归因到函数 → 排序输出。
- `collect` 在重新生成前删除残留的覆盖率产物。
- 覆盖率仅来自解析生态标准工具的固定产物 ——**luacov** 是唯一覆盖率路径
  （ADR-0003；本地的 `debug.sethook` adapter 契约已移除）。
- 圈复杂度基于真实 Lua AST 计算（ADR-0001：通过 LuaRocks 安装的 luacheck
  parser 取代 `luac -p -l` 字节码操作码计数）。

**有意偏离**

- JSON 报告输出（三个上游均仅输出文本表格）——供 CI 与可视化消费。
- 命令拆分为 `collect / report / summary / dry-run`，而非单次端到端
  analyze 运行。
- `summary --gate` 质量门禁 —— crap4java 退出码 2 门禁的正确移植，
  但阈值**可配置**（默认 5.0；java 硬编码 8.0，已作为教训记录在上游）。

**破坏性变更**：风险带收紧（5 vs 8）、luacov 唯一覆盖率路径、门禁退出码/
阈值语义，均会改变宿主可见行为——完整列表见"兼容性说明"。

## 宿主 Adapter 契约

宿主提供一个 adapter table（通常通过配置文件中引用的一个 Lua 文件），
将分析器桥接到宿主的测试运行器。adapter 的唯一覆盖率相关义务：
**在 luacov 下运行测试套件，使标准的 `luacov.report.out` 出现在
`opts.report_path` 处**。crap4lua 自行解析该产物；不再有进程内
覆盖率机制（旧的 `debug.sethook` 契约已移除，ADR-0003）。
`collect` 在运行测试前删除所有残留报告。

```lua
return {
  -- 必需：为某个 lane 解析测试套件。返回 suites, mode。
  resolve_suites = function(lane, mode)
    return {
      {
        name = lane,
        tests = {
          { name = "example", run = function() end },
        },
      },
    }, mode
  end,
  -- 必需：在 luacov 下运行套件，并在 opts.report_path 处留下
  -- luacov.report.out。接收 silent reporter，且
  -- raise_on_failure = false。
  run = function(suites, opts)
    -- 例如：任何能在 opts.report_path 处产出标准报告的接线，
    -- 如用 `lua -lluacov` 运行套件并调用 `luacov`。
    return { total = 0, failed = false, failures = {} }
  end,
  -- 可选：供 `dry-run` 列出某个 lane 的 spec/测试文件。
  discover_specs = function(lane)
    return { "tests/example_test.lua" }
  end,
}
```

如果运行后不存在报告，则覆盖率**不可用**：每个 CRAP 分数为 `null`
（绝不当作 0），显示为 `N/A`，排序沉底。

### 真实 luacov 输出格式（parser 契约）

crap4lua 解析 luacov 的**默认 reporter** 输出（即不带自定义 reporter
配置时 `luacov` 产出的格式）。adapter-runner 负责产出与此一致的格式。
以下为对照真实 luacov 0.17.0 输出验证的关键特征：

- **分段结构**：每个源文件独占一个块，由 78 个 `=` 字符组成的
  分隔线（`^=+$`）界定。
  ```
  ==============================================================================
  <luacov 所见的路径>
  ==============================================================================
  ```
- **命中计数列**：右对齐；宽度随最大命中数增长（最小 2 个字符，
  以便容纳 `*0`）。该列后跟一个分隔空格，然后是**原样**的源代码行
  （包括其原始缩进）。
- **未覆盖的可执行行**：显示为 `*0`，位于计数列位置——无前导空格。
  示例：`*0     return 0`。
- **不可执行行**（空行、`end`、`else`、注释）：无计数前缀——计数列为空
  （填充空格），然后是分隔空格，再是源代码行。这些行使行号递增，但
  **不**记录为可执行行。
- **Summary 段**：始终是报告中的最后一个块，以 `Summary` 作为"路径"名
  标头。crap4lua 遇到 `Summary` 即停止解析——其下方的覆盖率表格不被消费。
- **路径形态**：luacov 以 `require()` 时所见的路径记录——可能是
  **相对路径**（如 `src/foo.lua`）或**绝对路径**（如
  `/Users/.../src/foo.lua`）。crap4lua 在采集时将两者统一规范化为
  相对于项目根的 key。

### 为 Lua 5.4 安装 luacov

adapter-runner 必须用 luacov 插桩测试运行，然后调用 `luacov` 命令行工具
生成 `luacov.report.out`。Lua 5.4（唯一支持的运行时）的安装方法：

```sh
luarocks --lua-version=5.4 --lua-dir=/opt/homebrew/opt/lua@5.4 install luacov
```

使 `require("luacov")` 在 `lua5.4` 下生效：

```sh
export LUA_PATH="/Users/$USER/.luarocks/share/lua/5.4/?.lua;$LUA_PATH"
```

典型的 adapter `run()` 实现：

```lua
run = function(suites, opts)
  -- 1. 在 luacov 下运行测试套件（产出 luacov.stats.out）：
  os.execute("cd " .. project_root .. " && lua5.4 -lluacov test_runner.lua")

  -- 2. 生成报告（读取 luacov.stats.out，写入 luacov.report.out）：
  os.execute("cd " .. project_root .. " && luacov")

  -- 3. 将报告移动到 crap4lua 期望的位置：
  os.rename(project_root .. "/luacov.report.out", opts.report_path)

  return { total = N, failed = false, failures = {} }
end
```

crap4lua 的 `collect` 在调用 `run()` 前会删除所有残留的
`luacov.report.out`，因此 adapter 无需关心遗留产物。

## 配置格式

宿主放置一个 `crap4lua.config.lua`（任意路径均可；通过 `--config` 传入）：

```lua
return {
  project_name = "Example App",
  project_root = ".",
  source_roots = { "src" },
  coverage = {
    lanes = { "unit" },
    mode = "example",
    adapter = "adapter.lua", -- 相对于配置文件的路径，
                             -- 或内联 table/function
    report = "luacov.report.out", -- 可选；默认为 project_root 下
  },
}
```

## 接入新项目（eggy）

新宿主项目（代号 "eggy"）无需修改本仓库即可接入：

1. 引入库，例如作为 git submodule 或固定版本的 toolcache checkout，放在
   `vendor/crap4lua/`。
2. 在 eggy 仓库根目录添加 `crap4lua.config.lua`（见"配置格式"），
   将 `source_roots` 指向 eggy 的 Lua 源码。
3. 在配置文件旁编写 `adapter.lua`，基于 eggy 的测试运行器实现上述
   adapter 契约。
4. 在 eggy 仓库根目录添加薄入口脚本 `crap.lua`：

   ```lua
   package.path = "vendor/crap4lua/src/?.lua;" .. package.path
   os.exit(require("crap4lua.cli").run(arg, {
     command_name = "crap.lua",
     default_config = "crap4lua.config.lua",
   }))
   ```

   `cli.run(args, env)` 返回进程退出码。`env` table 允许宿主注入所有默认值；
   支持的 key：

   - `command_name` —— 在 usage/help 文本中显示的命令名。
   - `default_config` —— 省略 `--config` 时使用的配置路径。
   - `default_report_out` —— 省略 `--out` 时使用的报告路径
     （默认 `"tmp/crap_report.json"`；`tmp/...` 解析到 tmp 根目录下）。
   - `default_tier_config` —— `summary` 省略 `--tier-config` 时的分档配置。
   - `default_top` —— `--top` 的默认值。
   - `default_gate_threshold` —— `summary --gate` 的 max-CRAP 门禁阈值
     （默认 `5.0`）。
   - `tmp_root` / `tmp_env_var` —— `tmp/...` CLI 路径的解析根目录
     （默认：系统临时目录）。
   - `cwd`、`stdout`、`stderr` —— I/O 重载（用于嵌入/测试）。

5. 运行 `lua crap.lua report --out tmp/crap_report.json`。

如需编程式调用，`crap4lua.bridge` 暴露了 `bridge.collect(opts, env)` 和
`bridge.write_collect_json(opts, env)`，返回 `result, err` 而非写入流。

## 兼容性说明

- **破坏性变更**：风险带现为上游的
  `1–5 low / 5–30 moderate / 30+ high`（原为 `8+ warning / 30+ critical`）；
  JSON summary 字段 `critical_count`/`warning_count` 更名为
  `high_count`/`moderate_count`，并新增 `na_count`。`--gate` 触发时退出码为
  `2`（原为 `1`），且现在同时检查 max CRAP 是否超过 `--gate-threshold`
  （默认 5.0）。
- **破坏性变更**：`debug.sethook` adapter 覆盖率契约已移除。
  adapter 必须在 luacov 下运行测试并产出 `luacov.report.out`；
  `debug_api` 及 `before_case`/`after_case` 覆盖率钩子不再存在。
  无可度量覆盖率的函数现在报告 `crap: null`（N/A，排序沉底），
  而非以 0% 覆盖率计分。
- **破坏性变更**：圈复杂度来自 luacheck AST，而非 `luac -p -l`；
  不再需要 `luac`，`env.luac_cmd` 配置项已移除。请通过 LuaRocks 安装
  luacheck。每个函数的 `decision_line_count` JSON 字段已移除（AST
  复杂度没有按行归因的决策列表）。
- 未配置 lane 且未通过 `--lane` 传入时的回退 lane 名称为
  `"default"`（原为 `"behavior"`，这是原始宿主的残余）。
  仅影响依赖回退值的运行；显式 `--lane` / `coverage.lanes` 行为不变。
- 未识别的 CLI 标志现在向 stderr 输出错误并以退出码 1 退出，
  而非抛出未捕获的 Lua 错误。
- 本 README 旧版中出现的 `viewer` 命令未由仓内 CLI 实现，已从文档中移除。

## 运行要求

- Lua 5.4
- [luacheck](https://github.com/lunarmodules/luacheck)（`luarocks install luacheck`）
- 宿主测试可在 [luacov](https://github.com/lunarmodules/luacov) 下运行
  （仅覆盖率路径需要；复杂度分析无需此项，缺覆盖率时分数为 N/A）
- [luaunit](https://github.com/bluebird75/luaunit)（仅运行本仓测试套件需要；
  `luarocks --lua-version=5.4 --lua-dir=/opt/homebrew/opt/lua@5.4 install luaunit`）

## 测试

测试套件基于 luaunit（4lua 工具链统一测试框架，ADR-0005），入口为
`tests/run.lua`——自动发现 `tests/unit/test_*.lua` 并在单个 luaunit
套件下运行。

```sh
make test            # 使用 Lua 5.4（/opt/homebrew/opt/lua@5.4/bin/lua5.4）
make test LUA=lua    # 如需覆盖解释器
```

---

## 中文文档

`crap4lua` 是纯 Lua 的 CRAP 热点分析工具。它用 luacheck 的 AST 计算圈复杂度，
从宿主测试运行产出的标准 `luacov.report.out` 解析行覆盖率（ADR-0003：luacov 是唯一
覆盖率路径，旧的 debug.sethook adapter 契约已移除），并生成 JSON 报告。
库本身不含任何宿主专属路径；接入方式见上文"接入新项目（eggy）"
一节：宿主需提供 config 文件、adapter 和一个薄入口脚本，并以 luarocks 安装 luacheck。

破坏性变更：风险带对齐上游 `1–5 low / 5–30 moderate / 30+ high`；
`--gate` 触发时退出码 2，并检查 max CRAP 是否超过 `--gate-threshold`（默认 5.0）；
缺失覆盖率的函数 CRAP 为 `null`（N/A 沉底，绝不当 0）。
