# Pixelmatch SSIM 十一月验收说明草稿

整理日期为北京时间 2026-11-08，申报方向为“已有项目维护”。项目已通过报名初审，依据为参赛者提供的组委会邮件。本文按邮件中的项目完成度、代码质量、开源合规性及与 MoonBit 生态的相关性整理证据，正式验收提交、最终评定及材料格式待组委会通知确认。

项目名称为“Pixelmatch 局部 Gaussian SSIM 与逐像素相似度图”。公开 Fork 的默认分支为 `codex/local-gaussian-ssim`，当前草稿引用的已验证代码基线为 `a3af3df4143836bdd886dacce0e635dce48bee38`。最终验收提交将在正式提交前锁定。[公开仓库](https://github.com/sgy1023-crt/pixelmatch) · [成果分支](https://github.com/sgy1023-crt/pixelmatch/tree/codex/local-gaussian-ssim) · [已验证基线](https://github.com/sgy1023-crt/pixelmatch/commit/a3af3df4143836bdd886dacce0e635dce48bee38)

## 项目完成度与新增贡献

项目用于截图比较、视觉回归测试和图像质量分析。在 mizchi/pixelmatch 原有像素差异比较之外，新增局部 Gaussian SSIM，以连续数值描述空间相似度，并提供可运行的 PNG 命令行流程。[上游项目](https://github.com/mizchi/pixelmatch) · [需求 Issue #6](https://github.com/mizchi/pixelmatch/issues/6)

| 范围 | 实际交付 | 文件 |
| --- | --- | --- |
| P0 库能力 | 纯 MoonBit 局部高斯窗口、整体评分、逐像素 Double map、亮度／对比度／结构分量、灰度 Image 转换 | [SSIM 实现](../src/ssim.mbt)、[API 与数值约定](ssim.md) |
| 11 月新增使用流程 | 读取两张 PNG、调用 SSIM、写出灰度 PNG、向 stdout 输出 JSON，失败写 stderr 并返回非零状态 | [CLI 入口](../src/cmd/pixelmatch/main.mbt)、[使用说明](../README.md#compare-two-pngs-from-the-command-line) |
| 11 月新增工程验证 | 三后端库检查与测试、Node.js CLI 构建与端到端测试、README 样例复现及产物保存 | [CI 工作流](../.github/workflows/ci.yml)、[CLI 测试](../tools/ssim_cli_test.mjs) |
| 11 月工具链适配 | 三处类型派生声明迁移至 `#derive(...)`，支持 moonc 0.10.20 的严格警告检查 | [兼容性提交](https://github.com/sgy1023-crt/pixelmatch/commit/490f6c601e480be4efb365990ad2f542df559d26) |

上游既有的像素差异算法、图像类型、报告功能、C 桩及依赖 PNG 编解码能力沿用原作者成果。本人贡献范围为新增 SSIM 库、命令行接入、对应测试与文档，以及后续 CI 和工具链适配。Python 科学计算库用于生成和核对参考数值，源码归属与引用见数值文档。

### Git 提交与时间

下表使用北京时间。各行的 AuthorDate 与 CommitDate 相同，原始历史保留，可由链接中的提交核查。

| 时间（+08:00） | 提交 | 内容与贡献归属 |
| --- | --- | --- |
| 2026-10-31 23:59:46 | [e9f6384](https://github.com/sgy1023-crt/pixelmatch/commit/e9f638433f0a66c3e6423bb9ea4a1bb8ac98a9e0) | 为十一月赛事提前准备的 P0 核心、测试和文档，单列为十月底已完成基础 |
| 2026-11-01 00:00:50 | [978b468](https://github.com/sgy1023-crt/pixelmatch/commit/978b468e2fe7bca90dc5d043e28022679079f8b1) | 更正文档中的工程就绪与赛事验收措辞 |
| 2026-11-06 19:31:49 | [06d88af](https://github.com/sgy1023-crt/pixelmatch/commit/06d88af05f86f885a6caa7862201e74c021e1e6f) | 新增 PNG CLI、真实文件样例、端到端测试与使用说明 |
| 2026-11-06 19:32:32 | [59a2e40](https://github.com/sgy1023-crt/pixelmatch/commit/59a2e40af697d8e93cd711c5ef3131a151f9b4d6) | 记录干净克隆复现结果 |
| 2026-11-07 14:37:35 | [0d20e0c](https://github.com/sgy1023-crt/pixelmatch/commit/0d20e0c8ff89a75d4943b8ee4ed24d42567927d7) | 接入三后端与 CLI 的 GitHub CI |
| 2026-11-07 14:48:29 | [490f6c6](https://github.com/sgy1023-crt/pixelmatch/commit/490f6c601e480be4efb365990ad2f542df559d26) | 适配 MoonBit 0.10.20，更新公共接口文件与环境要求 |
| 2026-11-07 14:52:16、14:55:05 | [44eb356](https://github.com/sgy1023-crt/pixelmatch/commit/44eb356f05d2cc4ba0f45f83ea3e3e314b3ebb33)、[a3af3df](https://github.com/sgy1023-crt/pixelmatch/commit/a3af3df4143836bdd886dacce0e635dce48bee38) | 记录远端成功验证和推送自动触发证据 |

十一月实际新增功能以 PNG CLI 为起点，CI、兼容性适配及文档分别记录。P0 的十月底完成时间已在报名备注披露，其赛期归属留待赛事方认定。本文将既有基础与十一月工作分别列明，供验收核查。

## 代码质量与复现

当前源码需要 moonc 0.10.20 或更新版本。已记录的远端环境为 Linux、MoonBit CLI 0.1.20261104、moonc 0.10.20 与 Node.js 24.22.1。CI 使用官方 latest 安装入口，每次记录实际工具链版本。复现时先安装满足要求的工具链并将 `moon`、`node` 放入 PATH。[环境与运行说明](../README.md#compare-two-pngs-from-the-command-line)

以下命令在新目录检出上述已验证基线。该基线包含可运行实现与样例。

```sh
git clone --branch codex/local-gaussian-ssim --single-branch https://github.com/sgy1023-crt/pixelmatch.git pixelmatch-ssim
cd pixelmatch-ssim
git checkout --detach a3af3df4143836bdd886dacce0e635dce48bee38
moon version --all
node --version
moon update
moon run --target js src/cmd/pixelmatch ssim examples/ssim-cli/before.png examples/ssim-cli/after.png --output _build/ssim-map.png
```

两张输入均为 96×64 的合成 UI 样例，其中一个矩形的颜色不同。命令生成同尺寸、不透明的灰度 PNG，并输出下列 JSON。具体末位浮点显示以实际运行环境为准。

```json
{"ssim":0.99843089310234,"raw_ssim":0.99843089310234,"luminance":0.9994560289821766,"contrast":0.998979915928376,"structure":0.9999911836752656}
```

`ssim` 为裁剪到 [0,1] 的展示分，`raw_ssim` 保留原始有符号得分，三个分量为同一内域上的平均值。PNG 中越白表示越相似，逐像素值按 [0,1] 裁剪并映射为灰度。数值约定与参考图均可直接查看。[数值约定](ssim.md#numerical-contract) · [输入图一](../examples/ssim-cli/before.png) · [输入图二](../examples/ssim-cli/after.png) · [参考输出](../examples/ssim-cli/expected-map.png)

进一步复现 CLI 测试可执行以下命令。

```sh
moon build --target js --release --deny-warn src/cmd/pixelmatch
node --test tools/ssim_cli_test.mjs
```

2026-11-08 已按上述步骤在新目录检出指定基线并复现，CLI 测试 5/5 通过。生成 PNG 与参考图的 SHA-256 均为 `518692acff13021b4c1bd1ecbc7ae5e21fed958b8e2db4b928402d87a382fe36`。

| 检查 | 已记录结果 | 证据 |
| --- | --- | --- |
| JS、Wasm-GC、Native 库测试与严格检查 | 每目标 59/59，`--deny-warn` 通过 | [自动触发的 CI](https://github.com/sgy1023-crt/pixelmatch/actions/runs/42349058856) |
| PNG CLI 端到端测试 | 5/5，覆盖同图、局部变化、尺寸不匹配、无效 PNG 和目标路径不可写 | [测试脚本](../tools/ssim_cli_test.mjs)与同次 CI 的 PNG SSIM CLI 作业 |
| README 样例 | 干净克隆与远端检出均可复现，生成的 PNG 与参考图 SHA-256 一致 | 同次 CI 的 Reproduce README example 步骤 |
| 独立参考数值 | 12 组参考、1,539 个 map 像素，map 最大绝对误差约 8.33e-15 | [P0 验证快照](ssim-validation.md#numeric-comparison)、[参考元数据](ssim-reference.json) |

参考值采用 SciPy 的显式半径 Gaussian filter 和总体协方差计算，三个分量用直接二维加权中心矩核对，其中 8 组兼容案例另经 scikit-image 校验。普通 MoonBit 测试直接使用已入库的参考数据。CI 测试命令有 60 秒硬超时，工作流中三后端、CLI 及原有 Linux/macOS 性能作业共 6 个作业已全部成功。

CI 的 `ssim-cli-demo` 产物包含 PNG 和 JSON，当前所引用运行的产物保留至 2026-12-07。正式验收前可按实际需要重新运行并更新证据链接。[CI 产物入口](https://github.com/sgy1023-crt/pixelmatch/actions/runs/42349058856)

### 已记录的性能

以下为 P0 历史实测，环境为 i5-12450H、Node.js 24.22.1、默认 11×11／sigma 1.5，计时范围为 SSIM 库计算。图像准备在计时闭包之外。

| 图像尺寸 | 均值 |
| --- | --- |
| 200×200 | 4.25 ms |
| 1920×1080 | 225.34 ms |
| 3840×2160 | 1.40 s |

这些数值的测量条件、波动范围及数值存储估算保存在 P0 报告。CLI 的 PNG 解码、转换与编码会增加端到端成本。1080p／4K 的 79.94／318.08 MiB 是含两输入、map 与工作缓冲的数值存储估算，进程峰值 RSS 尚待测量。[性能与内存证据](ssim-validation.md#performance-and-memory)

## 开源合规性与来源

本项目沿用上游 Apache-2.0 许可证，仓库保留许可证文本、mizchi/pixelmatch 来源及其对 mapbox/pixelmatch 的移植说明。依赖版本列于 `moon.mod`。新算法按 SSIM 数学定义实现，数值参考来源、工具版本及生成方式列于 API 文档与参考元数据。[许可证](../LICENSE) · [README](../README.md) · [依赖声明](../moon.mod) · [参考来源](ssim.md#independent-reference)

项目使用 Codex 辅助实现、参考工具、测试、CI 和文档整理。参赛者负责理解技术路径、核对贡献边界、复现结果并对交付质量负责。验收时应能解释局部高斯窗口、亮度与透明度处理、原始分和展示分的区别，以及首版支持范围。

## 与 MoonBit 生态的相关性

SSIM 核心与 CLI 业务流程均由 MoonBit 实现，复用既有 Image 类型和 mizchi/image 编解码，提供库 API 及真实 PNG 输入输出。JS、Wasm-GC、Native 的库测试验证了多后端行为，Node.js CLI 为视觉回归场景提供直接可用的入口。

上游 Issue #6 所需的局部窗口、逐像素 map、整体分数、三个分量及 PNG 命令行流程已有对应实现。截至本草稿整理时，成果在公开 Fork 分支，上游 Issue 仍开放，尚未向上游创建 PR 或获得合并。后续协作按实际沟通与评审结果记录。[上游需求](https://github.com/mizchi/pixelmatch/issues/6) · [项目进度](../handoff.md)

## 首版边界与提交前待办

- CLI 首版运行于 Node.js，使用默认 11×11、sigma 1.5。自定义 window／sigma 由库 API 提供。
- 使用亮度通道，提供三个整体分量平均值。逐 RGB 通道 SSIM、MS-SSIM、逐像素分量图和彩色热力图留作后续范围。
- 输入尺寸须相同并容纳当前窗口，CLI 最小宽高均为 11。PNG 格式支持范围沿用 mizchi/image。
- Windows 根目录 Native 构建的历史链接问题见 P0 报告。当前可复现入口为 Node.js CLI，Native 库测试与已记录的独立消费者构建分别有证据。[历史限制](ssim-validation.md#existing-native-root-build-failure)
- 已完成报名初审，最终验收以组委会评定为准。正式截止日期、入口、材料模板、演示形式，以及上游 PR／发布要求待官方通知确认。

| 正式提交前事项 | 当前状态 |
| --- | --- |
| 补入正式通知链接、截止与验收入口 | 待赛事群通知 |
| 按正式模板核对四项要求及个人声明 | 草稿已备，格式待对齐 |
| 锁定最终提交 SHA，核实相应 CI 和可下载产物 | 本文已给出可复现基线，最终提交待锁定 |
| 按官方入口提交并保留回执 | 待正式提交 |

内部排期与每日完成情况以 handoff.md 为准。[规划与交接](../handoff.md)
