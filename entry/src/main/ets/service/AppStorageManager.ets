/**
 * 全局状态管理 - 使用AppStorage管理应用级状态
 */
import { CartItem, Order, Address, Coupon, User, UserRole, StoreItem, GoodsItem, Favorite, Review, MerchantStatsData } from '../model/Models'
import { getDefaultUser, getDefaultAddresses, getDefaultCoupons, getDefaultOrders, getMockUsers, getStores, getGoodsByStore, getDefaultReviews, getDefaultFavorites, getReviewsByStore, getClaimableCoupons } from './MockDataService'
import { saveAllData, clearAllData } from './DataPersistence'
import { logInfo, logWarn, logError } from './AppLogger'

// 初始化全局数据
export function initAppStorage() {
  // 如果持久化数据已加载，跳过默认值初始化
  if (AppStorage.get<boolean>('_persistenceReady')) {
    return
  }
  if (!AppStorage.has('isLoggedIn')) {
    AppStorage.setOrCreate<boolean>('isLoggedIn', false)
  }
  if (!AppStorage.has('user')) {
    AppStorage.setOrCreate<User>('user', getDefaultUser())
  }
  if (!AppStorage.has('allUsers')) {
    AppStorage.setOrCreate<User[]>('allUsers', getMockUsers())
  }
  if (!AppStorage.has('cartItems')) {
    AppStorage.setOrCreate<CartItem[]>('cartItems', [])
  }
  if (!AppStorage.has('addressList')) {
    AppStorage.setOrCreate('addressList', getDefaultAddresses())
  }
  // 不默认设置 currentAddress：用户未定位/未选择地址时保持空，主页显示“未定位”提示去定位
  if (!AppStorage.has('currentAddress')) {
    AppStorage.setOrCreate<Address | null>('currentAddress', null)
  }
  if (!AppStorage.has('orderList')) {
    AppStorage.setOrCreate('orderList', getDefaultOrders())
  }
  if (!AppStorage.has('couponList')) {
    AppStorage.setOrCreate('couponList', getDefaultCoupons())
  }
  if (!AppStorage.has('selectedCoupon')) {
    AppStorage.setOrCreate<Coupon | null>('selectedCoupon', null)
  }
  // 动态店铺和商品数据（商户可修改）
  if (!AppStorage.has('allStores')) {
    AppStorage.setOrCreate('allStores', getStores())
  }
  if (!AppStorage.has('allGoodsMap')) {
    let goodsMap: Record<string, GoodsItem[]> = {}
    const stores = getStores()
    for (let i = 0; i < stores.length; i++) {
      goodsMap[stores[i].id.toString()] = getGoodsByStore(stores[i].id)
    }
    AppStorage.setOrCreate('allGoodsMap', goodsMap)
  }
  if (!AppStorage.has('favoriteList')) {
    AppStorage.setOrCreate('favoriteList', getDefaultFavorites())
  }
  if (!AppStorage.has('reviewList')) {
    AppStorage.setOrCreate('reviewList', getDefaultReviews())
  }
  if (!AppStorage.has('claimableCoupons')) {
    AppStorage.setOrCreate('claimableCoupons', getClaimableCoupons())
  }
  logInfo('AppStorage', 'initAppStorage 完成，全局数据初始化就绪')
}

// ============ 登录/登出 ============
export function login(phone: string, password: string): User | undefined {
  const users: User[] = AppStorage.get<User[]>('allUsers') || []
  const user = users.find(u => u.phone === phone && u.password === password)
  if (user) {
    AppStorage.setOrCreate<User>('user', user)
    AppStorage.setOrCreate<boolean>('isLoggedIn', true)
    saveAllData()
    logInfo('Auth', `用户登录成功 phone=${phone} userId=${user.id} role=${user.role === UserRole.MERCHANT ? '商户' : '用户'}`)
    return user
  }
  logWarn('Auth', `用户登录失败 phone=${phone}（账号或密码错误）`)
  return undefined
}

