/**
 * 数据模型定义
 */

// 用户角色类型
export enum UserRole {
  CUSTOMER = 0,    // 普通用户（点餐）
  MERCHANT = 1,    // 商户（管理自己的店铺、商品和订单）
  ADMIN = 2        // 管理端（管理平台分类、店铺和托管订单）
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

// 商品模型
// stock：库存（0 表示售罄）；merchantCategoryId：商户店内分类（0=未分组）
export interface GoodsItem {
  id: number
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
  categoryId: number
  categoryIds?: number[]
  ownerId: number  // 商户用户ID
  recommended?: number // 平台是否推荐到发现页：0否 1是
}

// 购物车商品项
export interface CartItem {
  goods: GoodsItem
  quantity: number
  storeId: number
  storeName: string
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
