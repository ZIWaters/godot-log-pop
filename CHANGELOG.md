## 1.1.0

- Logger 回调改为在 RefCounted 上 Mutex 入队，主线程出队（避免工作线程访问 Node）。
- 修复父节点 Reparent 后不再捕获日志、UI 不刷新的问题。
- 不再限制 warning 和 error 在 logger 内显示的堆栈数量
- 为 UI 添加默认主题
- 其他 bug 修复

## 1.0.0

- 基础自定义 Logger + 游戏内浮层。
