## 0.3.0

- Logger 回调改为在 RefCounted 上 Mutex 入队，主线程出队（避免工作线程访问 Node）。
- 修复父节点 Reparent 后不再捕获：`enter_tree` 重新 `OS.add_logger` 和 UI 不刷新：`log_added` 在 `enter_tree` 重连。

## 0.2.0

- 不再限制 warning 和 error 在 logger 内显示的堆栈数量
- 为 UI 添加默认主题
- bug 修复

## 0.1.0

- 基础自定义 Logger + 游戏内浮层。