export function register(username: string, phone: string, password: string, role: UserRole): User | undefined {
  const users: User[] = AppStorage.get<User[]>('allUsers') || []
  if (users.find(u => u.phone === phone)) {
    return undefined // 手机号已注册
  }
  const newUser: User = {
    id: Date.now(),
    username: username,
    avatar: '',
    phone: phone,
    password: password,
    role: role,
    balance: role === UserRole.CUSTOMER ? 20.0 : 0, // 新注册用户赠送余额，商户从 0 开始靠经营赚钱
    coupons: [],
    orders: [],
    storeIds: [],
  }
  users.push(newUser)
  AppStorage.setOrCreate('allUsers', users)
  saveAllData()
  logInfo('Auth', `用户注册成功 phone=${phone} username=${username} role=${role === UserRole.MERCHANT ? '商户' : '用户'}`)
  return newUser
}

export function logout(): void {
  AppStorage.setOrCreate<boolean>('isLoggedIn', false)
  AppStorage.setOrCreate<User>('user', getDefaultUser())
  AppStorage.setOrCreate<CartItem[]>('cartItems', [])
  clearAllData()
  logInfo('Auth', '用户退出登录，已清除登录态与购物车')
}

export function isLoggedIn(): boolean {
  return AppStorage.get<boolean>('isLoggedIn') || false
}

// ============ 获取当前用户 ============
export function getCurrentUser(): User | undefined {
  return AppStorage.get<User>('user')
}

/**
 * 同步当前用户与 allUsers 账号数据（登录态恢复后调用）：
 * 以 allUsers 中的账号信息为基准（保证不同账号余额等初始数据正确），
 * 保留运行时的订单/优惠券，余额取两者较大值（不丢失商户经营收入）
 */
export function syncUserWithAllUsers(): void {
  const user: User | undefined = AppStorage.get<User>('user')
  const loggedIn: boolean = AppStorage.get<boolean>('isLoggedIn') || false
  if (!loggedIn || user === undefined || user === null || user.phone === '') {
    return
  }
  const allUsers: User[] = AppStorage.get<User[]>('allUsers') || []
  const index: number = allUsers.findIndex(u => u.phone === user.phone)
  if (index >= 0) {
    const fresh: User = allUsers[index]
    fresh.orders = user.orders || []
    fresh.coupons = user.coupons || []
    if (user.balance > fresh.balance) {
      fresh.balance = user.balance
    }
    allUsers[index] = fresh
    AppStorage.setOrCreate('allUsers', allUsers)
    AppStorage.setOrCreate<User>('user', fresh)
    logInfo('Auth', `同步用户数据 userId=${fresh.id} username=${fresh.username} balance=${fresh.balance}`)
  }
}

// ============ 购物车操作 ============
export function addToCart(item: CartItem): void {
  const cart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
  const existIndex = cart.findIndex(c => c.goods.id === item.goods.id && c.storeId === item.storeId)
  if (existIndex >= 0) {
    cart[existIndex].quantity += item.quantity
  } else {
    cart.push(item)
  }
  AppStorage.setOrCreate('cartItems', cart)
  saveAllData()
  logInfo('Cart', `加入购物车 goods=${item.goods.name} x${item.quantity} storeId=${item.storeId}`)
}

export function updateCartItemQuantity(goodsId: number, storeId: number, quantity: number): void {
  let cart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
  if (quantity <= 0) {
    cart = cart.filter(c => !(c.goods.id === goodsId && c.storeId === storeId))
  } else {
    const item = cart.find(c => c.goods.id === goodsId && c.storeId === storeId)
    if (item) {
      item.quantity = quantity
    }
  }
  AppStorage.setOrCreate('cartItems', cart)
  saveAllData()
  logInfo('Cart', `更新购物车数量 goodsId=${goodsId} storeId=${storeId} quantity=${quantity}`)
}

export function clearCart(): void {
  AppStorage.setOrCreate<CartItem[]>('cartItems', [])
  saveAllData()
  logInfo('Cart', '清空购物车')
}

// ============ 订单操作 ============
export function addOrder(order: Order): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  orders.unshift(order)
  AppStorage.setOrCreate('orderList', orders)
  const user: User | undefined = AppStorage.get<User>('user')
  if (user !== undefined && user !== null) {
    user.orders = orders
    AppStorage.setOrCreate('user', user)
  }
  saveAllData()
  logInfo('Order', `生成新订单 orderId=${order.id} store=${order.storeName} payAmount=${order.payAmount}`)
}

export function cancelOrder(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order) {
    order.status = 5
    order.cancelTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)
    logInfo('Order', `取消订单 orderId=${orderId}`)
  } else {
    logWarn('Order', `取消订单失败：订单不存在 orderId=${orderId}`)
  }
  saveAllData()
}

