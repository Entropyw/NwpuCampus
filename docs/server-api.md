# NwpuCampus Server API# NwpuCampus Server API 文档



## 8. 用户消息本文档基于 `server/src/server.ts` 的实现，描述所有可用的 HTTP API、鉴权方式、字段说明与示例请求/响应结构。默认服务地址：



### GET /api/messages- Base URL: `http://121.36.80.168:8080`

**描述**：获取当前用户的历史消息。

> 若无法访问健康检查，请确认服务已启动且服务器安全组/防火墙已放行对应端口。

**请求头**：`Authorization: Bearer <token>`

> 全部接口均返回 JSON。除特别说明外，状态码为 200 表示成功；错误时返回 `{ error: string }`。

**响应**：

```json---

{ "messages": [ { "id": "string", "userId": "string", "message": "string", "date": 1700000000000 } ] }

```## 1. 通用约定



> 说明：服务端消息已持久化。实际响应还会包含 `title`/`content`/`unread`/`action`/`place` 等字段，前端可按需使用。### 1.1 Content-Type

- 请求体为 JSON 时：`Content-Type: application/json`

### 1.2 认证方式
- 需要登录的接口必须携带：
  - `Authorization: Bearer <token>`
- Token 由 `/api/register` 或 `/api/login` 返回。

### 1.3 Place 字段说明

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 地点唯一 ID |
| name | string | 地点名称 |
| lat | number | 纬度 |
| lon | number | 经度 |
| description | string | 描述 |
| imageUrl | string | 图片 URL |
| ownerId | string | 拥有者用户 ID |
| ownerName | string | 拥有者用户名 |
| status | string | `private` / `pending` / `approved` / `rejected` |
| category | string | `normal` / `hazard` |
| hazardType | string | `water` / `slippery` / `danger` / `` |
| votes | object | `{ up: number, down: number }` |
| createdAt | number | 创建时间戳 |
| updatedAt | number | 更新时间戳 |
| sourceKey | string | 系统地点映射 Key（可选） |
| sourceType | string | `system` 或空字符串（可选） |

### 1.4 用户对象

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 用户 ID |
| username | string | 用户名 |
| isAdmin | boolean | 是否管理员 |

---

## 2. 健康检查

### GET /api/health
**描述**：服务健康状态。

**响应**：
```json
{ "status": "ok" }
```

---

## 3. 认证与用户

### POST /api/register
**描述**：注册用户。

**请求体**：
```json
{ "username": "string", "password": "string" }
```

**响应**：
```json
{ "token": "string", "user": { "id": "string", "username": "string", "isAdmin": false } }
```

**错误**：
- 400: `Invalid credentials`
- 400: `User exists`

---

### POST /api/login
**描述**：登录。

**请求体**：
```json
{ "username": "string", "password": "string" }
```

**响应**：
```json
{ "token": "string", "user": { "id": "string", "username": "string", "isAdmin": false } }
```

**错误**：
- 401: `Invalid credentials`

---

### GET /api/me
**描述**：获取当前用户信息。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "user": { "id": "string", "username": "string", "isAdmin": false } }
```

---

## 4. 系统覆盖数据

### GET /api/system-overrides
**描述**：获取系统地点覆盖信息（管理员审核通过后产生）。

**响应**：
```json
{ "overrides": [ { "sourceKey": "string", "name": "string", "description": "string", "imageUrl": "string", "updatedAt": 1700000000000 } ] }
```

---

## 5. 地点（Places）

### GET /api/places?scope=public
**描述**：获取公开地点与风险点。

**响应**：
```json
{ "places": [Place], "hazards": [Place] }
```

---

### GET /api/places?scope=mine
**描述**：获取当前用户的地点（含 pending）。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "places": [Place], "pending": [Place] }
```

---

### GET /api/places?scope=pending
**描述**：管理员查看所有待审核地点。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "pending": [Place] }
```

**错误**：
- 403: `Admin only`

---

### POST /api/places
**描述**：创建地点。

**请求头**：`Authorization: Bearer <token>`

**请求体**：
```json
{
  "name": "string",
  "lat": 34.03,
  "lon": 108.76,
  "description": "string",
  "imageUrl": "string",
  "category": "normal" | "hazard",
  "hazardType": "water" | "slippery" | "danger" | "",
  "status": "private" | "pending" | "approved"
}
```

**说明**：
- 非管理员即使传 `status=approved` 也会被改为 `private` 或 `pending`。

**响应**：
```json
{ "place": Place }
```

**错误**：
- 400: `Name required`

---

### PUT /api/places/:id
**描述**：更新地点。

**请求头**：`Authorization: Bearer <token>`

**请求体**：
```json
{
  "name": "string",
  "lat": 34.03,
  "lon": 108.76,
  "description": "string",
  "imageUrl": "string",
  "category": "normal" | "hazard",
  "hazardType": "water" | "slippery" | "danger" | "",
  "status": "private" | "pending" | "approved"
}
```

**响应**：
```json
{ "place": Place }
```

**错误**：
- 403: `Forbidden`
- 404: `Not found`

---

### DELETE /api/places/:id
**描述**：删除地点。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "ok": true }
```

**错误**：
- 403: `Forbidden`
- 404: `Not found`

---

### POST /api/places/:id/publish
**描述**：提交审核（变更为 `pending`）。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "place": Place }
```

**错误**：
- 403: `Forbidden`
- 404: `Not found`

---

### POST /api/places/:id/vote
**描述**：投票（点赞/踩）。

**请求头**：`Authorization: Bearer <token>`

**请求体**：
```json
{ "value": 1 }
```
或
```json
{ "value": -1 }
```

**响应**：
```json
{ "place": Place }
```

**错误**：
- 400: `Invalid vote`
- 404: `Not found`

---

### POST /api/places/:id/feedback
**描述**：提交反馈。

**请求头**：`Authorization: Bearer <token>`

**请求体**：
```json
{ "message": "string" }
```

**响应**：
```json
{ "ok": true }
```

**错误**：
- 400: `Message required`
- 404: `Not found`

---

## 6. 管理员接口

### POST /api/admin/places/:id/approve
**描述**：管理员审核通过地点。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "place": Place }
```

**错误**：
- 403: `Admin only`
- 404: `Not found`

---

### POST /api/admin/places/:id/reject
**描述**：管理员拒绝地点。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "place": Place }
```

**错误**：
- 403: `Admin only`
- 404: `Not found`

---

## 7. 用户偏好

### GET /api/preferences
**描述**：获取用户隐藏地点列表。

**请求头**：`Authorization: Bearer <token>`

**响应**：
```json
{ "hiddenPlaceIds": ["placeId1", "placeId2"] }
```

---

### POST /api/preferences/hide
**描述**：设置隐藏/显示地点。

**请求头**：`Authorization: Bearer <token>`

**请求体**：
```json
{ "placeId": "string", "hidden": true }
```

**响应**：
```json
{ "hiddenPlaceIds": ["placeId1", "placeId2"] }
```

**错误**：
- 400: `placeId required`

---

## 8. 错误响应格式

```json
{ "error": "string" }
```

---

## 9. 默认管理员
- 用户名：`admin`
- 密码：`admin123`

建议上线后立即修改 `server/data/db.json`。
