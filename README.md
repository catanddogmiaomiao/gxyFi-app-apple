# gxyFi macOS

家庭资产台账的 Mac 版，对应 Windows 客户端 [gxyFi](https://github.com/catanddogmiaomiao/gxyFi)。用 Xcode 27.1 的 macOS SwiftUI 工程编写。账本放在本机 SQLite，不上传。网站 `gxyFi-web` 仍是另一本账，目前不会自动同步。

它统计五件事：储蓄、投资、不动产、支出、预算。行情只给持仓估值，有延迟，不构成投资建议。

## 打开

用 Xcode 27.1 打开 `gxyFiApp.xcodeproj`，运行 gxyFiApp。部署目标是 macOS 26。

数据库在 `~/Library/Application Support/gxyFi/gxyfi.db`。沙盒打开后，系统会把它放到这个 App 的容器里。备份这个文件即可保留手工记录和最近一次行情。

图标和 Windows 版同一套深色底、顶部金线、金色 Fi。`Icon/gxyFi.ico` 是多尺寸 ICO，App 图标用同一张图。

## 行情

只查询持仓里的代码。黄金用上海黄金交易所延时行情，A 股先用新浪、失败再用东方财富，美股默认用 Yahoo Finance。在「行情」页保存 Finnhub Token 后，美股优先走 Finnhub。Token 只留在本机，导出的 Excel 不含 Token。