export function confirmOrder(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order) {
    order.status = 4
    order.completeTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)
    logInfo('Order', `确认收货 orderId=${orderId}`)
  } else {
    logWarn('Order', `确认收货失败：订单不存在 orderId=${orderId}`)
  }
  saveAllData()
}

// ============ 商户：店铺管理 ============
export function createStore(store: StoreItem): void {
  const stores: StoreItem[] = AppStorage.get<StoreItem[]>('allStores') || []
  store.id = Date.now()
  stores.push(store)
  AppStorage.setOrCreate('allStores', stores)
  // 初始化该店铺的商品列表为空
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  goodsMap[store.id.toString()] = []
  AppStorage.setOrCreate('allGoodsMap', goodsMap)
  // 更新商户的 storeIds
  const user: User | undefined = AppStorage.get<User>('user')
  if (user !== undefined && user.role === UserRole.MERCHANT) {
    user.storeIds.push(store.id)
    AppStorage.setOrCreate('user', user)
  }
  saveAllData()
  logInfo('Merchant', `创建店铺 storeId=${store.id} name=${store.name}`)
}

export function updateStore(store: StoreItem): void {
  const stores: StoreItem[] = AppStorage.get<StoreItem[]>('allStores') || []
  const index = stores.findIndex(s => s.id === store.id)
  if (index >= 0) {
    stores[index] = store
    AppStorage.setOrCreate('allStores', stores)
    logInfo('Merchant', `更新店铺信息 storeId=${store.id} name=${store.name} 配送费=${store.deliveryFee} 起送价=${store.minOrder}`)
  } else {
    logWarn('Merchant', `更新店铺失败：店铺不存在 storeId=${store.id}`)
  }
  saveAllData()
}

// ============ 商户：商品管理 ============
export function addGoodsToStore(storeId: number, goods: GoodsItem): void {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  const storeGoods: GoodsItem[] = goodsMap[storeId.toString()] || []
  goods.id = Date.now()
  storeGoods.push(goods)
  goodsMap[storeId.toString()] = storeGoods
  AppStorage.setOrCreate('allGoodsMap', goodsMap)
  saveAllData()
  logInfo('Merchant', `新增商品 storeId=${storeId} goodsId=${goods.id} name=${goods.name} price=${goods.price}`)
}

export function removeGoodsFromStore(storeId: number, goodsId: number): void {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  let storeGoods: GoodsItem[] = goodsMap[storeId.toString()] || []
  storeGoods = storeGoods.filter(g => g.id !== goodsId)
  goodsMap[storeId.toString()] = storeGoods
  AppStorage.setOrCreate('allGoodsMap', goodsMap)
  saveAllData()
  logInfo('Merchant', `删除商品 storeId=${storeId} goodsId=${goodsId}`)
}

export function updateGoodsToStore(storeId: number, goods: GoodsItem): void {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  const storeGoods: GoodsItem[] = goodsMap[storeId.toString()] || []
  const index = storeGoods.findIndex(g => g.id === goods.id)
  if (index >= 0) {
    storeGoods[index] = goods
    goodsMap[storeId.toString()] = storeGoods
    AppStorage.setOrCreate('allGoodsMap', goodsMap)
    logInfo('Merchant', `更新商品 storeId=${storeId} goodsId=${goods.id} name=${goods.name} price=${goods.price} 上架=${goods.isOnShelf !== false}`)
  }
  saveAllData()
}

export function getGoodsForStore(storeId: number): GoodsItem[] {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  return goodsMap[storeId.toString()] || []
}

export function getAllStoresList(): StoreItem[] {
  return AppStorage.get<StoreItem[]>('allStores') || getStores()
}

export function getStoresByOwner(ownerId: number): StoreItem[] {
  const stores: StoreItem[] = AppStorage.get<StoreItem[]>('allStores') || getStores()
  return stores.filter(s => s.ownerId === ownerId)
}

// ============ 地址操作 ============
export function addAddress(address: Address): void {
  const list: Address[] = AppStorage.get<Address[]>('addressList') || []
  if (address.isDefault) {
    list.forEach(a => a.isDefault = false)
  }
  address.id = list.length + 1
  list.push(address)
  AppStorage.setOrCreate('addressList', list)
  saveAllData()
  logInfo('Address', `新增地址 id=${address.id} name=${address.name} phone=${address.phone} 默认=${address.isDefault}`)
}

