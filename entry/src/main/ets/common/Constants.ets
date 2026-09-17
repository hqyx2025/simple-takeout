/**
 * 全局常量定义
 */

// 主题颜色 - 使用 class 避免 arkts-no-untyped-obj-literals
export class COLORS {
  static readonly PRIMARY: string = '#FF6B35'
  static readonly PRIMARY_LIGHT: string = '#FF8C5A'
  static readonly PRIMARY_DARK: string = '#E55A2B'
  static readonly SECONDARY: string = '#FFD700'
  static readonly TEXT_PRIMARY: string = '#333333'
  static readonly TEXT_SECONDARY: string = '#666666'
  static readonly TEXT_HINT: string = '#999999'
  static readonly TEXT_WHITE: string = '#FFFFFF'
  static readonly BG_PRIMARY: string = '#F5F5F5'
  static readonly BG_WHITE: string = '#FFFFFF'
  static readonly BG_CARD: string = '#FFFFFF'
  static readonly DIVIDER: string = '#EEEEEE'
  static readonly SUCCESS: string = '#4CAF50'
  static readonly WARNING: string = '#FF9800'
  static readonly ERROR: string = '#F44336'
  static readonly TAG_BG: string = '#FFF3E0'
  static readonly TAG_TEXT: string = '#FF6B35'
  static readonly PRICE_RED: string = '#FF3B30'
  static readonly TAB_ACTIVE: string = '#FF6B35'
  static readonly TAB_INACTIVE: string = '#999999'
  // 通用浅底色 / 遮罩 / 状态浅底色（新增，统一原来散落各处的硬编码色）
  static readonly WARM_BG: string = '#FFF3E8'
  static readonly OVERLAY: string = 'rgba(0,0,0,0.5)'
  static readonly ERROR_LIGHT: string = '#FFF0F0'
  static readonly SUCCESS_LIGHT: string = '#E8F5E9'
  static readonly WARNING_LIGHT: string = '#FFF7E6'
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
export function getOrderStatusColor(status: number, escrowStatus?: number): string {
  if (status === 0) { return '#FF6B35' }
  if (status === 1) { return '#FF9800' }
  if (status === 2) { return '#2196F3' }
  if (status === 3) { return '#4CAF50' }
  if (status === 4) { return (escrowStatus ?? 0) === 1 ? '#999999' : '#FF9800' }
  if (status === 5) { return '#999999' }
  if (status === 6) { return '#F44336' }
  return '#999999'
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
  static readonly HOME: string = '#FF6B35'
  static readonly SECKILL: string = '#FF3B30'
  static readonly NEARBY: string = '#2F80ED'
  static readonly SPECIAL: string = '#F2994A'
  static readonly RANKING: string = '#8E44AD'
  static readonly COUPON: string = '#E0526E'
  static readonly CART: string = '#27AE60'
  static readonly ORDER: string = '#2D9CDB'
  static readonly MINE: string = '#00838F'
  static readonly SEARCH: string = '#2196F3'
  static readonly FAVORITE: string = '#D6455D'
  static readonly REVIEW: string = '#9B51E0'
  static readonly MERCHANT: string = '#B25E39'
  static readonly RIDER: string = '#0F9D58'
  static readonly ADMIN: string = '#5B6B8C'
}

/** 模块浅底色：与 MODULE_COLOR 一一配对，用于模块标题条/分区卡片背景。 */
export class MODULE_BG {
  static readonly HOME: string = '#FFF3E8'
  static readonly SECKILL: string = '#FFEDEA'
  static readonly NEARBY: string = '#EAF2FE'
  static readonly SPECIAL: string = '#FFF4E5'
  static readonly RANKING: string = '#F3EBFA'
  static readonly COUPON: string = '#FDECEF'
  static readonly CART: string = '#EAF7EF'
  static readonly ORDER: string = '#E9F4FC'
  static readonly MINE: string = '#E6F3F4'
  static readonly SEARCH: string = '#E9F3FE'
  static readonly FAVORITE: string = '#FCEAEE'
  static readonly REVIEW: string = '#F4EBFC'
  static readonly MERCHANT: string = '#F7EDE7'
  static readonly RIDER: string = '#E8F6EE'
  static readonly ADMIN: string = '#EDF0F6'
}

/** 逐项取色的浅色底 / 前景色板（成对），让相邻卡片、图标底颜色不相同。 */
export class ACCENT {
  static readonly BG: string[] = ['#FFE3D3', '#FFE0E6', '#E3EEFF', '#E4F6E9',
    '#FFF3D6', '#EFE4FB', '#DFF3F5', '#FCE6DC']
  static readonly FG: string[] = ['#E55A2B', '#D6455D', '#2F80ED', '#27AE60',
    '#C99A05', '#8E44AD', '#00838F', '#B25E39']
}

/** 第 index 项的浅色底（确定性轮转，不用随机数，避免每次渲染跳色）。 */
export function accentBg(index: number): string {
  const list: string[] = ACCENT.BG
  return list[Math.abs(index) % list.length]
}

/** 第 index 项的前景色（与 accentBg 成对，保证对比度）。 */
export function accentFg(index: number): string {
  const list: string[] = ACCENT.FG
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
