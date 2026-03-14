# crap4lua 重构方案：Lua 仅作为脚本接入，主架构改为 Go

## 目标

将 `crap4lua` 重构为 **Go-first** 架构：

- **Lua 仅负责脚本接入**
  - 加载 `crap4lua.config.lua`
  - 加载并调用宿主 adapter
  - 使用 `debug.sethook` 收集覆盖率
- **Go 负责其余全部主流程**
  - CLI 参数解析
  - 命令调度
  - report 请求/响应协议
  - 源码扫描
  - `luac` 输出解析
  - CRAP 指标计算
  - viewer 产物生成
  - 缓存与摘要输出

该方案的重点不是“完全移除 Lua”，而是把 Lua 收敛为 **bridge / adapter runtime**，让 Go 成为真正的产品主入口与核心实现。

---

## 当前状态评估

当前仓库已经完成了部分 Go 化，主要包括：

- `cmd/crap4lua-go/main.go`
- `internal/analyzer/analyzer.go`
- `internal/ipc/types.go`
- `internal/viewer/viewer.go`

这意味着以下能力已经由 Go 实现：

- report 命令主流程
- viewer 输出主流程
- report JSON 类型定义
- CRAP 核心分析
- viewer 静态资源写出

当前仍由 Lua 承担的职责包括：

- `lib/crap4lua/cli.lua`
  - CLI 参数解析与命令分发
- `lib/crap4lua/report.lua`
  - coverage 结果与 Go report 引擎衔接
- `lib/crap4lua/viewer.lua`
  - viewer 包装层
- `lib/crap4lua/json_reader.lua`
- `lib/crap4lua/json_writer.lua`
- `lib/crap4lua/common.lua`
  - 大量通用工具函数
- `lib/crap4lua/config.lua`
  - 配置加载
- `lib/crap4lua/coverage.lua`
  - coverage 收集

其中，真正必须保留在 Lua 的只有：

1. **Lua config 执行**
2. **Lua adapter 执行**
3. **Lua runtime coverage hook**

---

## 重构原则

### 1. Go 成为唯一主入口
后续主入口应为：

- `crap4lua-go report ...`
- `crap4lua-go viewer ...`

Lua CLI 不再承担主产品入口职责。

### 2. Lua 只保留“不可替代”的运行时能力
Lua 层仅保留：

- 配置求值
- adapter 调用
- coverage line hit 采集

### 3. 以协议边界替代混合业务边界
Lua 与 Go 之间通过稳定 JSON 协议通信，而不是继续在 Lua 中拼装主业务逻辑。

### 4. 兼容性逐步退场
兼容旧用法可以保留一段时间，但最终应将 Lua CLI 降级为兼容包装或 bridge 工具，而不是主实现。

---

## 目标架构

### Go 侧职责

Go 负责：

- 主 CLI
- 参数校验
- 调用 Lua bridge
- 读取 bridge 输出
- 构建 report
- 输出 JSON
- 生成 viewer
- 控制退出码
- 输出 summary
- 后续缓存/增量分析优化

### Lua 侧职责

Lua 负责：

- 执行 `crap4lua.config.lua`
- 解析宿主 adapter
- 执行 coverage lanes
- 利用 `debug.sethook` 采集 hit lines
- 输出标准 coverage/config 结果给 Go

---

## 推荐目录收敛方向

### 保留
- `bin/crap4lua.lua`
- `lib/crap4lua/config.lua`
- `lib/crap4lua/coverage.lua`

### 新增
- `lib/crap4lua/bridge.lua`
  - Lua bridge 入口
  - 承担 config + coverage 输出职责
- `internal/bridge/`
  - Go 侧调用 bridge 的执行与协议封装

### 逐步弱化或移除
- `lib/crap4lua/cli.lua`
- `lib/crap4lua/report.lua`
- `lib/crap4lua/viewer.lua`
- `lib/crap4lua/json_reader.lua`
- `lib/crap4lua/json_writer.lua`

### 可拆分精简
- `lib/crap4lua/common.lua`
  - 保留最小 bridge 所需工具
  - 其余能力迁至 Go 后删除

---

## 新的职责分层

### Layer 1: Host runtime bridge (Lua)
职责：

- 加载配置
- 解析 adapter
- 跑测试
- 采集覆盖率
- 输出 JSON

