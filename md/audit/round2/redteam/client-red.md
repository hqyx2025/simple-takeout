# 客户端 / 网页端二次攻击线（client-red）

- 日期：2026-10-25
- 范围：entry/src/main/ets（ArkTS 客户端）、server/takeout-gateway/src/main/resources/static（网页端 SPA）
- 说明：本文件由 lead 汇总 client-red 审计线的结论；标注【lead 复核】的条目我逐行读过源码，其余为审计线结论。

## 摘要

| 编号 | 级别 | 一句话 |
| --- | --- | --- |
| C-01 | Low | 客户端在 HTTPS 探测失败时静默回退到明文 http://10.0.2.2:8087，且把任意 2xx-4xx 当作"健康" |
| C-02 | Low | 高德 JS Key 与安全密钥硬编码在客户端常量里 |
| C-03 | 否定 | 手机端余额支付入口全部传支付密码，提交前清空输入状态，未发现遗漏入口 |
| C-04 | 否定 | 令牌落盘经 HUKS AES-GCM 加密，非明文 |
| C-05 | 否定 | 登出清理覆盖全部账号维度缓存并清除本地数据，未发现跨账号残留 |
| C-06 | 否定 | 网页端无 hash / query 路由，无法用 URL 直接打开管理页；导航按 role 白名单 |
| C-07 | 否定 | 网页端 HTML 插值基本都过 esc()，未发现可直接利用的存储型 XSS 注入点 |

## C-01【Low】客户端明文 HTTP 回退【lead 复核】

证据
- entry/src/main/ets/common/Constants.ets:145-148

      static readonly REMOTE_BASE_URL: string = 'https://hqyx.website/takeout'
      static readonly LOCAL_BASE_URL: string = 'http://10.0.2.2:8087'
      static readonly BASE_URL: string = API_CONFIG.REMOTE_BASE_URL
      static readonly BASE_URLS: string[] = [API_CONFIG.REMOTE_BASE_URL, API_CONFIG.LOCAL_BASE_URL]

- entry/src/main/ets/service/HttpClient.ets:34-59 —— 依次探测两个候选；判据是 statusCode 在 [200,500) 即视为可用；异常时继续下一个候选；全部失败才回落 BASE_URLS[0]。

      if (response.statusCode >= 200 && response.statusCode < 500) { selectBaseUrl(candidates[i]); return activeBaseUrl }

影响
- 一旦 HTTPS 探测失败（断网、证书异常、链路被干扰）而 10.0.2.2 可达，客户端会把整个会话切到明文 HTTP，Bearer token 与业务数据裸奔。
- 现实利用面有限：10.0.2.2 是模拟器宿主别名，真机通常不可达，因此按 Low 记录，属纵深防御问题。

修复建议
- Release 构建不编译 LOCAL_BASE_URL 候选（buildProfile 条件编译或参数注入）；探测判据收窄为正业务接口 200 且校验响应体；失败时直接报"网络不可用"，不要降级协议。

## C-02【Low】高德 JS Key 硬编码【lead 复核】

证据：entry/src/main/ets/common/Constants.ets:182-184

      static readonly MAP_JS_KEY: string = '744ada1c8bc6f4854234bd752859177f'
      static readonly MAP_JS_SECURITY_CODE: string = 'edc265a033df7b6a5a11a1db5f03b6ba'

影响：JS API Key 属前端 Key，随包分发不可避免，但可被第三方盗用配额；安全密钥（jscode）同样随包下发，削弱服务端绑定。服务端 REST Key 已改为代理下发（LocationController.java:20-46），这一点是对的。

修复建议：高德后台配置域名/包名白名单与配额告警；如可，改为服务端代理全部地图请求，客户端不再持有 JS Key。

## C-03【否定】手机端余额支付入口与支付密码【lead 复核关键点】

- entry/src/main/ets/service/api/OrdersApi.ets:136-149 —— 仅当 channel === 'BALANCE' 才带 {paymentPassword}。
- entry/src/main/ets/pages/OrderDetailPage.ets:286-353 —— 先校验 6 位数字，取到密码后立即把 state 里的输入清空再发请求；失败给出提示。
- entry/src/main/ets/pages/BalancePage.ets:186-204、556-597 —— 银行卡揭示同样要求 6 位支付密码，关闭弹窗与提交后都清空。
- 未发现"另一条余额扣款入口不传密码"的路径（服务端 deductBalance 也只有 1 个调用点，见主报告 N1）。

## C-04【否定】令牌存储

- entry/src/main/ets/service/TokenStorage.ets:96-161 —— HUKS AES-256-GCM（12 字节 nonce、16 字节 tag、AAD takeout-auth-v1）加密后再写 Preferences，损坏即自清。未发现明文 token。
（本条为审计线结论，我未逐行复核实现细节。）

## C-05【否定】跨账号残留

- entry/src/main/ets/service/AppStorageManager.ets:108-145 —— clearLocalSessionState 清空 authToken/user/balance/cart/addressList/currentAddress/couponList/orderList/favoriteList/stores/goodsMap/categoryList/selectedStoreId/currentOrderId/checkoutStoreId 等账号维度键，最后 await clearAllData()。
- AppStorageManager.ets:547-571 —— loginRemote 成功后对 CUSTOMER 重新同步地址与购物车。
- 未发现切换账号后旧账号地址/购物车残留的路径。
（本条为审计线结论。）

## C-06【否定】网页端导航隔离

- app.js:168-173 —— navigate(page) 断言 page 在当前 role 的 NAV 白名单内（store/checkout 例外），app.js:176-187 renderPage 按 state.role 分发。
- 全文件无 hashchange/popstate/?page= 路由解析 ⇒ "用 URL 直接打开管理页"不成立；管理 API 仍由服务端 401/403 兜底（线上实测 401）。

## C-07【否定】网页端 HTML 注入

- app.js:32 esc() 覆盖 & < > " ' ；用户可控串（地址、评价、备注、昵称）均经 esc() 进入 innerHTML。
- 通过脚本枚举未过 esc() 的插值，绝大多数为数值型 id/计数；少数（riderPhone、orderNo、stock、rating、role）取决于服务端是否允许自由文本，抽查后未见服务端接受任意字符串的字段。
- 结论：未发现可直接利用的存储型 XSS；但"数值性假定"本身脆弱，建议统一走 esc() 或改用 textContent。

## 未测与原因

- 未做 ArkTS 全量构建（约 5-10 分钟，本轮无 ArkTS 代码改动，无构建必要）。
- 未做真机联调（无设备）。
- 未对线上做任何登录/写操作（边界约束）。
