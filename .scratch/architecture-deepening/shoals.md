## Shoals
- [无头测试全绿不等于 GUI 模式安全](.scratch/architecture-deepening/issues/04-rendering-seam.md) — 渲染路径改动必须单独跑 gui 套件验证：OnChanged 无限递归只在 GUI 模式触发，无头测试全绿掩盖了它（GUI 套件挂死 27 分钟才定位）；修复 afe3566 确立的不变量是渲染只读状态、永不写 store，后续动渲染层别再让渲染回调写 store
- [CI upload-artifact 步骤挂死＝测试留下孤儿进程](https://github.com/JsonBorn98/AHKeyMap/pull/2) — 诊断签名：test 步骤秒过、summary 全 passed，挂死的是之后的 upload-artifact 步骤且产物创建正常＝integration 测试（最可能 hotkey_engine_state.test.ahk）在 CI 真实桌面留了不退出的 hook/timer/弹窗类孤儿进程，其继承句柄让 node 进程无法退出；本地沙箱复现不出（本地 3.5 秒全绿无残留），改 integration 测试时先在真实桌面查残留进程