输入：

- config path
- lane/mode/filter 选项
- project root override（可选）

输出：

- 标准化配置
- coverage line hits
- lane 执行结果

### Layer 2: Product engine (Go)
职责：

- CLI
- bridge 调用
- 分析
- report 生成
- viewer 生成
- exit code 决策

### Layer 3: Compatibility shell
职责：

- 保留旧命令兼容
- 打印迁移提示
- 转发到 Go 或 bridge

---

## 关键接口设计

## 一、Lua bridge 输出协议

建议 bridge 输出统一 JSON，包含：

- `project_root`
- `project_name`
- `source_roots`
- `coverage_result`
  - `line_hits`
  - `lanes`

示例结构：

{
  "project_root": "/abs/path/project",
  "project_name": "Example App",
  "source_roots": ["src"],
  "coverage_result": {
    "line_hits": {
      "src/sample.lua": {
        "3": true,
        "4": true
      }
    },
    "lanes": [
      {
        "lane": "unit",
        "mode": "example",
        "total": 12,
        "failed": false,
        "failure_count": 0,
        "failures": []
      }
    ]
  }
}

该结构应尽可能与当前 Go `ipc.ReportRequest` 中的字段对齐，减少转换层。

---

## 二、Go CLI 目标命令

### report
支持两类模式：

#### 模式 A：高层模式
直接读取 Lua config 并自动触发 bridge

示例：

- `crap4lua-go report --config examples/basic/crap4lua.config.lua --out tmp/report.json`
- `crap4lua-go report --config xxx --lane unit --top 20 --strict-tests`

#### 模式 B：底层模式
保持现有 JSON 请求模式

示例：

- `crap4lua-go report --request-json req.json --response-json resp.json`

这样可以兼顾人用 CLI 与内部集成场景。

### viewer
继续支持：

- `crap4lua-go viewer --in-json tmp/report.json --out-dir tmp/crap_view --open`

后续可新增：

- `crap4lua-go viewer --config xxx --out-dir ...`

若未提供 `--in-json`，则先自动跑 report，再产出 viewer。

---

## 三、Lua bridge 命令形态

建议 Lua bridge 至少支持一个稳定命令：

- `lua bin/crap4lua.lua collect --config <file> --out <json>`

或：

- `lua bin/crap4lua.lua bridge coverage --config <file> --out <json>`

该命令只做一件事：

- 输出标准化 config + coverage 结果 JSON

不负责 report 和 viewer。

---

## 分阶段实施方案

## Phase 1：Go 接管主 CLI

### 目标
将用户主工作流迁移到 Go，而不立即删除 Lua 现有包装层。

### 工作项
1. 扩展 `cmd/crap4lua-go/main.go`
   - 增加 `--config`
   - 增加 `--lane`
   - 增加 `--mode`
   - 增加 `--top`
   - 增加 `--strict-tests`
   - 增加 `--project-root`
2. 新增 Go 侧 bridge 调用模块
   - 执行 Lua
   - 获取 bridge 输出 JSON
   - 映射到 `ipc.ReportRequest`
3. 让 `report` 命令支持“config 驱动模式”
4. 保留现有 `--request-json` 低层接口不变

### 产出
- Go 成为主入口
- Lua CLI 仍可用，但不再是推荐入口

### 验收标准
- `crap4lua-go report --config ...` 可完成完整分析
- `crap4lua-go viewer --in-json ...` 行为不变
- 当前示例项目可跑通

---

## Phase 2：Lua 收缩为纯 bridge

### 目标
Lua 不再承担 report/viewer/CLI 主业务逻辑。

### 工作项
1. 新增 `lib/crap4lua/bridge.lua`
2. 将 `bin/crap4lua.lua` 改为只支持 bridge/compat 两类行为
3. 从 Lua 中移除 report/viewer 主流程
4. 将 JSON 协议输出固定为 bridge contract

### Lua 保留职责
- `config.load`
- `coverage.collect`
- bridge 组装输出

### 验收标准
- Lua bridge 可单独产出 coverage JSON
- Go 可完全依赖 bridge 完成 report
- Lua 层不再控制 report/viewer 主流程

---

## Phase 3：兼容层降级与代码清理

### 目标
清理不再必要的 Lua 中间层。

