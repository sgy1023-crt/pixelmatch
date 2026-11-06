# Pixelmatch SSIM 进度与交接

最近更新：2026-11-06（北京时间）。维护分支为 `codex/local-gaussian-ssim`。

| 内部计划 | 工作 | 状态 |
| --- | --- | --- |
| 11 月 6 日起 | 确认 11 月验收截止、入口和材料要求，定下 CLI 首版范围 | CLI 范围已定，正式验收安排待赛事群确认 |
| 11 月 9–11 日 | 两张 PNG → 局部 Gaussian SSIM → PNG 相似度图与 JSON | 11 月 6 日完成首版与本地验证 |
| 11 月 12–13 日 | 从干净检出复现 README 示例，保留输入、输出与测试证据 | 示例已备齐，待干净检出复跑 |
| 11 月 16–20 日 | 复跑测试，核对上游来源与许可证，锁定验收提交 | 待做 |
| 11 月 23–30 日 | 入口开放且材料齐备后提交，处理验收反馈 | 待正式通知 |

这是内部排期。若正式截止更早，优先前移可复现演示和验收自查。

## 2026-11-06

- 报名初审已通过，确认邮件要求继续围绕申报方向开发并保留可追踪的仓库记录。最终验收待办。
- P0 基线是 `978b468e2fe7bca90dc5d043e28022679079f8b1`。既有 SSIM 库计算、数值 map、灰度转换和三后端验证见 [P0 验证报告](docs/ssim-validation.md)。
- P1 增加独立的 MoonBit CLI 入口，首版用 JS 后端和 Node.js 运行。沿用 `mizchi/image` PNG 编解码及 P0 的 SSIM 与展示映射。
- 首版参数为 `ssim before.png after.png --output ssim-map.png`。正常输出为灰度 PNG 和一行 JSON，失败使用 stderr 和非零退出状态。
- README 已加入可复制的命令、样例分数和上游来源。输入与参考输出位于 `examples/ssim-cli/`。
- 样例实测分数为 `0.99843089310234`，输出 96×64 灰度相似度 PNG。独立解码检查确认未改动的角点为白色，变色区域更暗。
- JS、Wasm-GC、Native 的 `moon test --target <目标> --deny-warn` 和 `moon check --target <目标> --deny-warn` 通过。CLI Release 构建和 `node --test tools/ssim_cli_test.mjs` 通过，覆盖同图、局部变化、尺寸不匹配、无效 PNG 和目标路径不可写。
- 验证环境为 Windows、MoonBit CLI 0.1.20261028、Node.js 24.22.1。CLI 首版支持 Node.js，Wasm-GC 和 Native 的结果为库回归测试。
- 下一步从干净检出执行 README 命令，再根据正式通知准备验收提交。

后续每次更新本文件时，补上日期、实际改动、验证命令与结果、已知问题及下一步，并同步上表的状态。
