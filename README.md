# 学生端 (Student)

![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0+-blue?logo=dart)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)

> 一个基于 Flutter 开发的 **Windows 桌面端** 学生考试与学习系统，与教师端配合使用，支持在线考试、打字练习、操作题模拟、积分兑换等完整学习闭环。

---

## 📋 目录

- [项目简介](#项目简介)
- [技术栈](#技术栈)
- [核心功能](#核心功能)
- [项目结构](#项目结构)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [构建部署](#构建部署)
- [架构说明](#架构说明)
- [截图展示](#截图展示)

---

## 📖 项目简介

**学生端 (Student)** 是一个面向课堂场景的 Windows 桌面应用，为学生提供以下学习体验：

- **在线考试** — 支持选择题、连线题、排序题等多种题型，自动评分与错题回顾
- **打字练习** — 中文、英文打字训练，提升打字速度与准确率
- **操作题模拟** — 基于 VHD 虚拟磁盘的操作题环境，模拟真实操作系统操作
- **积分激励** — 完成学习任务获取积分，可兑换商品，增强学习动力
- **数据可视化** — 通过图表直观展示学习进度、成绩趋势与积分变化

系统通过 **RESTful API** 与后端服务通信，并通过 **WebSocket** 实现与教师端的实时数据同步，支持教师端动态切换班级等场景。

---

## 🔧 技术栈

| 技术/依赖 | 版本 | 用途 |
|-----------|------|------|
| **Flutter / Dart** | >=3.0.0 | 跨平台桌面应用框架 |
| **Provider** | ^6.0.5 | 状态管理（AuthProvider, ExamProvider, UserProvider） |
| **http** | ^1.1.0 | RESTful API 网络请求 |
| **web_socket_channel** | （内置） | WebSocket 实时通信 |
| **fl_chart** | ^0.66.0 | 数据可视化图表（成绩趋势、积分变化曲线） |
| **shared_preferences** | ^2.2.2 | 本地键值对持久化（登录状态等） |
| **path_provider** | ^2.1.1 | 文件系统路径访问 |
| **window_manager** | ^0.3.7 | 窗口管理（自定义标题栏、全屏模式、窗口尺寸） |
| **desktop_multi_window** | ^0.2.0 | 多窗口支持（操作题指导窗口） |
| **flutter_svg** | ^2.0.9 | SVG 矢量图标渲染 |
| **json_annotation / json_serializable** | 最新 | JSON 序列化/反序列化 |
| **intl** | ^0.18.1 | 国际化与日期格式化 |
| **uuid** | ^4.2.1 | 唯一标识符生成 |

---

## 🚀 核心功能

### 1️⃣ 用户认证系统

| 功能 | 说明 |
|------|------|
| **登录** | 学生账户登录，支持记住登录状态 |
| **注册** | 新学生账户注册，绑定计算机名称与 IP |
| **自动登录** | 本地保存登录凭据，启动时自动登录 |
| **单实例运行** | 通过 `SingleInstanceService` 检测并防止同一台电脑重复启动 |

### 2️⃣ 首页仪表盘

- **个人信息展示** — 学生姓名、班级、积分实时显示
- **学习概览表格** — 汇总展示所有学习记录（时间、类型、成绩、积分）
- **数据可视化图表** — 使用 `fl_chart` 绘制四条趋势线：
  - 📈 **小测成绩趋势** — 近两个月考试得分变化
  - ⌨️ **中文打字成绩** — 中文打字得分趋势
  - ⌨️ **英文打字成绩** — 英文打字得分趋势
  - ⭐ **学习积分变化** — 积分累积曲线
- **教师端班级联动** — 每 5 秒轮询教师端活跃班级，自动切换并刷新数据
- **页面生命周期管理** — 通过 `RouteObserver` 智能暂停/恢复轮询，优化性能

### 3️⃣ 打字练习模块

| 功能 | 说明 |
|------|------|
| **中文打字练习** | 中文文本录入，支持速度与准确率评分 |
| **英文打字练习** | 英文文本录入，支持速度与准确率评分 |
| **基础打字练习** | 基础打字功能训练 |

### 4️⃣ 考试小测系统

- **考试列表** — 展示所有可用考试，支持选择进入答题
- **多种题型支持**：
  - **选择题** — A/B/C/D 四选一，选中后自动跳转下一题
  - **连线题** — 左右两侧项目匹配连线，支持彩色连线可视化
  - **排序题** — 拖拽或点击排列选项顺序
- **答题体验**：
  - 进度条实时显示答题进度
  - 上一题/下一题导航
  - 答题过程中可随时退出（含确认提示）
- **交卷评分** — 提交后自动评分，显示总分、正确题数、错误题数
- **错题本** — 考试结束后可查看详细错题分析：
  - 选择题：标注错误选项，显示正确答案
  - 连线题：展示错误连线关系，彩色标记
  - 排序题：对比错误排列顺序与正确顺序

### 5️⃣ 操作题模块

- **VHD 虚拟磁盘操作** — 通过 `vhd_service` 管理虚拟磁盘文件
- **操作指导窗口** — 独立的指导窗口，提供操作步骤指引
- **多窗口模式** — 支持 `desktop_multi_window` 多窗口并行
- **文件管理** — 初始文件创建、用户操作记录与答案提交

### 6️⃣ 积分兑换系统

- **积分查看** — 首页顶部实时显示当前积分余额
- **商品列表** — 卡片式展示可兑换商品，包含：
  - 商品名称与描述
  - 所需积分数量
  - 库存状态（有限库存/无限库存）
- **兑换流程**：
  1. 点击商品进入兑换确认弹窗
  2. 显示消耗积分与剩余积分
  3. 确认后调用 API 完成兑换
  4. 实时更新积分余额
- **智能状态** — 自动判断积分不足/已售罄状态，禁用对应按钮

### 7️⃣ 实时通信

- **WebSocket 连接** — 与服务器保持长连接，实现实时数据推送
- **Socket 服务** — 封装 WebSocket 连接管理与消息处理

### 8️⃣ 设备与服务

- **设备信息采集** — 自动获取计算机名称、IP 地址等信息
- **本地存储** — 使用 `shared_preferences` 持久化本地数据
- **API 服务** — 统一封装 HTTP 请求，支持 GET/POST 等操作

---

## 📁 项目结构

```
student/
├── lib/
│   ├── main.dart                              # 应用入口
│   │   ├── 窗口初始化（window_manager）
│   │   ├── 单实例检测（SingleInstanceService）
│   │   ├── API 服务初始化
│   │   └── Socket 服务初始化
│   │
│   ├── models/                                # 数据模型
│   │   ├── exam_model.dart                    # 考试模型
│   │   ├── question_model.dart                # 题目模型（选择题/连线题/排序题）
│   │   └── user_model.dart                    # 用户模型
│   │
│   ├── pages/                                 # 页面
│   │   ├── login_page.dart                    # 登录页
│   │   ├── register_page.dart                 # 注册页
│   │   ├── home_page.dart                     # 首页（仪表盘 + 数据图表）
│   │   ├── exam_dashboard_page.dart           # 考试列表与答题页
│   │   ├── chinese_typing_page.dart           # 中文打字练习
│   │   ├── english_typing_page.dart           # 英文打字练习
│   │   ├── base_typing_page.dart              # 基础打字练习
│   │   ├── quiz_typing_page.dart              # 测验打字
│   │   ├── quiz_page/                         # 小测页面
│   │   ├── result_page.dart                   # 成绩结果页
│   │   ├── wrong_questions_page.dart          # 错题本（全屏模式）
│   │   ├── points_exchange_page.dart          # 积分兑换
│   │   └── operation_guide_window.dart        # 操作题指导窗口
│   │
│   ├── providers/                             # 状态管理（Provider）
│   │   ├── auth_provider.dart                 # 认证状态管理
│   │   ├── exam_provider.dart                 # 考试状态管理
│   │   └── user_provider.dart                 # 用户状态管理
│   │
│   ├── services/                              # 服务层
│   │   ├── api_service.dart                   # HTTP API 封装
│   │   ├── socket_service.dart                # WebSocket 通信服务
│   │   ├── local_storage_service.dart         # 本地数据持久化
│   │   ├── device_info_service.dart           # 设备信息采集
│   │   ├── quiz_service.dart                  # 小测服务
│   │   ├── vhd_service.dart                   # VHD 虚拟磁盘操作
│   │   └── single_instance_service.dart       # 单实例运行检测
│   │
│   ├── theme/
│   │   └── app_theme.dart                     # 应用主题配置
│   │
│   ├── utils/
│   │   └── app_path.dart                      # 路径工具类
│   │
│   └── widgets/                               # 自定义组件
│       ├── custom_title_bar.dart               # 自定义标题栏
│       ├── draggable_overlay_window.dart       # 可拖拽叠加窗口
│       ├── input_row.dart                     # 输入行组件
│       └── no_copy_paste_controller.dart       # 防复制粘贴控制器
│
├── assets/
│   ├── images/                                # 图片资源
│   └── icons/                                 # 图标资源
│
├── windows/                                   # Windows 平台配置
│   ├── flutter/                               # Flutter Windows 插件
│   └── runner/                                # Windows 运行器
│
├── pubspec.yaml                               # 项目配置与依赖声明
├── analysis_options.yaml                      # 静态分析配置
└── student_config.json                        # 学生端配置文件
```

---

## ⚙️ 环境要求

| 依赖 | 版本要求 |
|------|----------|
| **Flutter SDK** | >= 3.0.0 |
| **Dart SDK** | >= 3.0.0 |
| **操作系统** | Windows 10+ |
| **开发工具** | Visual Studio Code / Android Studio |
| **Windows 开发环境** | Visual Studio 2022（含"使用 C++ 的桌面开发"工作负载） |

---

## 🚦 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/jdwls/student_lerarn.git
cd student
```

### 2. 安装依赖

```bash
flutter pub get
```

### 3. 配置后端服务

编辑 `student_config.json` 文件，配置后端 API 地址与 WebSocket 地址：

```json
{
  "api_base_url": "http://your-server:port/api",
  "socket_url": "ws://your-server:port/ws"
}
```

### 4. 运行应用

```bash
flutter run
```

或指定运行 Windows 平台：

```bash
flutter run -d windows
```

---

## 📦 构建部署

### 构建 Windows 安装包

```bash
flutter build windows
```

构建产物位于 `build/windows/x64/runner/Release/` 目录，包含可执行文件 `student.exe` 及其依赖的 DLL 文件。

### 打包分发

建议使用 Inno Setup 或 NSIS 等工具将 Release 目录打包为安装程序，方便分发部署。

---

## 🏗️ 架构说明

### 状态管理

采用 **Provider** 模式管理应用状态，分为三个核心 Provider：

```
AuthProvider  ── 管理用户登录/注销状态、当前用户信息
UserProvider  ── 管理用户个人数据（积分、班级等）
ExamProvider  ── 管理考试状态（考试列表、当前题目、答题进度、评分）
```

### 数据流

```
[页面 Widget] ──→ [Provider] ──→ [Service] ──→ [后端 API]
     ↑              │
     └──────────────┘
     (Consumer/Consumer2 监听状态变更自动刷新 UI)
```

### 通信方式

- **RESTful API** — 常规数据请求（登录、获取考试列表、提交答案、积分兑换等）
- **WebSocket** — 实时数据推送（教师端班级切换通知等）

### 页面生命周期优化

- 首页通过 `RouteObserver` 监听页面路由变化
- 当其他页面覆盖首页时，自动**暂停**轮询请求
- 返回首页时，自动**恢复**轮询并刷新数据
- 应用从后台切回前台时，自动刷新数据

---

## 📸 截图展示

> 截图待补充

---

## 🤝 贡献指南

欢迎提交 Issue 或 Pull Request 来改进项目。

### 开发规范

- 遵循 Flutter 官方代码风格指南
- 使用 `flutter_lints` 进行代码静态分析
- 保持 Provider + Service 的架构分层清晰
- 为新增功能编写对应的单元测试

---

## 📄 开源协议

本项目基于 MIT 协议开源，详见 [LICENSE](LICENSE) 文件。

---

## 📬 联系方式

- 项目地址：[https://github.com/jdwls/student_lerarn](https://github.com/jdwls/student_lerarn)