/**
 * 全局状态管理 - 使用AppStorage管理应用级状态
 */
import { CartItem, Order, Address, Coupon, User, UserRole, StoreItem, GoodsItem, Favorite, Review, MerchantStatsData } from '../model/Models'
import { getDefaultUser, getDefaultAddresses, getDefaultCoupons, getDefaultOrders, getMockUsers, getStores, getGoodsByStore, getDefaultReviews, getDefaultFavorites, getReviewsByStore, getClaimableCoupons } from './MockDataService'

// 初始化全局数据
export function initAppStorage() {
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
  if (!AppStorage.has('currentAddress')) {
    const addresses: Address[] = getDefaultAddresses()
    const defaultAddr = addresses.find(a => a.isDefault) || addresses[0]
    AppStorage.setOrCreate('currentAddress', defaultAddr)
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
}

// ============ 登录/登出 ============
export function login(phone: string, password: string): User | undefined {
  const users: User[] = AppStorage.get<User[]>('allUsers') || []
  const user = users.find(u => u.phone === phone && u.password === password)
  if (user) {
    AppStorage.setOrCreate<User>('user', user)
    AppStorage.setOrCreate<boolean>('isLoggedIn', true)
    return user
  }
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
    balance: 0,
    coupons: [],
    orders: [],
    storeIds: [],
  }
  users.push(newUser)
  AppStorage.setOrCreate('allUsers', users)
  return newUser
}

export function logout(): void {
  AppStorage.setOrCreate<boolean>('isLoggedIn', false)
  AppStorage.setOrCreate<User>('user', getDefaultUser())
  AppStorage.setOrCreate<CartItem[]>('cartItems', [])
}

export function isLoggedIn(): boolean {
  return AppStorage.get<boolean>('isLoggedIn') || false
}

// ============ 获取当前用户 ============
export function getCurrentUser(): User | undefined {
  return AppStorage.get<User>('user')
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
}

export function clearCart(): void {
  AppStorage.setOrCreate<CartItem[]>('cartItems', [])
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
}

export function cancelOrder(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order) {
    order.status = 5
    order.cancelTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)
  }
}

export function confirmOrder(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order) {
    order.status = 4
    order.completeTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)
  }
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
}

export function updateStore(store: StoreItem): void {
  const stores: StoreItem[] = AppStorage.get<StoreItem[]>('allStores') || []
  const index = stores.findIndex(s => s.id === store.id)
  if (index >= 0) {
    stores[index] = store
    AppStorage.setOrCreate('allStores', stores)
  }
}

// ============ 商户：商品管理 ============
export function addGoodsToStore(storeId: number, goods: GoodsItem): void {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  const storeGoods: GoodsItem[] = goodsMap[storeId.toString()] || []
  goods.id = Date.now()
  storeGoods.push(goods)
  goodsMap[storeId.toString()] = storeGoods
  AppStorage.setOrCreate('allGoodsMap', goodsMap)
}

export function removeGoodsFromStore(storeId: number, goodsId: number): void {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  let storeGoods: GoodsItem[] = goodsMap[storeId.toString()] || []
  storeGoods = storeGoods.filter(g => g.id !== goodsId)
  goodsMap[storeId.toString()] = storeGoods
  AppStorage.setOrCreate('allGoodsMap', goodsMap)
}

export function updateGoodsToStore(storeId: number, goods: GoodsItem): void {
  const goodsMap: Record<string, GoodsItem[]> = AppStorage.get<Record<string, GoodsItem[]>>('allGoodsMap') || {}
  const storeGoods: GoodsItem[] = goodsMap[storeId.toString()] || []
  const index = storeGoods.findIndex(g => g.id === goods.id)
  if (index >= 0) {
    storeGoods[index] = goods
    goodsMap[storeId.toString()] = storeGoods
    AppStorage.setOrCreate('allGoodsMap', goodsMap)
  }
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
}

export function deleteAddress(addressId: number): void {
  let list: Address[] = AppStorage.get<Address[]>('addressList') || []
  list = list.filter(a => a.id !== addressId)
  AppStorage.setOrCreate('addressList', list)
}

// ============ 优惠券操作 ============
export function useCoupon(couponId: number): void {
  const coupons: Coupon[] = AppStorage.get<Coupon[]>('couponList') || []
  const coupon = coupons.find(c => c.id === couponId)
  if (coupon) {
    coupon.used = true
    AppStorage.setOrCreate('couponList', coupons)
  }
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

  if (existIndex >= 0) {
    // 取消收藏
    favorites = favorites.filter(f => !(f.storeId === storeId && f.userId === user.id))
    AppStorage.setOrCreate('favoriteList', favorites)
    return false
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
      return true
    }
    return false
  }
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
  }
}

export function merchantStartDelivery(orderId: number): void {
  const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
  const order = orders.find(o => o.id === orderId)
  if (order && order.status === 2) {
    order.status = 3  // 制作中 -> 配送中
    order.deliverTime = formatDateTime(new Date())
    AppStorage.setOrCreate('orderList', orders)
  }
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
  }
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
  }
}