# NetDiagnose — 免费网络健康诊断

macOS 原生工具：一键扫描整个局域网，识别每台设备的类型、厂商和延迟，给出网络健康评分和可执行的优化建议。

> 网速慢、WiFi 不稳，别再瞎猜了。扫一次，看看家里到底谁在占用网络、哪台设备有问题。

## ⬇️ 下载

**macOS 版**：👉 [下载 DMG](https://github.com/wordwu/NetDiagnose/releases)

首次打开时 macOS 可能提示「无法验证开发者」：**系统设置 → 隐私与安全性 → 仍要打开**。

**Android 版**：👉 [下载 APK](https://github.com/wordwu/NetDiagnose/releases/latest/download/NetDiagnose.apk)

安装前需在手机设置中允许「安装未知来源应用」。安卓版与 Mac 版功能一致，界面为手机适配。

安卓版源码在仓库 [`android/`](android/) 目录（Kotlin + Compose）。

## ✨ 功能

- 📡 **自动检测网络**：自动识别网卡、网关、子网，支持手动指定
- 🏠 **局域网设备扫描**：ping 全子网 + ARP + mDNS + SSDP 多手段发现设备
- 🗺️ **网络拓扑图**：扫描结果自动生成交互式拓扑，点设备看详情
- 🔍 **设备详情**：IP、MAC、厂商、类型、风险等级、开放端口、识别置信度一目了然
- 🛡️ **风险分析**：风险设备、陌生设备、高延迟、新增开放端口自动提示
- ⏱️ **延迟测量**：每台设备单独测延迟并评级
- 📝 **设备备注**：给设备打标签写备注，下次扫描自动识别
- 👀 **后台监控**：每 5 分钟检测新设备并通知
- 📶 **WiFi 扫描**：查看信道拥堵，帮你选个不挤的频段
- 🖥️ **多格式导出**：PDF / HTML / Markdown / CSV / JSON + 分享卡片
- 🎯 **专家模式**：进阶用户可看更详细的扫描数据

## 💻 系统要求

- macOS 13.0+
- Apple Silicon 或 Intel

## 🔧 使用

1. 打开 App，点「一键诊断」
2. 等待扫描完成（通常 1–2 分钟）
3. 查看设备清单、健康评分和建议，可导出 PDF 报告

## 💬 反馈

遇到问题或想要新功能？去 [Issues](https://github.com/wordwu/NetDiagnose/issues) 反馈，作者会看。

---

Made with ❤️ by [AltairZheng](https://github.com/wordwu)
