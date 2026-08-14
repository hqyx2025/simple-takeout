/**
 * 数据模型定义
 */

// 用户角色类型
export enum UserRole {
  CUSTOMER = 0,    // 普通用户（点餐）
  MERCHANT = 1     // 商户（上架店铺/食物）
}

// 分类模型
export interface Category {
  id: number
  name: string
  icon: string
  color: string
}

// 商品模型
export interface GoodsItem {
  id: number
  name: string
  description: string
  price: number
  originalPrice?: number
  image: string
  categoryId: number
  sales: number
  rating: number
  tag?: string
  isOnShelf?: boolean
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