export function deleteAddress(addressId: number): void {
  let list: Address[] = AppStorage.get<Address[]>('addressList') || []
  list = list.filter(a => a.id !== addressId)
  AppStorage.setOrCreate('addressList', list)
  saveAllData()
  logInfo('Address', `删除地址 id=${addressId}`)
}

// ============ 优惠券操作 ============
export function useCoupon(couponId: number): void {
  const coupons: Coupon[] = AppStorage.get<Coupon[]>('couponList') || []
  const coupon = coupons.find(c => c.id === couponId)
  if (coupon) {
    coupon.used = true
    AppStorage.setOrCreate('couponList', coupons)
    logInfo('Coupon', `使用优惠券 couponId=${couponId} 金额=${coupon.amount}`)
  } else {
    logWarn('Coupon', `使用优惠券失败：优惠券不存在 couponId=${couponId}`)
  }
  saveAllData()
}

// ============ 工具方法 ============
function formatDateTime(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  const h = String(date.getHours()).padStart(2, '0')
  const min = String(date.getMinutes()).padStart(2, '0')
  const s = String(date.getSeconds()).padStart(2, '0')
  return `${y}-${m}-${d} ${h}:${min}:${s}`
}

export function generateOrderId(): number {
  return Date.now() + Math.floor(Math.random() * 1000)
}

export function formatPrice(price: number): string {
  return '¥' + price.toFixed(2)
}

// ============ 收藏操作 ============
export function toggleFavorite(storeId: number): boolean {
  const user: User | undefined = AppStorage.get<User>('user')
  if (user === undefined || user === null) return false

  let favorites: Favorite[] = AppStorage.get<Favorite[]>('favoriteList') || getDefaultFavorites()
  const existIndex = favorites.findIndex(f => f.storeId === storeId && f.userId === user.id)

  let result: boolean = false
  if (existIndex >= 0) {
    // 取消收藏
    favorites = favorites.filter(f => !(f.storeId === storeId && f.userId === user.id))
    AppStorage.setOrCreate('favoriteList', favorites)
    result = false
  } else {
    // 添加收藏
    const stores: StoreItem[] = getAllStoresList()
    const store = stores.find(s => s.id === storeId)
    if (store) {
      const favorite: Favorite = {
        id: Date.now(),
        userId: user.id,
        storeId: storeId,
        storeName: store.name,
        storeImage: store.image,
        createTime: formatDateTime(new Date())
      }
      favorites.push(favorite)
      AppStorage.setOrCreate('favoriteList', favorites)
      result = true
    }
  }
  saveAllData()
  logInfo('Favorite', `切换收藏 storeId=${storeId} ${result ? '已收藏' : '已取消'}`)
  return result
}

export function getFavorites(): Favorite[] {
  const user: User | undefined = AppStorage.get<User>('user')
  if (user === undefined || user === null) return []
  const favorites: Favorite[] = AppStorage.get<Favorite[]>('favoriteList') || getDefaultFavorites()
  return favorites.filter(f => f.userId === user.id)
}

export function isFavorited(storeId: number): boolean {
  const user: User | undefined = AppStorage.get<User>('user')
  if (user === undefined || user === null) return false
  const favorites: Favorite[] = AppStorage.get<Favorite[]>('favoriteList') || getDefaultFavorites()
  return favorites.some(f => f.storeId === storeId && f.userId === user.id)
}

// ============ 评价操作 ============
export function addReview(review: Review): void {
  let reviews: Review[] = AppStorage.get<Review[]>('reviewList') || getDefaultReviews()
  review.id = Date.now()
  reviews.unshift(review)
  AppStorage.setOrCreate('reviewList', reviews)

  // 标记订单已评价
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === review.orderId)
  if (order) {
    // 在remark字段标记已评价
    order.remark = order.remark + ' [已评价]'
    AppStorage.setOrCreate('orderList', orders)
  }
  saveAllData()
  logInfo('Review', `提交评价 orderId=${review.orderId} storeId=${review.storeId} 评分=${review.rating} 内容=${review.content}`)
}

