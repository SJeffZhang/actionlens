# ActionLens 可行性测试结论

## 1. 结论

结论：**方案可行，建议继续推进。**

目标链路：

`全局快捷键唤起截图 -> 用户框选/选窗 -> AI 识别截图内容 -> 自动生成任务/计划 -> 写入苹果提醒事项`

这条链路在 macOS 上具备完整的系统能力支撑，不需要依赖灰色方案。主要依赖如下：

- 截图：`screencapture` 或 `ScreenCaptureKit`
- OCR：`Vision`
- 提醒事项写入：`EventKit`
- 全局快捷键：原生 AppKit / Carbon 路线或成熟 Swift 封装库

因此，这不是“概念上能做”的项目，而是“工程上可以落地”的项目。

## 2. 为什么可行

### 2.1 截图入口可行

用户要求“通过快捷键唤起截图”。

这个需求在 macOS 上有两条可行路线：

#### 路线 A：调用系统截图能力

可由 App 监听全局快捷键后，调用系统自带命令：

```bash
/usr/sbin/screencapture -i
```

本地验证结果：

- 当前机器存在 `/usr/sbin/screencapture`
- 该命令支持 `-i` 交互截图、窗口截图、区域截图
- 也支持输出到文件或剪贴板

这意味着 v1 完全可以先复用系统截图交互，不必一开始自己造截图 UI。

#### 路线 B：使用 ScreenCaptureKit

如果后续要做更强控制，例如：

- 自定义选区 UI
- 更细粒度窗口/应用选择
- 更强的多屏支持
- 截图后立即进入自定义浮层流程

可以升级到 `ScreenCaptureKit`。

