#!/usr/bin/env python3
# PreToolUse hook: warn before a destructive `git checkout` that discards
# working-tree changes, suggesting `git stash` instead.
# Non-blocking: prints a warning to stderr and exits 0, so the command still runs.
#
# Reproduces the three rules previously under the invalid "pre_tool_call" key:
#   git checkout -- <file>   -> 会永久丢失该文件的所有未提交修改
#   git checkout .           -> 会永久丢失所有未提交修改
#   git checkout ...         -> 确认要丢弃文件修改？
import sys
import json
import re

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cmd = data.get("tool_input", {}).get("command", "")

warn = None
if re.search(r"\bgit checkout --\s+\S", cmd):
    warn = ("[HOOK] git checkout -- <file> 会永久丢失该文件的所有未提交修改！"
            "如需临时还原验证请用 git stash push -m 'xxx' 替代")
elif re.search(r"\bgit checkout \.", cmd):
    warn = ("[HOOK] git checkout . 会永久丢失所有未提交修改！"
            "如需临时还原验证请用 git stash push -m 'xxx' 替代")
elif re.search(r"\bgit checkout\b", cmd):
    warn = "[HOOK] 确认要丢弃文件修改？临时验证请用 git stash push 替代 git checkout"

if warn:
    print(warn, file=sys.stderr)
sys.exit(0)
