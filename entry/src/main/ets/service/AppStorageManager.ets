/**
 * 全局状态管理 - 使用AppStorage管理应用级状态
 */
import { CartItem, Order, Address, Coupon, User, UserRole, StoreItem, GoodsItem, Favorite, Review, MerchantStatsData, Category, RefundRecord, createEmptyUser, createDefaultCategories } from '../model/Models'
import { saveAllData, clearAllData } from './DataPersistence'
import { apiLogin, apiRegister, updateUserProfileApi, fetchCategories, fetchStores, fetchStoreGoods, fetchUserOrdersApi, fetchOrderDetailApi, fetchMerchantOrdersApi, createOrderApi, cancelOrderApi, confirmOrderApi, merchantActionApi, toggleFavoriteApi, fetchFavoritesApi, fetchCouponsApi, fetchAddressesApi, addAddressApi, addAddressAndFetchApi, deleteAddressApi, updateAddressApi, setDefaultAddressApi, claimCouponApi, fetchMerchantStoresApi, searchStoresApi, fetchStoreReviews, submitReviewApi, applyRefundApi, fetchCartApi, addCartItemApi, updateCartItemQuantityApi, deleteCartItemApi, deleteCartItemsApi, clearCartApi } from './ApiService'
import { getAuthToken, setAuthToken, getLastApiErrorMessage } from './HttpClient'
import { logInfo, logWarn, logError } from './AppLogger'
import { GeoPosition } from './LocationService'

let categoriesSyncInFlight: Promise<void> | null = null
let storesSyncInFlight: Promise<void> | null = null

// 初始化全局数据
export function initAppStorage() {
  const existingCategories: Category[] | undefined = AppStorage.get<Category[]>('categoryList')
  if (existingCategories === undefined || existingCategories.length === 0) {
    AppStorage.setOrCreate<Category[]>('categoryList', createDefaultCategories())
  }
  // 如果持久化数据已加载，跳过默认值初始化
  if (AppStorage.get<boolean>('_persistenceReady') && AppStorage.get<boolean>('privacyConsent')) {
    return
  }
  if (!AppStorage.has('isLoggedIn')) {
    AppStorage.setOrCreate<boolean>('isLoggedIn', false)
  }
  if (!AppStorage.has('user')) {
    AppStorage.setOrCreate<User>('user', createEmptyUser())
  }
  if (!AppStorage.has('cartItems')) {
    AppStorage.setOrCreate<CartItem[]>('cartItems', [])
  }
  if (!AppStorage.has('addressList')) {
    AppStorage.setOrCreate<Address[]>('addressList', [])
  }
  // 不默认设置 currentAddress：用户未定位/未选择地址时保持空，主页显示“未定位”提示去定位
  if (!AppStorage.has('currentAddress')) {
    AppStorage.setOrCreate<Address | null>('currentAddress', null)
  }
  if (!AppStorage.has('orderList')) {
    AppStorage.setOrCreate<Order[]>('orderList', [])
  }
  if (!AppStorage.has('couponList')) {
    AppStorage.setOrCreate<Coupon[]>('couponList', [])
  }
  if (!AppStorage.has('selectedCoupon')) {
    AppStorage.setOrCreate<Coupon | null>('selectedCoupon', null)
  }
  if (!AppStorage.has('categoryList')) {
    AppStorage.setOrCreate<Category[]>('categoryList', createDefaultCategories())
  }
  // 动态店铺和商品数据（商户可修改）
  if (!AppStorage.has('allStores')) {
    AppStorage.setOrCreate<StoreItem[]>('allStores', [])
  }
  if (!AppStorage.has('allGoodsMap')) {
    AppStorage.setOrCreate<Record<string, GoodsItem[]>>('allGoodsMap', {})
  }
  if (!AppStorage.has('favoriteList')) {
    AppStorage.setOrCreate<Favorite[]>('favoriteList', [])
  }
  if (!AppStorage.has('reviewList')) {
    AppStorage.setOrCreate<Review[]>('reviewList', [])
  }
  if (!AppStorage.has('claimableCoupons')) {
    AppStorage.setOrCreate<Coupon[]>('claimableCoupons', [])
  }
  logInfo('AppStorage', 'initAppStorage 完成，全局数据初始化就绪')
}

