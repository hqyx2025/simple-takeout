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
    'orders': '/api/orders',
    'merchantOrders': '/api/merchant/orders',
    'merchantStats': '/api/merchant/stats',
    'merchantStores': '/api/merchant/stores',
    'coupons': '/api/coupons',
    'favorites': '/api/favorites',
    'addresses': '/api/addresses'
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