export function getStoreReviews(storeId: number): Review[] {
  const reviews: Review[] = AppStorage.get<Review[]>('reviewList') || getDefaultReviews()
  return reviews.filter(r => r.storeId === storeId)
}

// ============ 商户订单状态流转 ============
export function merchantAcceptOrder(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order && order.status === 1) {
    order.status = 2  // 待接单 -> 制作中
    order.payTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)
    logInfo('Merchant', `商户接单 orderId=${orderId}（待接单 -> 制作中）`)
  } else {
    logWarn('Merchant', `商户接单失败：订单不存在或状态不符 orderId=${orderId}`)
  }
  saveAllData()
}

export function merchantStartDelivery(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order && order.status === 2) {
    order.status = 3  // 制作中 -> 配送中
    order.deliverTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)
    logInfo('Merchant', `商户出餐配送 orderId=${orderId}（制作中 -> 配送中）`)
  } else {
    logWarn('Merchant', `商户出餐失败：订单不存在或状态不符 orderId=${orderId}`)
  }
  saveAllData()
}

export function merchantCompleteOrder(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order && order.status === 3) {
    order.status = 4  // 配送中 -> 已完成
    order.completeTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)

    // 商户余额增加
    const user: User | undefined = AppStorage.get<User>('user')
    if (user !== undefined && user !== null && user.role === UserRole.MERCHANT) {
      user.balance += order.payAmount
      AppStorage.setOrCreate('user', user)
    }
    logInfo('Merchant', `商户确认送达 orderId=${orderId}（配送中 -> 已完成）收入=${order.payAmount}`)
  } else {
    logWarn('Merchant', `商户确认送达失败：订单不存在或状态不符 orderId=${orderId}`)
  }
  saveAllData()
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
  const completedOrders = todayOrders.filter(o => o.status === 4)
  const revenue = completedOrders.reduce((sum, o) => sum + o.payAmount, 0)

  const stats: MerchantStatsData = {
    todayOrders: todayOrders.length,
    todayRevenue: revenue,
    completedOrders: completedOrders.length,
    totalOrders: orders.length,
    totalRevenue: orders.filter(o => o.status === 4).reduce((sum, o) => sum + o.payAmount, 0)
  }
  return stats
}

export function getMerchantWeekStats(merchantId: number): MerchantStatsData {
  const orders: Order[] = getMerchantOrders(merchantId)
  const now = new Date()
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)

  const weekOrders = orders.filter(o => {
    const orderDate = new Date(o.createTime.replace(/-/g, '/'))
    return orderDate >= weekAgo
  })
  const completedOrders = weekOrders.filter(o => o.status === 4)
  const revenue = completedOrders.reduce((sum, o) => sum + o.payAmount, 0)

  const stats: MerchantStatsData = {
    todayOrders: weekOrders.length,
    todayRevenue: revenue,
    completedOrders: completedOrders.length,
    totalOrders: orders.length,
    totalRevenue: orders.filter(o => o.status === 4).reduce((sum, o) => sum + o.payAmount, 0)
  }
  return stats
}

// 近7天（含今日）每日已完成订单收入，索引0为7天前，索引6为今日
// 供商户收入统计页折线图使用
export function getMerchantWeekRevenue(merchantId: number): number[] {
  const orders: Order[] = getMerchantOrders(merchantId)
  const result: number[] = []
  const now = new Date()
  for (let i = 6; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 24 * 60 * 60 * 1000)
    const dayStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    const revenue = orders
      .filter(o => o.status === 4 && (o.completeTime ?? '').startsWith(dayStr))
      .reduce((sum, o) => sum + o.payAmount, 0)
    result.push(revenue)
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

// ============ 用户信息更新 ============
export function updateUserProfile(username: string, phone: string): void {
  const user: User | undefined = AppStorage.get<User>('user')
  if (user !== undefined && user !== null) {
    user.username = username
    user.phone = phone
    AppStorage.setOrCreate('user', user)

    // 更新allUsers中的对应用户
    const allUsers: User[] = AppStorage.get<User[]>('allUsers') || []
    const index = allUsers.findIndex(u => u.id === user.id)
    if (index >= 0) {
      allUsers[index] = user
      AppStorage.setOrCreate('allUsers', allUsers)
    }
    logInfo('Profile', `更新用户信息 userId=${user.id} username=${username} phone=${phone}`)
  }
  saveAllData()
}