### 工作项
1. 废弃 `lib/crap4lua/report.lua`
2. 废弃 `lib/crap4lua/viewer.lua`
3. 废弃 `lib/crap4lua/cli.lua`
4. 删除不再需要的 JSON 工具
5. 精简 `common.lua`

### 兼容策略
可保留轻量 wrapper：

- 当用户执行旧命令时，打印迁移说明
- 内部转发到 Go 主命令

### 验收标准
- 仓库主实现逻辑集中在 Go
- Lua 只剩 bridge + runtime 接入能力
- 删除后测试全部通过

---

## 文件级改造建议

## 1. `cmd/crap4lua-go/main.go`
### 改造目标
从“底层二进制命令”升级为“产品主 CLI”。

### 建议内容
- 扩展 `report` 命令参数
- 新增 config 驱动路径
- 封装调用 Lua bridge
- 统一 exit code 行为
- 可补充 `collect` 子命令用于调试 bridge 输出

---

## 2. `internal/ipc/types.go`
### 改造目标
将 bridge contract 与 report contract 分层。

### 建议内容
新增类型：

- `BridgeCollectRequest`
- `BridgeCollectResponse`

其中 `BridgeCollectResponse` 可以直接包含：

- project info
- source roots
- coverage result

再由 Go 将其映射为 `ReportRequest`。

### 好处
- 解耦 Lua bridge 与 analyzer 输入
- 便于后续扩展 bridge 元数据

---

## 3. `internal/bridge/`
### 改造目标
新增 Go-Lua 调用层。

### 建议文件
- `internal/bridge/runner.go`
- `internal/bridge/types.go`

### 职责
- 定位 Lua 可执行程序
- 定位 bridge 脚本
- 生成临时文件
- 调用 Lua
- 读取 JSON
- 返回结构化结果

### 错误处理要求
- 明确区分：
  - Lua 不可用
  - bridge 调用失败
  - config 加载失败
  - adapter 运行失败
  - 输出 JSON 格式错误

---

## 4. `lib/crap4lua/config.lua`
### 改造目标
保留，但收敛为纯配置加载器。

### 保留
- `crap4lua.config.lua` 加载
- 相对路径解析
- adapter 加载

### 避免继续扩展
不要再在这里加入 report/viewer 业务逻辑。

---

## 5. `lib/crap4lua/coverage.lua`
### 改造目标
保留，作为 Lua runtime 核心。

### 保留
- tracked source 判断
- debug hook 安装
- lane 结果输出

### 可以优化
- 输出结构与 Go IPC 完全一致
- 错误消息更明确
- 对 adapter 缺失字段进行早失败

---

## 6. `lib/crap4lua/cli.lua`
### 改造目标
逐步废弃。

### 处理方式
短期：
- 保持可用
- 内部转发到 bridge 或 Go

中期：
- 标记 deprecated

长期：
- 删除

---

## 7. `lib/crap4lua/report.lua`
### 改造目标
删除主业务职责。

### 当前问题
它仍然是 Lua 主流程的一部分，而这与 Go-first 目标冲突。

### 处理建议
- Phase 1 暂时保留
- Phase 2 后由 Go 完全替代
- 最终删除或改为极薄兼容层

---

## 8. `lib/crap4lua/viewer.lua`
### 改造目标
删除主业务职责。

### 处理建议
与 `report.lua` 同步退场。

---

## 9. `lib/crap4lua/json_reader.lua` / `json_writer.lua`
### 改造目标
仅在 bridge 必须时保留，否则逐步移除。

### 建议
如果 bridge 仍需要 JSON 输出，可短期保留 `json_writer.lua`。
`json_reader.lua` 大概率可以移除，因为主 JSON 读取应改由 Go 完成。

---

## 10. `lib/crap4lua/common.lua`
### 改造目标
拆分“桥接必需”与“历史遗留工具”。

### 建议保留最小集合
- path normalize / resolve
- temp path
- read/write file
- run command
- path exists
- parent dir / join path

### 建议删除的方向
- 与旧 CLI / viewer / report 包装强耦合的能力
- 已被 Go 替代的复杂辅助逻辑

---

## 兼容性策略

## 兼容目标
保证已有使用方不会被一次性打断。