// ============ 登录/登出 ============
export function logout(): void {
  setAuthToken('')
  AppStorage.setOrCreate<string>('authToken', '')
  AppStorage.setOrCreate<boolean>('isLoggedIn', false)
  AppStorage.setOrCreate<User>('user', createEmptyUser())
  AppStorage.setOrCreate<CartItem[]>('cartItems', [])
  AppStorage.setOrCreate<Address[]>('addressList', [])
  AppStorage.setOrCreate<Address | null>('currentAddress', null)
  AppStorage.setOrCreate<GeoPosition | null>('lastLocationPosition', null)
  clearAllData()
  logInfo('Auth', '用户退出登录，已清除登录态与购物车')
}

export function isLoggedIn(): boolean {
  return AppStorage.get<boolean>('isLoggedIn') || false
}

export function getLastRemoteErrorMessage(): string {
  return getLastApiErrorMessage()
}

// ============ 获取当前用户 ============
export function getCurrentUser(): User | undefined {
  return AppStorage.get<User>('user')
}

// ============ 购物车操作 ============
export function addToCart(item: CartItem): void {
  const savedCart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
  const cart: CartItem[] = savedCart.slice()
  const existIndex = cart.findIndex(c => c.goods.id === item.goods.id && c.storeId === item.storeId)
  if (existIndex >= 0) {
    const current: CartItem = cart[existIndex]
    cart[existIndex] = {
      goods: current.goods,
      quantity: current.quantity + item.quantity,
      storeId: current.storeId,
      storeName: current.storeName
    }
  } else {
    cart.push(item)
  }
  AppStorage.setOrCreate<CartItem[]>('cartItems', cart)
  saveAllData()
  logInfo('Cart', `加入购物车 goods=${item.goods.name} x${item.quantity} storeId=${item.storeId}`)
}

export function updateCartItemQuantity(goodsId: number, storeId: number, quantity: number): void {
  const savedCart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
  let cart: CartItem[] = savedCart.slice()
  if (quantity <= 0) {
    cart = cart.filter(c => !(c.goods.id === goodsId && c.storeId === storeId))
  } else {
    const itemIndex: number = cart.findIndex(c => c.goods.id === goodsId && c.storeId === storeId)
    if (itemIndex >= 0) {
      const current: CartItem = cart[itemIndex]
      cart[itemIndex] = {
        goods: current.goods,
        quantity: quantity,
        storeId: current.storeId,
        storeName: current.storeName
      }
    }
  }
  AppStorage.setOrCreate<CartItem[]>('cartItems', cart)
  saveAllData()
  logInfo('Cart', `更新购物车数量 goodsId=${goodsId} storeId=${storeId} quantity=${quantity}`)
}

export function clearCart(): void {
  AppStorage.setOrCreate<CartItem[]>('cartItems', [])
  saveAllData()
  logInfo('Cart', '清空购物车')
}

function setRemoteCart(cart: CartItem[]): void {
  AppStorage.setOrCreate<CartItem[]>('cartItems', cart)
  saveAllData()
}

export async function syncCartRemote(): Promise<boolean> {
  if (!isLoggedIn()) {
    return false
  }
  const remoteCart: CartItem[] | null = await fetchCartApi()
  if (remoteCart === null) {
    logWarn('Api', '同步购物车失败，保留本地购物车')
    return false
  }
  const localCart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
  const shouldMigrateLocalCart: boolean = false
  // 首次接入后端时迁移已有本地购物车，避免用户升级后购物车商品丢失。
  if (shouldMigrateLocalCart && remoteCart.length === 0 && localCart.length > 0) {
    for (let i = 0; i < localCart.length; i++) {
      await addCartItemApi(localCart[i].goods.id, localCart[i].quantity)
    }
    const migratedCart: CartItem[] | null = await fetchCartApi()
    if (migratedCart !== null) {
      setRemoteCart(migratedCart)
      logInfo('Api', `迁移本地购物车 ${migratedCart.length} 条`)
      return true
    }
  }
  setRemoteCart(remoteCart)
  logInfo('Api', `同步购物车 ${remoteCart.length} 条`)
  return true
}

