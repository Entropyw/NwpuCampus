# 华为云真机定位调试指南

本文说明如何在华为云真机调试中启用真实定位，并验证“我的位置”在地图中标记与导航默认起点。

## ✅ 前置条件

- 已在 `entry/src/main/module.json5` 中声明权限：
  - `ohos.permission.LOCATION`
  - `ohos.permission.APPROXIMATELY_LOCATION`
- 设备/云真机已开启 **定位服务**（系统设置中打开定位）。

## 1. 切换到真实定位模式

在 `entry/src/main/ets/pages/Index.ets` 中找到配置：

```ts
private useMockLocation: boolean = true;
```

将其改为：

```ts
private useMockLocation: boolean = false;
```

> 说明：
> - `true`：模拟器模式，会在校园中心 500m 范围随机生成“我的位置”。
> - `false`：真实定位模式（华为云/真机），会请求系统定位权限并获取真实坐标。

## 2. 编译并部署到华为云设备

在 DevEco Studio 中：

1. 选择华为云真机设备（云调试）。
2. 运行构建并安装到设备（Run / Debug）。
3. 首次启动时会弹出定位权限请求，选择“允许”。

## 3. 验证定位与导航

启动应用后：

- 地图应显示“我的位置”标记（绿色圆点）。
- 若位置在校园范围内：
  - POI 起点默认切换为“我的位置”。
  - 点击“规划路线”后会以我的位置为默认起点。
- 若位置不在校园范围内：
  - 页面顶部提示 **“您当前不在校园内！”**
  - 不显示“我的位置”标记。

## 4. 常见问题排查

### 4.1 未弹出权限
- 检查 `module.json5` 中是否包含定位权限。
- 确保设备系统定位服务已开启。
- 可以卸载应用重新安装以触发权限弹窗。

### 4.2 仍显示“模拟位置”
- 确认 `useMockLocation` 已改为 `false`。
- 重新编译并部署到云设备。

### 4.3 定位失败 / 无坐标
- 设备未连接外网或定位服务不可用。
- 调试日志中可查看 `获取真实定位失败` 或权限拒绝提示。

## 5. 推荐调试日志（可选）

```bash
hdc dlog | grep com.example.nwpucampus
```

可查看定位请求、权限授权结果和 WebView 注入日志。

---

如需更精确的定位策略（连续定位、后台定位、WebView geolocation），可在此基础上扩展。