### 保留的兼容点
- `lua bin/crap4lua.lua report ...`
- `lua bin/crap4lua.lua viewer ...`

### 兼容实现建议
旧命令执行时：

1. 输出迁移提示
2. 内部转发到 `crap4lua-go`
3. 若 Go 不存在，再提供明确错误与构建建议

### 中长期
README 与文档统一切换为 Go CLI 优先。

---

## 测试策略

## 1. Go 单元测试
覆盖：

- bridge runner
- request mapping
- analyzer
- viewer
- exit code 逻辑

## 2. Lua 单元测试
保留最小测试面：

- config loader
- coverage collector
- bridge output correctness

## 3. 集成测试
重点验证以下链路：

### 用例 A：Go report 直跑 config
- 给定 fixture config
- Go 调 Lua bridge
- Go 输出 report JSON
- 校验 metadata / summary / functions

### 用例 B：Go viewer 读取 report
- 输入 report JSON
- 输出 viewer bundle
- 校验 `index.html` 与数据文件存在

### 用例 C：严格模式退出码
- lane failed
- `--strict-tests`
- 进程返回非零

### 用例 D：兼容 Lua 命令转发
- 旧 Lua CLI 仍可触发成功流程

---

## 文档改造计划

## README
需要改成：

- Go CLI 为主
- Lua bridge 为集成层
- 明确“Lua 仅负责脚本接入”

### 新文案核心
- 主命令：`crap4lua-go`
- Lua config/adapter 仍保留
- Lua bridge 只负责 coverage collection

## docs/migration.md
补充：

- 新旧架构对比
- 主入口切换说明
- 兼容层保留周期
- 对宿主 adapter 编写者的影响

## docs/embedding.md
改成明确描述：

- 如何写 adapter
- 如何输出 coverage
- Go 如何调用 Lua bridge

---

## 风险与注意事项

## 1. 配置文件是 Lua，不是 JSON/YAML
这决定了 Go 不应尝试直接原生解析配置。
应坚持“Lua 求值，Go 消费结果”的边界。

## 2. Coverage 无法脱离 Lua runtime
只要使用 `debug.sethook`，coverage 采集就必须在 Lua 里运行。
这一层不应勉强迁到 Go。

## 3. Adapter 是宿主集成边界
宿主项目对 suite discovery / runner 的掌控应继续留在 Lua。
不要把宿主测试执行逻辑强行泛化到 Go。

## 4. 兼容期内可能出现双入口混乱
需要在 README、help、错误信息中明确：
- 推荐入口是 Go
- Lua 是 bridge / compatibility layer

---

## 里程碑计划

## Milestone 1：Go 成为推荐入口
- `crap4lua-go report --config` 可用
- `crap4lua-go viewer --in-json` 可用
- README 切换为 Go-first

## Milestone 2：Lua bridge 固化
- Lua 只负责 config + coverage
- 新 bridge contract 稳定
- 旧 Lua report/viewer 不再承担主流程

## Milestone 3：清理历史包装层
- 删除或废弃旧 Lua CLI/report/viewer
- 精简 common/json 辅助模块
- 测试与文档完成收敛

---

## 最终预期结果

重构完成后，系统应满足以下形态：

### 用户视角
- 主命令是 `crap4lua-go`
- Lua 仍然能写 config 和 adapter
- 功能行为更稳定、性能更好、边界更清晰

### 工程视角
- Go 是主业务实现语言
- Lua 是必要的运行时接入层
- 跨语言边界变成稳定协议，而不是互相包裹的流程逻辑

### 长期收益
- 更清晰的维护边界
- 更容易扩展 CLI 和分析能力
- 更容易增加缓存、并发、增量分析、输出格式扩展
- 更容易向外部系统提供稳定 API/协议

---

## 建议执行顺序

1. 先实现 Go `report --config`
2. 再实现 Lua bridge 专用命令
3. 然后让 Go 通过 bridge 完成 coverage 收集
4. 再废弃 Lua report/viewer/cli 中间层
5. 最后清理 common/json 遗留工具与文档

---

## 简版结论

最终方向应明确为：

- **Lua：只做 config + adapter + coverage**
- **Go：做 CLI + analyzer + viewer + protocol + orchestration**

这是当前仓库最自然、风险最低、收益最大的重构路径。