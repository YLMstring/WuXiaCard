# 平衡数据 CloudBase 后端

该目录包含通关战报的 CloudBase Node.js 云函数，使用腾讯当前维护的
`@cloudbase/js-sdk` v3，并由云函数环境自动提供鉴权信息。数据库使用上海地域的
**云数据库／文档型数据库**，集合名称固定为 `run_reports`；不要选择 MySQL
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

1. 在 CloudBase 创建上海地域免费环境和 `run_reports` 集合。
2. 复制 `cloudbaserc.example.json` 为本机部署配置，并填入环境 ID；不要提交
   包含个人环境信息的本机配置。
3. 创建足够长的随机管理 token，在云函数环境变量中设置
   `BALANCE_TELEMETRY_ADMIN_TOKEN`。
4. 部署 `report_api`，再在 HTTP 网关中把 `/v1` 前缀路由到该函数。网关会
   剥离前缀，因此函数同时接受 `/v1/reports` 与 `/reports`，以及
   `/v1/admin/export` 与 `/admin/export`。
5. 真实端到端验证完成后，把 `/v1/reports` 的 HTTPS 地址写入游戏
   `project.godot` 的 `balance_telemetry/endpoint`。

上传接口没有客户端共享密钥；移动应用中的秘密无法可靠保密。管理导出接口则
必须使用只存于云端环境变量和管理员本机环境变量的 Bearer token。

当前生产环境为 `wuxiacard-d9gvg1e2o15e3b73e`，公网入口为：

```text
https://wuxiacard-d9gvg1e2o15e3b73e-1488910861.ap-shanghai.app.tcloudbase.com/v1
```
