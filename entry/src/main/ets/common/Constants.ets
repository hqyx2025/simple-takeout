/**
 * 全局常量定义
 */

// 品牌主色（业务数据用途的稳定 hex，不随深浅色变化）。
// 如分类展示色传给后端存储、Canvas 需要字符串色的场景使用。
export const COLORS_PRIMARY_HEX: string = '#FF6B35'

// 主题颜色 - 使用 class 避免 arkts-no-untyped-obj-literals
// 颜色已主题化为 app.color.* 双态资源（resources/base + resources/dark），
// 类型为 Resource 以便随系统深浅色自动切换；渲染属性（fontColor/backgroundColor 等
// ResourceColor 参数）直接传入即兼容，Canvas/API 等需要 string 的场景用
// ColorMetrics.resourceColor(X).color 运行时解析。
export class COLORS {
  static readonly PRIMARY: Resource = $r('app.color.primary')
  static readonly PRIMARY_LIGHT: Resource = $r('app.color.primary_light')
  static readonly PRIMARY_DARK: Resource = $r('app.color.primary_dark')
  static readonly SECONDARY: Resource = $r('app.color.secondary')
  static readonly TEXT_PRIMARY: Resource = $r('app.color.text_primary')
  static readonly TEXT_SECONDARY: Resource = $r('app.color.text_secondary')
  static readonly TEXT_HINT: Resource = $r('app.color.text_hint')
  static readonly TEXT_WHITE: Resource = $r('app.color.text_white')
  static readonly BG_PRIMARY: Resource = $r('app.color.bg_primary')
  static readonly BG_WHITE: Resource = $r('app.color.bg_white')
  static readonly BG_CARD: Resource = $r('app.color.bg_card')
  static readonly DIVIDER: Resource = $r('app.color.divider')
  static readonly SUCCESS: Resource = $r('app.color.success')
  static readonly WARNING: Resource = $r('app.color.warning')
  static readonly ERROR: Resource = $r('app.color.error')
  static readonly TAG_BG: Resource = $r('app.color.tag_bg')
  static readonly TAG_TEXT: Resource = $r('app.color.tag_text')
  static readonly PRICE_RED: Resource = $r('app.color.price_red')
  static readonly TAB_ACTIVE: Resource = $r('app.color.tab_active')
  static readonly TAB_INACTIVE: Resource = $r('app.color.tab_inactive')
  // 通用浅底色 / 遮罩 / 状态浅底色（新增，统一原来散落各处的硬编码色）
  static readonly WARM_BG: Resource = $r('app.color.warm_bg')
  static readonly OVERLAY: Resource = $r('app.color.overlay')
  static readonly ERROR_LIGHT: Resource = $r('app.color.error_light')
  static readonly SUCCESS_LIGHT: Resource = $r('app.color.success_light')
  static readonly WARNING_LIGHT: Resource = $r('app.color.warning_light')
}

// 间距
export class SPACING {
  static readonly XS: number = 4
  static readonly SM: number = 8
  static readonly MD: number = 12
  static readonly LG: number = 16
  static readonly XL: number = 20
  static readonly XXL: number = 24
}

// 字体大小
export class FONT_SIZE {
  static readonly XS: number = 10
  static readonly SM: number = 12
  static readonly MD: number = 14
  static readonly LG: number = 16
  static readonly XL: number = 18
  static readonly XXL: number = 20
  static readonly TITLE: number = 24
  static readonly BIG_TITLE: number = 28
}

// 圆角
export class BORDER_RADIUS {
  static readonly SM: number = 4
  static readonly MD: number = 8
  static readonly LG: number = 12
  static readonly XL: number = 16
  static readonly ROUND: number = 20
  static readonly CIRCLE: number = 999
}

// 订单状态文本（status=4 时需结合托管状态 escrowStatus 区分：
// 0=已送达待用户确认收货，1=已结算完成；与大纲 6.4/21.6 口径一致）
export function getOrderStatusText(status: number, escrowStatus?: number): string {
  if (status === 0) { return '待付款' }
  if (status === 1) { return '待接单' }
  if (status === 2) { return '制作中' }
  if (status === 3) { return '配送中' }
  if (status === 4) { return (escrowStatus ?? 0) === 1 ? '已完成' : '已送达，待确认收货' }
  if (status === 5) { return '已取消' }
  if (status === 6) { return '退款中' }
  return '未知'
}

