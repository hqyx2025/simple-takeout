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

// 订单状态文本
export function getOrderStatusText(status: number): string {
  if (status === 0) { return '待付款' }
  if (status === 1) { return '待接单' }
  if (status === 2) { return '制作中' }
  if (status === 3) { return '配送中' }
  if (status === 4) { return '已完成' }
  if (status === 5) { return '已取消' }
  if (status === 6) { return '退款中' }
  return '未知'
}

// 订单状态颜色
export function getOrderStatusColor(status: number): string {
  if (status === 0) { return '#FF6B35' }
  if (status === 1) { return '#FF9800' }
  if (status === 2) { return '#2196F3' }
  if (status === 3) { return '#4CAF50' }
  if (status === 4) { return '#999999' }
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

// 订单状态时间轴配置
export class ORDER_TIMELINE {
  static readonly STATUS_LIST: number[] = [1, 2, 3, 4]
  static readonly STATUS_TITLES: Record<string, string> = {
    '1': '已下单',
    '2': '制作中',
    '3': '配送中',
    '4': '已完成'
  }
}

// API端点常量（当前对接Mock，预留真实API结构）
export class API_CONFIG {
  static readonly BASE_URL: string = ''
  static readonly TIMEOUT: number = 10000
  static readonly ENDPOINTS: Record<string, string> = {
    'stores': '/api/stores',
    'goods': '/api/goods',
    'orders': '/api/orders',
    'user': '/api/user',
    'login': '/api/login',
    'register': '/api/register'
  }
}

// 高德地图配置（申请地址：https://lbs.amap.com）
export class AMAP_CONFIG {
  // TODO: 请将此处替换为你自己申请的高德“Web服务”类型API Key（用于逆地理编码/地点搜索）
  static readonly API_KEY: string = ''
  // TODO: 请将此处替换为高德“HarmonyOS”平台Key（用于地图SDK显示，需绑定应用签名appId）
  static readonly MAP_SDK_KEY: string = ''
  // 高德Web服务REST接口域名
  static readonly RESTO_URL: string = 'https://restapi.amap.com'
  // 网络请求超时（毫秒）
  static readonly TIMEOUT: number = 10000
}