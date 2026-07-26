---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

**Default plan mode: RTL / Hardware Design** (Verilog/SystemVerilog). For software projects (Python/JS/etc), adjust task structure accordingly — see "Software Mode" sections below.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `superpowers:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Plan Mode: RTL / Hardware Design (Default)

For RTL design projects (Verilog/SystemVerilog/VHDL), use this plan structure:

### Module Dependency Analysis First

Before defining tasks, list all modules and their dependencies:

```text
Module dependency order:
1. <sync_module>, <basic_gate>              ← 叶子模块（无内部依赖）
2. <bus_interface>                           ← 依赖同步器
3. <regfile>                                 ← 依赖总线接口
4. <data_path_module_a>, <data_path_module_b> ← 可以与前序并行
5. <ctrl_module_a>, <ctrl_module_b>           ← 依赖数据通路
6. <fsm_module>                              ← 依赖控制模块
7. <dma_module>, <calib_module>              ← 依赖 FSM
8. <top_module>                               ← 顶层，依赖所有子模块
```

并行路径可同时开发，串行路径需等前置完成。

### RTL Task Granularity

Each task should be self-contained and independently verifiable:

| 阶段 | 粒度 | 验证方法 |
|:--|:--|:--|
| 叶子模块 | 1 模块 / task | 单独 lint + 基本仿真 |
| 非叶子模块 | 1 模块 / task | lint + 连接检查 |
| 顶层集成 | 1 task | lint + 集成仿真 |
| debug & 覆盖率 | 单独 task | 仿真迭代 |

### Task Structure for RTL

```markdown
### Task N: [Module Name] RTL Implementation

**Files:**
- Create: `<rtl_dir>/<module>.v`
- Create: `<tb_dir>/<module>/tb_<module>.v`（可选）
- Modify: `<rtl_dir>/filelist.f`（添加新文件）

- [ ] **Step 1: Read spec and understand the module**
  Review spec and architecture docs for interface and timing.

- [ ] **Step 2: Generate RTL code**
  Call /rtl-generator with the module specs.

- [ ] **Step 3: Run lint**
  Run: `<lint_command>` (e.g., `make lint`)
  Expected: PASS (no errors, no warnings)

- [ ] **Step 4: Run basic validation**
  Run: `<sim_command>` (e.g., `make sim`)
  Check simulation log for basic functionality.

- [ ] **Step 5: Commit**
  ```bash
  git add <rtl_dir>/<module>.v <rtl_dir>/filelist.f
  git commit -m "feat: add <module> module"
  ```
```

### RTL-Specific Planning Inputs

- Module hierarchy and dependency graph
- Clock domain definition
- Interface protocol (APB / AHB / AXI)
- Register map
- Key timing constraints (latency, handshake timeout, clock frequencies)

### File Structure for RTL Projects

- `rtl/<module>/` — RTL source files
- `tb/<module>/` — testbench files per module
- `sim/log/` — simulation logs (timestamped)
- `spec/` — specifications
- `doc/design/` — architecture documentation

Each file should have one clear module responsibility. Follow existing naming conventions in the project.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Task Granularity

In RTL mode, each task = one module (hours per module, see granularity table above).
In software mode, each step should be one actionable unit with a clear pass/fail outcome:
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Remember
- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, offer execution choice:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use superpowers:executing-plans
- Batch execution with checkpoints for review