// 订单状态颜色（status=4 时按托管状态区分，待确认用橙色醒目标识）
export function getOrderStatusColor(status: number, escrowStatus?: number): ResourceColor {
  if (status === 0) { return $r('app.color.primary') }
  if (status === 1) { return $r('app.color.warning') }
  if (status === 2) { return $r('app.color.module_search') }
  if (status === 3) { return $r('app.color.success') }
  if (status === 4) { return (escrowStatus ?? 0) === 1 ? $r('app.color.text_hint') : $r('app.color.warning') }
  if (status === 5) { return $r('app.color.text_hint') }
  if (status === 6) { return $r('app.color.error') }
  return $r('app.color.text_hint')
}

// 评价标签
export class REVIEW_TAGS {
  static readonly GOOD_TASTE: string = '味道好'
  static readonly FAST_DELIVERY: string = '配送快'
  static readonly FRESH: string = '食材新鲜'
  static readonly GOOD_SERVICE: string = '服务好'
  static readonly LARGE_PORTION: string = '分量足'
  static readonly CLEAN: string = '干净卫生'
  static readonly RECOMMEND: string = '推荐'
  static readonly WILL_REORDER: string = '会回购'
}

export function formatSales(sales: number): string {
  if (sales >= 10000) {
    return (sales / 10000).toFixed(1) + '万'
  }
  return sales.toString()
}

// 订单状态时间轴配置
export class ORDER_TIMELINE {
  static readonly STATUS_LIST: number[] = [1, 2, 3, 4]
  static readonly STATUS_TITLES: Record<string, string> = {
    '1': '已下单',
    '2': '制作中',
    '3': '配送中',
    '4': '已送达'
  }
}

// API端点常量
// BASE_URL：模拟器访问宿主机用 10.0.2.2；真机联调改为电脑局域网 IP，如 http://192.168.1.100:9000
export class API_CONFIG {
  static readonly DEV_BASE_URL: string = 'http://10.0.2.2:9000'
  static readonly RELEASE_BASE_URL: string = 'https://api.example.com'
  // Release 构建前改为 true，并将 RELEASE_BASE_URL 替换为真实 HTTPS 域名。
  static readonly USE_HTTPS: boolean = false
  static readonly BASE_URL: string = API_CONFIG.USE_HTTPS
    ? API_CONFIG.RELEASE_BASE_URL
    : API_CONFIG.DEV_BASE_URL
  static readonly TIMEOUT: number = 10000
  static readonly ENDPOINTS: Record<string, string> = {
    'categories': '/api/categories',
    'stores': '/api/stores',
    'search': '/api/search',
    'login': '/api/auth/login',
    'register': '/api/auth/register',
    'recharge': '/api/auth/recharge',
    'orders': '/api/orders',
    'merchantOrders': '/api/merchant/orders',
    'merchantStats': '/api/merchant/stats',
    'merchantStores': '/api/merchant/stores',
    'coupons': '/api/coupons',
    'favorites': '/api/favorites',
    'addresses': '/api/addresses',
    'upload': '/api/upload',
    'seckills': '/api/seckills',
    'rankStores': '/api/rankings/stores',
    'rankGoods': '/api/rankings/goods'
  }
}

// 高德地图配置（申请地址：https://lbs.amap.com，创建“Web端(JS API)”类型Key）
export class AMAP_CONFIG {
  // 高德 Web端(JS API) Key：用于地图显示/选点/逆地理编码/地点搜索（模拟器与真机均可运行）
  // 注意：更换Key时需同步修改 resources/rawfile/amap_map.html 中的 AMAP_KEY 常量
  static readonly MAP_JS_KEY: string = 'a0373d4b39b6524b7f80e825339e7a28'
  // 高德 JS API 安全密钥（jscode）：若申请Key时生成了安全密钥，请填入并同步修改 amap_map.html
  static readonly MAP_JS_SECURITY_CODE: string = ''
  // 网络请求超时（毫秒）
  static readonly TIMEOUT: number = 10000
}

/**
 * 商户上传图片的默认占位图。
 * 资源位置：entry/src/main/resources/rawfile/images/default/merchant_goods_default.png
 * 图片资源的目录约定与新增流程见 md/图片资源规范.md。
 */
export const DEFAULT_MERCHANT_IMAGE: Resource = $rawfile('images/default/merchant_goods_default.png')

/**
 * 商户上传图片地址 → 可渲染的图片来源。
 * 后端返回的是相对地址（/uploads/yyyyMMdd/xxx.png），必须拼 API 基址；
 * 地址为空（菜品没传图）时回退默认占位图，避免用户端出现空白/破图。
 */