export async function addCartItemRemote(item: CartItem): Promise<boolean> {
  const remoteCart: CartItem[] | null = await addCartItemApi(item.goods.id, item.quantity)
  if (remoteCart === null) {
    return false
  }
  setRemoteCart(remoteCart)
  return true
}

export async function updateCartItemQuantityRemote(goodsId: number, quantity: number): Promise<boolean> {
  const remoteCart: CartItem[] | null = await updateCartItemQuantityApi(goodsId, quantity)
  if (remoteCart === null) {
    return false
  }
  setRemoteCart(remoteCart)
  return true
}

export async function deleteCartItemRemote(goodsId: number): Promise<boolean> {
  const remoteCart: CartItem[] | null = await deleteCartItemApi(goodsId)
  if (remoteCart === null) {
    return false
  }
  setRemoteCart(remoteCart)
  return true
}

export async function deleteCartItemsRemote(goodsIds: number[]): Promise<boolean> {
  const remoteCart: CartItem[] | null = await deleteCartItemsApi(goodsIds)
  if (remoteCart === null) {
    return false
  }
  setRemoteCart(remoteCart)
  return true
}

export async function clearCartRemote(): Promise<boolean> {
  const remoteCart: CartItem[] | null = await clearCartApi()
  if (remoteCart === null) {
    return false
  }
  setRemoteCart(remoteCart)
  return true
}

export function getGoodsForStore(storeId: number): GoodsItem[] {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  return goodsMap[storeId.toString()] || []
}

export function getAllStoresList(): StoreItem[] {
  return AppStorage.get<StoreItem[]>('allStores') || []
}

export function getStoresByOwner(ownerId: number): StoreItem[] {
  const stores: StoreItem[] = AppStorage.get<StoreItem[]>('allStores') || []
  return stores.filter(s => s.ownerId === ownerId)
}

// 地址同步去重：同一用户重复确认当前位置可能在服务端生成多条相同地址，
// 页面只保留一条，且优先保留默认标记和完整经纬度。
export function deduplicateAddresses(addresses: Address[]): Address[] {
  const result: Address[] = []
  for (let i = 0; i < addresses.length; i++) {
    const address: Address = addresses[i]
    const key: string = `${address.name}|${address.phone}|${address.address}|${address.detail}`
    const index: number = result.findIndex((item: Address) => {
      return `${item.name}|${item.phone}|${item.address}|${item.detail}` === key
    })
    if (index < 0) {
      result.push(address)
      continue
    }
    const existing: Address = result[index]
    existing.isDefault = existing.isDefault || address.isDefault
    if (existing.latitude === undefined && address.latitude !== undefined) {
      existing.latitude = address.latitude
    }
    if (existing.longitude === undefined && address.longitude !== undefined) {
      existing.longitude = address.longitude
    }
  }
  return result
}

// ============ 工具方法 ============
export function formatPrice(price: number): string {
  return '¥' + price.toFixed(2)
}

export function getFavorites(): Favorite[] {
  const user: User | undefined = AppStorage.get<User>('user')
  if (user === undefined || user === null) return []
  const favorites: Favorite[] = AppStorage.get<Favorite[]>('favoriteList') || []
  return favorites.filter(f => f.userId === user.id)
}

export function isFavorited(storeId: number): boolean {
  const user: User | undefined = AppStorage.get<User>('user')
  if (user === undefined || user === null) return false
  const favorites: Favorite[] = AppStorage.get<Favorite[]>('favoriteList') || []
  return favorites.some(f => f.storeId === storeId && f.userId === user.id)
}

