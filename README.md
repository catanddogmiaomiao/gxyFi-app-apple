# gxyFi iPhone

家庭资产台账的 iPhone 版，对应 Windows 客户端 [gxyFi](https://github.com/catanddogmiaomiao/gxyFi)。用 Xcode 27.1 的 iOS SwiftUI 工程编写，只面向 iPhone。

不登录时，账只放在这台手机的 SQLite 里。在「更多 → 网页同步」登录网页版 [gxyFi-web](https://github.com/catanddogmiaomiao/gxyFi-web) 的账号后，手机和网页用同一本账：记账、修改、删除都直接存到网页端，再下载回手机显示。

## 网页同步

- 填网页端地址（必须是 https）、用户名和密码。网页端不开放注册，账号在 Cloudflare 的 `AUTH_USERS` 里配置。
- 第一次登录时，如果手机上已经记过账，可以选「上传到网页账号」（追加到网页账号里）或「改用网页上的账」。两种选择都会先把手机账本备份到「文件」App 的 gxyFi 文件夹。
- 登录凭证存在钥匙串里，14 天后过期，过期后需要重新登录。打开 App 或从后台切回来时会自动下载最新数据。
- 没有网络时只能查看上次同步的内容，不能记账。
- 退出登录会清空手机上的缓存，账仍保存在网页端。
- 登录后「刷新行情」由网页端去取，Finnhub Token 用网页端的 `FINNHUB_TOKEN`。

它统计五件事：储蓄、投资、不动产、支出、预算。行情只给持仓估值，有延迟，不构成投资建议。

## 打开

用 Xcode 27.1 打开 `gxyFiApp.xcodeproj`，目标选一台 iPhone 或 iPhone 模拟器，运行 gxyFiApp。部署目标是 iOS 18.0，iOS 18 及以上的 iPhone 都能装，主屏幕名称是 gxyFi。

数据库在这个 App 沙盒里的 `Library/Application Support/gxyFi/gxyfi.db`。整机备份或换机时，系统会带着这个文件走。

图标是深色底、一圈圆角金边、金色 Palatino 小写 g，颜色取自 Windows 版侧边栏的 gxyFi 字标。`Icon/gxyFi.ico` 是多尺寸 ICO，iPhone 主屏幕用同一张 1024 图。

底部有总览、储蓄、投资、支出。不动产、预算、行情和导出 Excel 在「更多」里。表格可以左右滑动。

## 行情

只查询持仓里的代码。黄金用上海黄金交易所延时行情，A 股先用新浪、失败再用东方财富，美股默认用 Yahoo Finance。在「行情」页保存 Finnhub Token 后，美股优先走 Finnhub。Token 只留在这台手机，导出的 Excel 不含 Token。