Apple 官方文档明确说明 `ScreenCaptureKit` 支持屏幕内容捕获，并要求添加 `NSScreenCaptureUsageDescription` 说明权限用途。[ScreenCaptureKit](https://developer.apple.com/documentation/ScreenCaptureKit?language=_2)

### 2.2 文本识别可行

截图中的“课程通知 / 会议截图 / 活动海报 / 招聘 JD / 旅行攻略”都天然包含大量文本内容，因此第一阶段不需要把问题定义成“纯视觉理解”，可以先走：

`截图 -> OCR -> 文本抽取 -> LLM 结构化`

Apple 的 `Vision` 提供文本识别能力：

- `VNRecognizeTextRequest`
- 新版 `RecognizeTextRequest`

官方文档说明 `Vision` 可以在图片中识别文本，且识别结果包含字符串与置信度信息。[Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images/) [RecognizeTextRequest](https://developer.apple.com/documentation/vision/recognizetextrequest)

因此，OCR 不是问题。

### 2.3 AI 提取“项目/任务/计划”可行

你要的其实不是简单 OCR，而是“识别截图类型后，生成对应行动计划”，例如：

- 课程通知 -> 学习安排
- 会议截图 -> TODO
- 活动海报 -> 参加计划
- 招聘 JD -> 申请任务
- 旅行攻略 -> itinerary

这类需求适合做成“两段式”：

1. OCR / 图像理解拿到原始文本与上下文
2. LLM 输出结构化任务

推荐输出结构：

```json
{
  "content_type": "meeting_notes",
  "title": "项目例会纪要",
  "summary": "本次会议涉及登录页修复和发布时间调整",
  "items": [
    {
      "title": "修复登录页按钮样式",
      "kind": "todo",
      "due_date": null,
      "priority": "medium",
      "notes": "来源于截图第 2 条"
    }
  ]
}
```

这属于 LLM 很擅长的“分类 + 信息抽取 + 结构化输出”场景，可行性高。

### 2.4 写入苹果提醒事项可行

Apple 官方 `EventKit` 支持创建和修改 reminder。

官方文档明确说明：

- 可以创建 `EKReminder`
- reminder 必须关联 calendar/list
- 需要先请求 reminders 访问权限

参考文档：

- [Creating events and reminders](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders?language=objc)
- [requestFullAccessToReminders](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:))
- [NSRemindersFullAccessUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsremindersfullaccessusagedescription)

所以“最后接入苹果提醒事项”不是外挂方案，而是官方支持能力。

## 3. 建议的实现策略

## 3.1 推荐 v1 技术路线

为了尽快验证产品价值，建议 v1 先走最稳妥方案：

- 形态：macOS Menu Bar App
- 语言：Swift + SwiftUI
- 全局快捷键：Carbon/Hotkey 封装
- 截图：优先调用系统 `screencapture -i`
- OCR：Vision
- AI：云端 LLM 做类型识别与结构化抽取
- 本地存储：SwiftData 或轻量本地 JSON/SQLite
- 提醒事项：EventKit 写入 Apple Reminders

### 为什么先用 `screencapture -i`

优点：

- 开发成本低
- 系统交互成熟，用户学习成本低
- 不需要 v1 就处理复杂的选区框、窗口高亮、多屏坐标等问题

等产品价值跑通，再升级为 `ScreenCaptureKit` 自定义截图体验。

## 3.2 AI 分层建议

建议不要让模型直接“盲看图片后随意发挥”，而是做成分层：

### 第一层：输入预处理

- 截图原图
- OCR 文本
- 可能的语言信息

### 第二层：内容类型分类

可分类为：

- `course_notice`
- `meeting_notes`
- `event_poster`
- `job_description`
- `travel_guide`
- `generic`

### 第三层：模板化结构化输出

不同类型输出不同模板：

- 课程通知 -> 学习计划
- 会议截图 -> TODO 列表
- 活动海报 -> 参加计划
- 招聘 JD -> 申请任务
- 旅行攻略 -> 行程安排

这样稳定性会明显高于“一套通用 prompt 打天下”。

## 4. 关键权限与系统限制

## 4.1 需要的权限

### 屏幕捕获权限

使用 `ScreenCaptureKit` 时，需要声明 `NSScreenCaptureUsageDescription`。[ScreenCaptureKit](https://developer.apple.com/documentation/ScreenCaptureKit?language=_2)

### 提醒事项权限

需要声明 `NSRemindersFullAccessUsageDescription`，否则可能无法正常弹出授权。[NSRemindersFullAccessUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsremindersfullaccessusagedescription)

### 全局快捷键相关

如果只是注册全局热键，通常可以通过成熟封装实现；如果后续扩展为更复杂的全局输入监听，可能会遇到额外权限问题。  
建议 v1 仅做“固定快捷键唤起”，不要把范围扩大到全局键盘监听工具。

## 4.2 主要风险

### 风险 1：截图权限与系统弹窗体验

首次使用时，用户要授权屏幕捕获权限。  
这不是技术阻塞，但会影响首启体验。

### 风险 2：AI 结果不稳定

同一张图中可能同时出现标题、正文、日期、备注、广告文案，模型可能误把“信息”提取成“任务”。

应对策略：

- 做类型分类
- 做 JSON schema 校验
- 提供“发送到提醒事项前确认”步骤

### 风险 3：活动海报和旅行攻略的“任务”并不天然存在

比如活动海报里写的是时间、地点、报名方式，而不是显式待办。  
这时产品本质上是在“生成计划”，不是“抽取已有 TODO”。

这不是不可行，而是需要在产品文案中讲清楚：

- 有些内容是“抽取任务”
- 有些内容是“根据内容生成行动计划”

## 5. MVP 是否可做

结论：**可以，而且适合做 MVP。**

建议 MVP 只做以下闭环：

1. 用户按快捷键
2. 唤起系统截图
3. 截完图后弹出结果面板
4. AI 识别截图类型与关键信息
5. 生成任务列表
6. 用户确认
7. 一键写入提醒事项

只要这条链跑通，产品价值就已经成立。

## 6. 推荐的最小版本边界

建议 v1 先支持 3 类最清晰场景：

- 会议截图 -> TODO
- 招聘 JD -> 申请任务
- 课程通知 -> 学习安排

原因：

- 文本密度高
- 任务导向明确
- 更容易评价效果

而下面两类建议放到第二阶段：

- 活动海报 -> 参加计划
- 旅行攻略 -> itinerary

因为这两类更偏“生成计划”，主观性更强。

## 7. 最终判断

### 可行性结论

- 技术上可行：**是**
- 系统权限链路可行：**是**
- 与苹果提醒事项集成可行：**是**
- 可先做 MVP 再逐步增强：**是**

### 建议

建议正式进入产品定义与 v1 设计阶段，并以 **macOS 菜单栏工具 + 快捷键截图 + AI 结构化 + Reminders 导入** 作为第一阶段主线。