// 商户获取自己店铺的订单
export function getMerchantOrders(merchantId: number): Order[] {
  const stores: StoreItem[] = getStoresByOwner(merchantId)
  const storeIds: number[] = stores.map(s => s.id)
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  return orders.filter(o => storeIds.includes(o.storeId))
}

// ============ 商户收入统计 ============
export function getMerchantTodayStats(merchantId: number): MerchantStatsData {
  const orders: Order[] = getMerchantOrders(merchantId)
  const today = new Date()
  const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

  const todayOrders = orders.filter(o => o.createTime.startsWith(todayStr))
  // 收入口径与大纲 21.4 一致：仅统计已结算订单（status=4 且 escrow=1，用户确认收货后）
  const completedOrders = todayOrders.filter(o => o.status === 4 && (o.escrowStatus ?? 0) === 1)
  const revenue = completedOrders.reduce((sum, o) => sum + o.payAmount, 0)

  const stats: MerchantStatsData = {
    todayOrders: todayOrders.length,
    todayRevenue: revenue,
    completedOrders: completedOrders.length,
    totalOrders: orders.length,
    totalRevenue: orders.filter(o => o.status === 4 && (o.escrowStatus ?? 0) === 1).reduce((sum, o) => sum + o.payAmount, 0)
  }
  return stats
}

export function getMerchantWeekStats(merchantId: number): MerchantStatsData {
  const orders: Order[] = getMerchantOrders(merchantId)
  const now = new Date()
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)

  const weekOrders = orders.filter(o => {
    const orderTime: number = Date.parse(o.createTime.replace(/-/g, '/'))
    return !Number.isNaN(orderTime) && orderTime >= weekAgo.getTime()
  })
  const completedOrders = weekOrders.filter(o => o.status === 4 && (o.escrowStatus ?? 0) === 1)
  const revenue = completedOrders.reduce((sum, o) => sum + o.payAmount, 0)

  const stats: MerchantStatsData = {
    todayOrders: weekOrders.length,
    todayRevenue: revenue,
    completedOrders: completedOrders.length,
    totalOrders: orders.length,
    totalRevenue: orders.filter(o => o.status === 4 && (o.escrowStatus ?? 0) === 1).reduce((sum, o) => sum + o.payAmount, 0)
  }
  return stats
}

// 近7天（含今日）每日已完成订单收入，索引0为7天前，索引6为今日
// 供商户收入统计页折线图使用
export function getMerchantWeekRevenue(merchantId: number): number[] {
  const orders: Order[] = getMerchantOrders(merchantId)
  const result: number[] = []
  const now = new Date()
  const dayMillis: number = 24 * 60 * 60 * 1000
  const cursor: Date = new Date(now.getTime() - 6 * dayMillis)
  for (let i = 6; i >= 0; i--) {
    const dayStr = `${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, '0')}-${String(cursor.getDate()).padStart(2, '0')}`
    const revenue = orders
      .filter(o => o.status === 4 && (o.escrowStatus ?? 0) === 1 && (o.completeTime ?? '').startsWith(dayStr))
      .reduce((sum, o) => sum + o.payAmount, 0)
    result.push(revenue)
    cursor.setTime(cursor.getTime() + dayMillis)
  }
  return result
}