export function merchantImageSource(image: string | undefined): ResourceStr {
  const url: string = (image ?? '').trim()
  if (url === '') {
    return DEFAULT_MERCHANT_IMAGE
  }
  if (url.indexOf('http://') === 0 || url.indexOf('https://') === 0) {
    return url
  }
  return url.startsWith('/') ? API_CONFIG.BASE_URL + url : url
}

/**
 * 功能模块主题色：一个模块一种颜色，同一模块在所有页面保持一致。
 * 用途：模块标题、模块图标底、分区强调色，避免整屏只有白底 + 灰字（"很多空白"的观感来源之一）。
 */
export class MODULE_COLOR {
  static readonly HOME: Resource = $r('app.color.module_home')
  static readonly SECKILL: Resource = $r('app.color.module_seckill')
  static readonly NEARBY: Resource = $r('app.color.module_nearby')
  static readonly SPECIAL: Resource = $r('app.color.module_special')
  static readonly RANKING: Resource = $r('app.color.module_ranking')
  static readonly COUPON: Resource = $r('app.color.module_coupon')
  static readonly CART: Resource = $r('app.color.module_cart')
  static readonly ORDER: Resource = $r('app.color.module_order')
  static readonly MINE: Resource = $r('app.color.module_mine')
  static readonly SEARCH: Resource = $r('app.color.module_search')
  static readonly FAVORITE: Resource = $r('app.color.module_favorite')
  static readonly REVIEW: Resource = $r('app.color.module_review')
  static readonly MERCHANT: Resource = $r('app.color.module_merchant')
  static readonly RIDER: Resource = $r('app.color.module_rider')
  static readonly ADMIN: Resource = $r('app.color.module_admin')
}

/** 模块浅底色：与 MODULE_COLOR 一一配对，用于模块标题条/分区卡片背景。 */
export class MODULE_BG {
  static readonly HOME: Resource = $r('app.color.module_bg_home')
  static readonly SECKILL: Resource = $r('app.color.module_bg_seckill')
  static readonly NEARBY: Resource = $r('app.color.module_bg_nearby')
  static readonly SPECIAL: Resource = $r('app.color.module_bg_special')
  static readonly RANKING: Resource = $r('app.color.module_bg_ranking')
  static readonly COUPON: Resource = $r('app.color.module_bg_coupon')
  static readonly CART: Resource = $r('app.color.module_bg_cart')
  static readonly ORDER: Resource = $r('app.color.module_bg_order')
  static readonly MINE: Resource = $r('app.color.module_bg_mine')
  static readonly SEARCH: Resource = $r('app.color.module_bg_search')
  static readonly FAVORITE: Resource = $r('app.color.module_bg_favorite')
  static readonly REVIEW: Resource = $r('app.color.module_bg_review')
  static readonly MERCHANT: Resource = $r('app.color.module_bg_merchant')
  static readonly RIDER: Resource = $r('app.color.module_bg_rider')
  static readonly ADMIN: Resource = $r('app.color.module_bg_admin')
}

/** 逐项取色的浅色底 / 前景色板（成对），让相邻卡片、图标底颜色不相同。 */
export class ACCENT {
  static readonly BG: Resource[] = [$r('app.color.accent_bg_0'), $r('app.color.accent_bg_1'), $r('app.color.accent_bg_2'),
    $r('app.color.accent_bg_3'), $r('app.color.accent_bg_4'), $r('app.color.accent_bg_5'),
    $r('app.color.accent_bg_6'), $r('app.color.accent_bg_7')]
  static readonly FG: Resource[] = [$r('app.color.accent_fg_0'), $r('app.color.accent_fg_1'), $r('app.color.accent_fg_2'),
    $r('app.color.accent_fg_3'), $r('app.color.accent_fg_4'), $r('app.color.accent_fg_5'),
    $r('app.color.accent_fg_6'), $r('app.color.accent_fg_7')]
}

/** 第 index 项的浅色底（确定性轮转，不用随机数，避免每次渲染跳色）。 */
export function accentBg(index: number): Resource {
  const list: Resource[] = ACCENT.BG
  return list[Math.abs(index) % list.length]
}

/** 第 index 项的前景色（与 accentBg 成对，保证对比度）。 */
export function accentFg(index: number): Resource {
  const list: Resource[] = ACCENT.FG
  return list[Math.abs(index) % list.length]
}

/**
 * 由文本/名称推导取色序号：同一个名称永远同一色，不同名称大概率不同色。
 * 用于没有天然序号的位置（菜单行、资产项），省掉逐处传 index 的样板代码。
 */
export function accentIndexFromText(text: string): number {
  let sum: number = 0
  for (let i = 0; i < text.length; i++) {
    sum += text.charCodeAt(i)
  }
  return sum
}
