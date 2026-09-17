/**
 * 数据模型定义
 */

// 用户角色类型
export enum UserRole {
  CUSTOMER = 0,    // 普通用户（点餐）
  MERCHANT = 1,    // 商户（管理自己的店铺、商品和订单）
  ADMIN = 2,       // 管理端（管理平台分类、店铺和托管订单）
  RIDER = 3        // 骑手（接单、取餐、送达）
}

// 分类模型（type：PLATFORM 平台分类 / MERCHANT 商户分类，商户分类带 merchantId/sort）
export interface Category {
  id: number
  name: string
  icon: string
  color: string
  type?: string
  merchantId?: number
  sort?: number
}

/** 首页分类导航的默认展示数据；服务端返回成功后会以服务端数据为准。 */
export function createDefaultCategories(): Category[] {
  return [
    { id: 1, name: '美食', icon: '🍔', color: '#FF6B35' },
    { id: 2, name: '快餐', icon: '🍟', color: '#FFB74D' },
    { id: 3, name: '饮品', icon: '🧋', color: '#4FC3F7' },
    { id: 4, name: '甜品', icon: '🍰', color: '#F06292' },
    { id: 5, name: '火锅', icon: '🍲', color: '#E53935' },
    { id: 6, name: '烧烤', icon: '🍢', color: '#FF7043' },
    { id: 7, name: '面食', icon: '🍜', color: '#FFA726' },
    { id: 8, name: '寿司', icon: '🍣', color: '#66BB6A' }
  ]
}

// 菜品规格（多规格 SKU）：同一菜品下每个规格独立定价与库存
export interface GoodsSpec {
  id: number
  goodsId: number
  name: string
  price: number
  stock: number
  sort?: number
  status?: number
}

// 商品模型
// stock：库存（0 表示售罄）；merchantCategoryId：商户店内分类（0=未分组）
// specs：多规格列表；非空时 price=规格最低价、stock=规格库存合计，下单必须带 specId
export interface GoodsItem {
  id: number
  storeId?: number
  name: string
  description: string
  price: number
  originalPrice?: number
  image: string
  categoryId: number
  merchantCategoryId?: number
  stock?: number
  sales: number
  rating: number
  tag?: string
  isOnShelf?: boolean
  isSpecial?: boolean
  specs?: GoodsSpec[]
}

/** 首页特价团购商品，附带店铺信息用于展示和跳转。 */
export interface SpecialGoodsItem {
  goods: GoodsItem
  storeName: string
  storeDistance: string
}

// 店铺模型
export interface StoreItem {
  id: number
  name: string
  image: string
  rating: number
  monthlySales: number
  deliveryFee: number
  minOrder: number
  deliveryTime: string
  distance: string
  tags: string[]
  notice: string
  address?: string
  latitude?: number
  longitude?: number
  categoryId: number
  categoryIds?: number[]
  ownerId: number  // 商户用户ID
  recommended?: number // 平台是否推荐到发现页：0否 1是
}

// 购物车/订单商品项
// 多规格：specId/specName 记录所选规格；price 为该行实际结算单价（规格价优先）
export interface CartItem {
  goods: GoodsItem
  quantity: number
  storeId: number
  storeName: string
  specId?: number
  specName?: string
  price?: number
  stock?: number
}

// 地址模型
export interface Address {
  id: number
  name: string
  phone: string
  address: string
  detail: string
  isDefault: boolean
  tag?: string
  latitude?: number  // 定位经纬度（定位选点地址才有，用于地图回显）
  longitude?: number
}

// 已绑定银行卡（钱包页展示；卡号由服务端掩码后下发，客户端拿不到完整卡号）
export interface BankCard {
  id: number
  bankName: string
  cardType: string
  cardNoMasked: string
  isDefault: boolean
  createTime: string
}

// 优惠券模型
export interface Coupon {
  id: number
  amount: number
  minOrder: number
  startTime: string
  endTime: string
  used: boolean
  storeId?: number
  storeName?: string
  condition: string
}

// 订单模型
export interface Order {
  id: number
  storeId: number
  storeName: string
  storeImage: string
  items: CartItem[]
  totalPrice: number
  deliveryFee: number
  discountAmount: number
  payAmount: number
  status: number
  /** 托管款状态：0托管中，1已结算给商户，2已退款 */
  escrowStatus?: number
  /** 是否已评价：0未评价 1已评价（后端 orders.reviewed） */
  reviewed?: number
  createTime: string
  payTime?: string
  deliverTime?: string
  completeTime?: string
  cancelTime?: string
  /** 预约送达时间（空=立即送达） */
  expectTime?: string
  /** 待付款订单的支付截止时间（非待付款为空串），前端据此倒计时 */
  payDeadline?: string
  /** 服务端计算的支付截止毫秒时间戳，避免前端解析字符串时区问题 */
  payDeadlineEpochMs?: number
  /** 下单使用的优惠券 ID（0=未使用），待付款取消时由后端自动退回 */
  couponId?: number
  orderNo?: string
  /** 配送骑手姓名/电话（配送中及之后返回） */
  riderName?: string
  riderPhone?: string
  /** 商户出餐时间：非空表示已出餐并已进入骑手待取餐池（此时数字状态仍为 2 制作中） */
  readyTime?: string
  address: Address
  remark: string
}

// 用户模型（支持双角色）
export interface User {
  id: number
  username: string
  avatar: string
  phone: string
  password: string
  role: UserRole
  balance: number
  coupons: Coupon[]
  orders: Order[]
  storeIds: number[]  // 商户拥有的店铺ID列表（仅商户有值）
}

