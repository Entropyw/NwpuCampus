# NwpuCampus Server API 文档

本文档基于 `server/src/server.ts` 的实现，描述所有可用的 HTTP API、鉴权方式、字段说明与示例请求/响应结构。默认服务地址：

- Base URL: `http://121.36.80.168:8080`

> 全部接口均返回 JSON。除特别说明外，状态码为 200 表示成功；错误时返回 `{ error: string }`。

---

## 1. 通用约定

### 1.1 Content-Type
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
| email | string | 绑定邮箱（可选，未绑定为空字符串） |
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

### GET /api/users
**描述**：开发用，列出所有用户（无需登录）。

**响应**：
```json
{ "users": [ { "id": "string", "username": "string", "isAdmin": false } ] }
```

---

### POST /api/users
**描述**：开发用，直接创建用户（无需登录）。

**请求体**：
```json
{ "username": "string", "password": "string" }
```

**响应**：
```json
{ "user": { "id": "string", "username": "string", "isAdmin": false } }
```

**错误**：
- 400: `Invalid credentials`
- 400: `User exists`

---

### POST /api/pre-register
**描述**：为尚未完成注册的账号创建占位用户并生成验证码（有效期 5 分钟），不发送邮件，返回验证码供前端/开发使用。

**请求体**：
```json
{ "username": "string" }
```

**响应**：
```json
{ "ok": true, "code": "123456" }
```

**错误**：
- 400: `username required`
- 400: `User exists`（已设置密码的正式账号）

---

### POST /api/send-code
**描述**：为已存在的账号生成验证码（有效期 5 分钟），不发送邮件，返回验证码供开发/短信渠道使用。

**请求体**：
```json
{ "username": "string" }
```

**响应**：
```json
{ "ok": true, "code": "123456" }
```

**错误**：
- 404: `User not found`

---

### POST /api/login-code
**描述**：使用验证码登录。

**请求体**：
```json
{ "username": "string", "code": "123456" }
```

**响应**：
- 占位用户（尚未设置密码）：`{ "ok": true }`
- 已设置密码的用户：`{ "token": "string", "user": { "id": "string", "username": "string", "isAdmin": false } }`

**错误**：
- 401: `Invalid credentials`
- 404: `User not found`

---

### POST /api/email/send
**描述**：发送邮箱验证码（用途：绑定邮箱或重置密码，5 分钟内有效）。

**请求体**：
```json
{ "username": "string", "email": "user@example.com", "purpose": "bind" | "reset" }
```

**响应**：
```json
{ "ok": true, "code": "123456" }
```

**说明**：
- 始终发送邮件，同时返回验证码便于开发环境调试。
- `purpose=bind`：若账号已绑定且邮箱不同，返回 400。
- `purpose=reset`：需要账号已绑定且邮箱一致，否则返回 400。
- 验证码记录存入 `verification_codes`，5 分钟后被清理。

**错误**：
- 400: `Username and email required`
- 400: `Email not bound to this account`
- 400: `Account already bound to a different email`
- 404: `User not found`
- 500: `Failed to send mail: ...`

---

### POST /api/email/bind
**描述**：使用邮箱验证码绑定账号邮箱。

**请求体**：
```json
{ "username": "string", "email": "user@example.com", "code": "123456" }
```

**响应**：
```json
{ "ok": true }
```

**错误**：
- 400: `Username, email and code required`
- 400: `Invalid or expired code`
- 404: `User not found`

---

### POST /api/password/reset
**描述**：使用邮箱验证码重置密码。

**请求体**：
```json
{ "username": "string", "code": "123456", "newPassword": "string" }
```

**响应**：
```json
{ "ok": true }
```

**错误**：
- 400: `Username, code and newPassword required`
- 400: `Email not bound to this account`
- 400: `Invalid or expired code`
- 404: `User not found`

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

### POST /api/admin/send-mail
**描述**：管理员发送验证码邮件（默认用途：绑定），并保存账号与验证码对应关系。

**请求头**：`Authorization: Bearer <token>`（管理员）

**请求体**：
```json
{ "account": "admin", "email": "user@example.com" }
```

**响应**：
```json
{ "ok": true, "code": "123456" }
```

**错误**：
- 400: `Account and email required`
- 403: `Admin only`
- 404: `User not found`
- 500: `Failed to send mail: ...`

**行为说明**：
- 验证码用途固定为 `bind`，有效期 5 分钟，写入 `verification_codes`，同时发送邮件。
- 邮件内容：subject `Verification Code`，正文 `Your verification code is <code>. It expires in 5 minutes.`
- SMTP: `smtp.126.com:465`，发件人：`ygshgzhy@126.com`

### POST /api/admin/verify-code
**描述**：验证账号与验证码是否匹配（有效期 5 分钟），成功后删除验证码记录。

**请求体**：
```json
{ "account": "admin", "code": "123456" }
```

**响应**：
```json
{ "ok": true }
```

**错误**：
- 400: `Account and code required`
- 400: `Invalid or expired code`

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

## 8. 图片上传

### POST /api/images
**描述**：上传图片二进制数据，保存到服务器并返回可访问 URL（无需登录）。

**请求头**：
- `Content-Type: image/jpeg | image/png | image/webp | image/gif`
- 可选：`X-File-Name: example.png` 或查询参数 `?filename=example.png` 用于推断扩展名。

**请求体**：二进制图片流。

**响应**：
```json
{ "id": "string", "url": "http://.../images/<id>.png", "fileName": "<id>.png" }
```

**错误**：
- 400: `Empty file` / `Unsupported image type` / `File too large`

---

### POST /api/images/from-path
**描述**：从服务器指定路径读取图片并保存（无需登录）。适合将已有文件导入上传目录。

**请求体**：
```json
{ "path": "/abs/path/to/image.png", "contentType": "image/png", "fileName": "image.png" }
```
- `path` 必填，服务器可访问的文件绝对路径。
- `contentType` 可选，未提供时按扩展名推断。
- `fileName` 可选，仅用于扩展名推断，不会影响生成的 ID 文件名。

**响应**：
```json
{ "id": "string", "url": "http://.../images/<id>.png", "fileName": "<id>.png" }
```

**错误**：
- 400: `path required` / `Unsupported image type` / `File too large`
- 404: `File not found`

---

### GET /images/{fileName}
**描述**：直接获取已上传图片文件。

**响应**：图片二进制流，`Content-Type` 按文件扩展名返回。

**错误**：
- 400: `Bad Request`
- 404: `Not Found`

---

## 9. 错误响应格式

```json
{ "error": "string" }
```

---

## 10. 默认管理员
- 用户名：`admin`
- 密码：`admin123`