// 今日订单状态分布：[待接单, 制作中, 配送中, 已完成, 已取消]
// 供商户收入统计页柱状图使用
export function getMerchantTodayStatusOrders(merchantId: number): number[] {
  const orders: Order[] = getMerchantOrders(merchantId)
  const today = new Date()
  const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`
  const todayOrders = orders.filter(o => o.createTime.startsWith(todayStr))
  const dist: number[] = [0, 0, 0, 0, 0]
  todayOrders.forEach(o => {
    if (o.status === 1) {
      dist[0]++
    } else if (o.status === 2) {
      dist[1]++
    } else if (o.status === 3) {
      dist[2]++
    } else if (o.status === 4) {
      dist[3]++
    } else if (o.status === 5) {
      dist[4]++
    }
  })
  return dist
}

export async function updateUserProfileRemote(username: string, phone: string): Promise<User | undefined> {
  const user: User | undefined = await updateUserProfileApi(username, phone)
  if (user === undefined) {
    logWarn('Api', '远程更新个人资料失败')
    return undefined
  }
  AppStorage.setOrCreate<User>('user', user)
  await saveAllData()
  logInfo('Api', `远程更新个人资料成功 userId=${user.id}`)
  return user
}

// ==================== 真实后端 API 接入（ApiService） ====================
// 以下方法统一调用后端；页面 onShow/关键操作处调用
// ==================== 认证 ====================

/**
 * 远程登录：成功返回用户并写入 AppStorage；失败返回 undefined
 */
export async function loginRemote(phone: string, password: string, loginType?: string): Promise<User | undefined> {
  const user: User | null = await apiLogin(phone, password, loginType)
  if (user !== null) {
    const token: string = getAuthToken()
    AppStorage.setOrCreate<string>('authToken', token)
    AppStorage.setOrCreate<User>('user', user)
    AppStorage.setOrCreate<boolean>('isLoggedIn', true)
    // 登录成功后立即按当前账号同步地址，恢复默认配送地址；不能继续沿用上一个账号的定位缓存。
    if (user.role === UserRole.CUSTOMER) {
      await syncAddressesRemote()
      await syncCartRemote()
    }
    // 登录态和 Token 必须在登录成功后立即落盘，避免应用重启后回到未登录状态。
    await saveAllData()
    const roleName: string = user.role === UserRole.ADMIN
      ? '管理端'
      : user.role === UserRole.MERCHANT ? '商户' : '用户'
    logInfo('Api', `远程登录成功 userId=${user.id} role=${roleName}`)
    return user
  }
  logWarn('Api', '远程登录失败')
  return undefined
}

/**
 * 远程注册：成功返回用户；失败返回 undefined
 */
export async function registerRemote(username: string, phone: string, password: string, role: UserRole): Promise<User | undefined> {
  const user: User | null = await apiRegister(username, phone, password, role)
  if (user !== null) {
    logInfo('Api', `远程注册成功 userId=${user.id}`)
    return user
  }
  logWarn('Api', '远程注册失败')
  return undefined
}

// ==================== 数据拉取 ====================

/** 从后端拉取首页分类；服务端暂时无数据时保留默认导航，避免首页出现空白区域。 */
export async function syncCategoriesFromServer(): Promise<void> {
  if (categoriesSyncInFlight !== null) {
    await categoriesSyncInFlight
    return
  }
  categoriesSyncInFlight = (async (): Promise<void> => {
    const remoteCategories: Category[] = await fetchCategories()
    const defaults: Category[] = createDefaultCategories()
    if (remoteCategories.length === 0) {
      AppStorage.setOrCreate<Category[]>('categoryList', defaults)
      logWarn('Api', '同步分类数据为空，使用默认分类图标')
      return
    }
    const categories: Category[] = remoteCategories.map((remote: Category) => {
      const fallback: Category | undefined = defaults.find((item: Category) => item.id === remote.id)
      const category: Category = {
        id: remote.id,
        name: remote.name.trim() === '' && fallback !== undefined ? fallback.name : remote.name,
        icon: remote.icon.trim() === '' && fallback !== undefined ? fallback.icon : remote.icon,
        color: remote.color.trim() === '' && fallback !== undefined ? fallback.color : remote.color
      }
      return category
    })
    AppStorage.setOrCreate<Category[]>('categoryList', categories)
    logInfo('Api', `同步分类数据 ${categories.length} 个`)
  })()
  try {
    await categoriesSyncInFlight
  } finally {
    categoriesSyncInFlight = null
  }
}

/**
 * 从后端拉取店铺列表并写入 allStores（首页 onShow 调用）
 */
export async function syncStoresFromServer(): Promise<void> {
  if (storesSyncInFlight !== null) {
    await storesSyncInFlight
    return
  }
  storesSyncInFlight = (async (): Promise<void> => {
    const stores: StoreItem[] = await fetchStores()
    AppStorage.setOrCreate<StoreItem[]>('allStores', stores)
    logInfo('Api', `同步店铺数据 ${stores.length} 家`)
  })()
  try {
    await storesSyncInFlight
  } finally {
    storesSyncInFlight = null
  }
}

/**
 * 从后端拉取指定店铺商品并写入 allGoodsMap
 */
export async function syncGoodsFromServer(storeId: number): Promise<void> {
  const goods: GoodsItem[] = await fetchStoreGoods(storeId)
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  goodsMap[storeId.toString()] = goods
  AppStorage.setOrCreate('allGoodsMap', goodsMap)
  logInfo('Api', `同步店铺商品 storeId=${storeId} ${goods.length} 个`)
}

/**
 * 从后端拉取当前用户订单并写入 orderList
 */
export async function syncUserOrdersFromServer(): Promise<void> {
  const orders: Order[] | null = await fetchUserOrdersApi()
  if (orders === null) {
    logWarn('Api', '同步用户订单失败，保留当前订单列表')
    return
  }

  // 后端返回空数组也必须覆盖本地数据，避免启动时的模拟订单残留在真实订单页面。
  AppStorage.setOrCreate<Order[]>('orderList', orders)
  const user: User | undefined = AppStorage.get<User>('user')
  if (user !== undefined && user !== null) {
    user.orders = orders
    AppStorage.setOrCreate('user', user)
  }
  await saveAllData()
  logInfo('Api', `同步用户订单 ${orders.length} 条`)
}

export async function fetchOrderDetailRemote(orderId: number): Promise<Order | null> {
  const order: Order | null = await fetchOrderDetailApi(orderId)
  if (order === null) {
    return null
  }
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const index: number = orders.findIndex(item => item.id === order.id)
  if (index >= 0) {
    orders[index] = order
  } else {
    orders.unshift(order)
  }
  AppStorage.setOrCreate<Order[]>('orderList', orders)
  logInfo('Api', `远程查询订单详情 orderId=${orderId}`)
  return order
}

/**
 * 从后端拉取商户订单并写入 orderList（商户端 onShow 调用）
 */
export async function syncMerchantOrdersFromServer(): Promise<void> {
  const orders: Order[] = await fetchMerchantOrdersApi()
  AppStorage.setOrCreate<Order[]>('orderList', orders)
  logInfo('Api', `同步商户订单 ${orders.length} 条`)
}

// ==================== 订单操作 ====================

/**
 * 远程下单：成功返回服务端订单；失败返回 null
 */
export async function createOrderRemote(storeId: number, cartItems: CartItem[], addressId: number, couponId: number, remark: string): Promise<Order | null> {
  const order: Order | null = await createOrderApi(storeId, cartItems, addressId, couponId, remark)
  if (order !== null) {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    orders.unshift(order)
    AppStorage.setOrCreate('orderList', orders)
    const user: User | undefined = AppStorage.get<User>('user')
    if (user !== undefined && user !== null) {
      user.orders = orders
      AppStorage.setOrCreate('user', user)
    }
    saveAllData()
    logInfo('Api', `远程下单成功 orderId=${order.id}`)
  }
  return order
}

/**
 * 远程取消订单：成功同步更新本地
 */
export async function cancelOrderRemote(orderId: number): Promise<boolean> {
  const ok: boolean = await cancelOrderApi(orderId)
  if (ok) {
    await syncUserOrdersFromServer()
    logInfo('Api', `远程取消订单 orderId=${orderId}`)
  }
  return ok
}

/**
 * 远程确认收货：同步本地订单状态
 */
export async function confirmOrderRemote(orderId: number): Promise<boolean> {
  const ok: boolean = await confirmOrderApi(orderId)
  if (ok) {
    await syncUserOrdersFromServer()
    logInfo('Api', `远程确认收货 orderId=${orderId}`)
  }
  return ok
}

/**
 * 远程申请退款（演进项：退款审批，见大纲 7.11）：成功后订单进入退款中（status=6）
 */
export async function applyRefundRemote(orderId: number, reason: string): Promise<boolean> {
  const record: RefundRecord | null = await applyRefundApi(orderId, reason)
  if (record !== null) {
    await syncUserOrdersFromServer()
    logInfo('Api', `远程申请退款 orderId=${orderId} refundId=${record.id}`)
    return true
  }
  logWarn('Api', '远程申请退款失败')
  return false
}

/**
 * 远程商户订单流转：action = accept(接单)/deliver(出餐)/complete(完成)
 */
export async function merchantActionRemote(orderId: number, action: string): Promise<boolean> {
  const ok: boolean = await merchantActionApi(orderId, action)
  if (ok) {
    await syncMerchantOrdersFromServer()
    logInfo('Api', `商户操作成功 orderId=${orderId} action=${action}`)
  }
  return ok
}

// ==================== 用户中心同步 ====================

/**
 * 远程收藏切换：返回最新收藏状态（true=已收藏）
 */
export async function toggleFavoriteRemote(storeId: number): Promise<boolean> {
  const favorited: boolean = await toggleFavoriteApi(storeId)
  const errorMessage: string = getLastApiErrorMessage()
  if (errorMessage !== '') {
    logWarn('Api', `远程收藏操作失败 storeId=${storeId} message=${errorMessage}`)
    return false
  }
  await syncFavoritesRemote()
  logInfo('Api', `远程收藏切换 storeId=${storeId} 结果=${favorited}`)
  return favorited
}

/**
 * 从后端拉取收藏列表并写入 favoriteList
 */
export async function syncFavoritesRemote(): Promise<void> {
  const remoteFavorites: Favorite[] = await fetchFavoritesApi()
  // 远端收藏接口返回店铺视图，不携带本地用户 ID；补齐当前登录用户后，
  // getFavorites() 才能通过用户隔离校验并正常渲染收藏列表。
  const user: User | undefined = AppStorage.get<User>('user')
  const favorites: Favorite[] = user === undefined || user === null
    ? []
    : remoteFavorites.map((favorite: Favorite) => {
      favorite.userId = user.id
      return favorite
    })
  AppStorage.setOrCreate<Favorite[]>('favoriteList', favorites)
  logInfo('Api', `同步收藏 ${favorites.length} 条`)
}

/**
 * 从后端拉取优惠券并写入 couponList
 */
export async function syncCouponsRemote(): Promise<void> {
  const coupons: Coupon[] = await fetchCouponsApi()
  AppStorage.setOrCreate<Coupon[]>('couponList', coupons)
  logInfo('Api', `同步优惠券 ${coupons.length} 张`)
}

/**
 * 远程领取优惠券
 */
export async function claimCouponRemote(storeId: number, name: string, threshold: number, amount: number): Promise<boolean> {
  const ok: boolean = await claimCouponApi(storeId, name, threshold, amount)
  if (ok) {
    await syncCouponsRemote()
    logInfo('Api', `远程领券成功 ${name}`)
  }
  return ok
}

/**
 * 从后端拉取商户自己的店铺并合并进 allStores
 */
export async function syncMerchantStoresRemote(): Promise<void> {
  const stores: StoreItem[] = await fetchMerchantStoresApi()
  if (stores.length > 0) {
    const all: StoreItem[] = AppStorage.get<StoreItem[]>('allStores') || []
    for (let i = 0; i < stores.length; i++) {
      const idx: number = all.findIndex(s => s.id === stores[i].id)
      if (idx >= 0) {
        all[idx] = stores[i]
      } else {
        all.push(stores[i])
      }
    }
    AppStorage.setOrCreate<StoreItem[]>('allStores', all)
    logInfo('Api', `同步商户店铺 ${stores.length} 家`)
  }
}

/**
 * 从后端搜索店铺
 */
export async function searchStoresRemote(keyword: string): Promise<StoreItem[]> {
  const result: StoreItem[] = await searchStoresApi(keyword)
  logInfo('Api', `远程搜索 keyword=${keyword} 结果=${result.length} 条`)
  return result
}

/**
 * 远程提交订单评价
 */
export async function submitReviewRemote(orderId: number, goodsId: number, rating: number, content: string, tags: string[]): Promise<boolean> {
  const ok: boolean = await submitReviewApi(orderId, goodsId, rating, content, tags)
  if (ok) {
    logInfo('Api', `远程提交评价 orderId=${orderId} 评分=${rating}`)
  }
  return ok
}

/**
 * 从后端拉取店铺评价
 */
export async function syncStoreReviewsRemote(storeId: number): Promise<void> {
  const reviews: Review[] = await fetchStoreReviews(storeId)
  AppStorage.setOrCreate<Review[]>('reviewList', reviews)
  logInfo('Api', `同步店铺评价 storeId=${storeId} ${reviews.length} 条`)
}

/**
 * 从后端拉取地址并写入 addressList
 */
export async function syncAddressesRemote(): Promise<boolean> {
  if (!isLoggedIn()) {
    logWarn('Api', '同步地址跳过：用户未登录')
    return false
  }
  const remoteAddresses: Address[] = await fetchAddressesApi()
  // fetchAddressesApi 在认证失效时会触发 HttpClient 清理登录态，不能用空数组覆盖本地缓存。
  if (!isLoggedIn()) {
    logWarn('Api', '同步地址失败：登录已失效，保留本地地址')
    return false
  }
  const addresses: Address[] = deduplicateAddresses(remoteAddresses)
    .filter((address: Address) => address.name !== '当前位置')
  AppStorage.setOrCreate<Address[]>('addressList', addresses)
  const currentAddress: Address | null = AppStorage.get<Address>('currentAddress') ?? null
  const selectedAddress: Address | undefined = currentAddress !== null && currentAddress.id > 0
    ? addresses.find((address: Address) => address.id === currentAddress.id)
    : undefined
  const nextAddress: Address | undefined = selectedAddress ?? addresses.find((address: Address) => address.isDefault) ?? addresses[0]
  AppStorage.setOrCreate<Address | null>('currentAddress', nextAddress === undefined ? null : nextAddress)
  await saveAllData()
  logInfo('Api', `同步地址 ${remoteAddresses.length} 条，去重后 ${addresses.length} 条`)
  return true
}

/**
 * 远程新增地址
 */
export async function addAddressRemote(name: string, phone: string, detail: string, isDefault: boolean): Promise<boolean> {
  const ok: boolean = await addAddressApi(name, phone, detail, isDefault)
  if (ok) {
    await syncAddressesRemote()
    logInfo('Api', '远程新增地址成功')
  }
  return ok
}

export async function addAddressRemoteAndGet(name: string, phone: string, detail: string, isDefault: boolean): Promise<Address | null> {
  const address: Address | null = await addAddressAndFetchApi(name, phone, detail, isDefault)
  if (address !== null) {
    await syncAddressesRemote()
    logInfo('Api', `远程新增地址成功 addressId=${address.id}`)
  }
  return address
}

/**
 * 远程删除地址
 */
export async function deleteAddressRemote(addressId: number): Promise<boolean> {
  const ok: boolean = await deleteAddressApi(addressId)
  if (ok) {
    await syncAddressesRemote()
    logInfo('Api', `远程删除地址 addressId=${addressId}`)
  }
  return ok
}

export async function updateAddressRemote(addressId: number, name: string, phone: string, detail: string, isDefault: boolean): Promise<boolean> {
  const ok: boolean = await updateAddressApi(addressId, name, phone, detail, isDefault)
  if (ok) {
    await syncAddressesRemote()
    logInfo('Api', `远程更新地址 addressId=${addressId}`)
  }
  return ok
}

/**
 * 远程设置默认地址
 */
export async function setDefaultAddressRemote(addressId: number): Promise<boolean> {
  const ok: boolean = await setDefaultAddressApi(addressId)
  if (ok) {
    await syncAddressesRemote()
    logInfo('Api', `远程设置默认地址 addressId=${addressId}`)
  }
  return ok
}