/** 未登录用户占位状态，不包含任何测试账号或业务数据。 */
export function createEmptyUser(): User {
  const user: User = {
    id: 0,
    username: '未登录',
    avatar: '',
    phone: '',
    password: '',
    role: UserRole.CUSTOMER,
    balance: 0,
    coupons: [],
    orders: [],
    storeIds: []
  }
  return user
}

// 商户店铺管理数据
export interface MerchantStoreData {
  storeId: number
  storeName: string
  goodsCount: number
  todayOrders: number
  todayRevenue: number
  status: string  // 营业中/休息中
}

// 评价模型
export interface Review {
  id: number
  orderId: number
  storeId: number
  goodsId: number
  userId: number
  username: string
  rating: number        // 1-5星
  content: string
  tags: string[]        // 评价标签
  images: string[]      // 评价图片（URL 列表，上传功能为演进项）
  anonymous: number     // 0 实名 / 1 匿名
  reply: string         // 商家回复
  replyTime: string     // 回复时间
  createTime: string
}

// 骑手档案（四端改造：role=3 对应的骑手业务资料）
export interface Rider {
  id: number
  userId: number
  name: string
  phone: string
  online: number       // 0 离线 / 1 在线
  totalOrders: number  // 累计完成配送单量
  totalIncome: number  // 累计配送收入
  status: number
  createTime: string
}

// 首页轮播 Banner（内容管理）
export interface Banner {
  id: number
  title: string
  subtitle: string
  image: string
  color: string
  linkType: string
  linkValue: string
  sort: number
  status: number
  createTime: string
}

// 平台公告（内容管理）
export interface Announcement {
  id: number
  title: string
  content: string
  status: number
  createTime: string
}

// 收藏模型
export interface Favorite {
  id: number
  userId: number
  storeId: number
  storeName: string
  storeImage: string
  createTime: string
}

// 限时秒杀（首页秒杀专区）
export interface SeckillItem {
  id: number
  goodsId: number
  goodsName: string
  image: string
  originalPrice: number
  price: number
  quota: number
  sold: number
  startTime: string
  endTime: string
  storeId: number
  storeName: string
  storeDistance: string
  /** 距结束剩余秒数（服务端计算） */
  remainSeconds: number
}

// 凑单提示：还差多少元起送 + 店内可凑单菜品
export interface BundleInfo {
  storeId: number
  storeName: string
  minOrder: number
  amount: number
  gap: number
  suggestions: GoodsItem[]
}

// 图片上传结果（相对地址，前端用 API_CONFIG.BASE_URL 拼接展示）
export interface UploadResult {
  url: string
  size: number
}

// 退款记录（用户申请退款 + 管理端审批）
export interface RefundRecord {
  id: number
  orderId: number
  userId: number
  merchantId: number
  reason: string
  amount: number
  status: string        // PENDING待审批 / REFUNDED已退款 / REJECTED已拒绝
  applyTime: string
  processTime?: string
  rejectReason?: string
}

// 配送时间轴节点
export interface DeliveryStep {
  status: number        // 对应订单状态码
  title: string         // 状态标题
  time: string          // 时间（空字符串表示未到达）
  completed: boolean    // 是否已完成
}

// 店铺内商品分类
export interface StoreCategory {
  id: number
  name: string
}

// 商户统计数据
export interface MerchantStatsData {
  todayOrders: number
  todayRevenue: number
  completedOrders: number
  totalOrders: number
  totalRevenue: number
}

// 管理端员工账号
export interface AdminEmployee {
  id: number
  username: string
  phone: string
  role: number
  status: number
  storeCount: number
  createTime: string
}

/** 平台商品监管视图 */
export interface AdminProduct {
  id: number
  storeId: number
  storeName: string
  name: string
  description: string
  price: number
  originalPrice: number
  image: string
  categoryId: number
  merchantCategoryId: number
  stock: number
  sales: number
  rating: number
  tag: string
  status: number
  createTime: string
}

/** 管理端商品分页结果 */
export interface AdminProductPage {
  list: AdminProduct[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

/** 管理端用户/商户账号 */
export interface AdminUser {
  id: number
  username: string
  phone: string
  role: number
  status: number
  balance: number
  storeCount: number
  createTime: string
}

export interface AdminHotGoods {
  goodsId: number
  goodsName: string
  storeId: number
  storeName: string
  sales: number
  price: number
  status: number
}

export interface AdminStatisticsData {
  totalUsers: number
  totalMerchants: number
  totalStores: number
  totalGoods: number
  totalOrders: number
  totalGmv: number
  settledAmount: number
  pendingEscrowAmount: number
  todayOrders: number
  todayGmv: number
  hotGoods: AdminHotGoods[]
}

export interface AdminTrendPoint {
  date: string
  orderCount: number
  gmv: number
}

export interface AdminOrderStatusCount {
  status: number
  count: number
}

export interface AdminTopStore {
  storeId: number
  storeName: string
  gmv: number
  orderCount: number
}

export interface AdminDashboard {
  overview: AdminStatisticsData
  trend: AdminTrendPoint[]
  orderStatuses: AdminOrderStatusCount[]
  topStores: AdminTopStore[]
}

export interface MarketingActivity {
  id: number
  storeId: number
  type: string
  title: string
  discountRate: number
  reduceAmount: number
  threshold: number
  giftGoodsId: number
  startTime: string
  endTime: string
  status: number
  createTime: string
}

export interface SetmealItem {
  id: number
  setmealId: number
  goodsId: number
  goodsName: string
  quantity: number
}

export interface Setmeal {
  id: number
  storeId: number
  name: string
  description: string
  price: number
  originalPrice: number
  image: string
  status: number
  createTime: string
  items: SetmealItem[]
}
