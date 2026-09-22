# 平衡数据 CloudBase 后端

该目录包含通关战报和匿名里程碑计数的 CloudBase Node.js 云函数，使用腾讯当前维护的
`@cloudbase/js-sdk` v3。事件云函数环境提供临时鉴权信息，函数将其显式传给
`CLOUD_API` 数据库通道；不要改回默认 `GATEWAY`，否则管理导出查询会返回
`INVALID_CREDENTIALS`。数据库使用上海地域的
**云数据库／文档型数据库**，集合名称固定为 `run_reports`（整轮战报）和
`player_events`（匿名计数事件）；不要选择 MySQL
或 PostgreSQL。

## 本地测试

进入 `functions/report_api` 后运行：

```powershell
npm test
```

单元测试不需要连接腾讯云，也不会读取任何密钥。部署前安装依赖并生成锁文件：

```powershell
npm install
```

## 云端配置

1. 在 CloudBase 创建上海地域免费环境，以及 `run_reports`、`player_events` 集合。
2. 复制 `cloudbaserc.example.json` 为本机部署配置，并填入环境 ID；不要提交
   包含个人环境信息的本机配置。
3. 创建足够长的随机管理 token，在云函数环境变量中设置
   `BALANCE_TELEMETRY_ADMIN_TOKEN`。
4. 部署 `report_api`，再在 HTTP 网关中把 `/v1` 前缀路由到该函数。网关会
   剥离前缀，因此函数同时接受 `/v1/reports` 与 `/reports`、
   `/v1/events` 与 `/events`，以及
   `/v1/admin/export` 与 `/admin/export`。
5. 真实端到端验证完成后，把 `/v1/reports` 的 HTTPS 地址写入游戏
   `project.godot` 的 `balance_telemetry/endpoint`。

上传接口没有客户端共享密钥；移动应用中的秘密无法可靠保密。管理导出接口则
必须使用只存于云端环境变量和管理员本机环境变量的 Bearer token。

当前生产环境为 `wuxiacard-d9gvg1e2o15e3b73e`，公网入口为：

```text
https://wuxiacard-d9gvg1e2o15e3b73e-1488910861.ap-shanghai.app.tcloudbase.com/v1
```

## 下载战报

管理员令牌和导出地址已保存在当前 Windows 用户环境变量中，不写入仓库：

- `WUXIA_TELEMETRY_ADMIN_TOKEN`
- `WUXIA_TELEMETRY_ADMIN_ENDPOINT`

同时下载通关报告和新手流程完成计数（默认 CSV）：

```powershell
powershell -ExecutionPolicy Bypass -File tools/download_balance_reports.ps1
```

也可以只下载其中一类：

```powershell
powershell -ExecutionPolicy Bypass -File tools/download_balance_reports.ps1 -Dataset Reports
powershell -ExecutionPolicy Bypass -File tools/download_balance_reports.ps1 -Dataset Events
```

也可以使用 `-Format Json`，或用 `-From 2026-09-01 -To 2026-09-30`
限制日期范围。脚本优先读取当前进程环境变量，并在新终端尚未继承时回退读取
Windows 用户环境变量；它不会覆盖已存在的导出文件。`-OutputPath` 仅适用于
`-Dataset Reports` 或 `-Dataset Events` 的单类下载。

`beginner_flow_completed` 在同一匿名安装中最多记录一次，只包含匿名 ID、事件
类型、版本、平台与时间，不包含卡组或对局内容。客户端离线时会暂存并在以后重试。
