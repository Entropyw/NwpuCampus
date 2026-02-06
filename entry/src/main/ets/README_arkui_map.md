# ArkUI 地图迁移说明

本目录下新增了纯 ArkTS/ArkUI 的地图渲染与业务逻辑，替代 WebView 里的 HTML/JS。主要目标：

- 在 ArkTS 中解析 `map.osm` 并渲染道路/建筑/水体/运动场等基础图层。
- 用 ArkUI 组件实现路线规划、账号、地点管理、筛选与审核等 UI。
- 通过 ArkTS 服务类管理用户会话、地点列表、路线规划等逻辑。

## 目录结构

- `components/MapCanvas.ets`：地图 Canvas 渲染组件。
- `model/MapTypes.ets`：地图与地点数据类型定义。
- `services/OsmParser.ets`：OSM 文本解析服务（轻量正则解析）。
- `services/MapMath.ets`：投影与距离计算工具。
- `services/PlaceService.ets`：地点数据管理（当前为本地内存版本）。
- `services/AuthService.ets`：账号与会话管理（本地内存）。
- `services/RoutePlanner.ets`：路线规划（当前为直线规划）。

## 运行说明（当前阶段）

- `Index.ets` 已切换为 ArkUI 版本，启动后直接显示 Canvas 地图。
- 右侧面板可以进行登录、地点创建、筛选等操作（本地内存保存）。
- 需要网络/服务端同步时，可在 `PlaceService` 中接入后端接口。

## 下一步建议

- 将 `RoutePlanner` 升级为基于道路图的 Dijkstra/A* 路径规划。
- 对 `OsmParser` 进行分块解析与缓存，提升性能与稳定性。
- 接入真实服务端 API（或鸿蒙分布式数据能力）以持久化用户数据。
