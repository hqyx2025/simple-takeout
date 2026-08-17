/**
 * 后端 API 适配层
 * 负责：调用后端 REST API（HttpClient）+ 后端 JSON 与客户端 Models 之间的双向转换
 * 所有页面/服务层通过本模块访问真实后端数据
 */
import { get, post, put, del, ApiResponse, setAuthToken } from './HttpClient'
import { API_CONFIG } from '../common/Constants'
import {
  User, UserRole, StoreItem, GoodsItem, Category, Order, CartItem,
  Address, Coupon, Review, Favorite, RefundRecord, AdminEmployee, AdminProduct, AdminUser,
  AdminStatisticsData, AdminTrendPoint, AdminHotGoods
} from '../model/Models'
import { logInfo, logWarn } from './AppLogger'

// ==================== 后端响应结构（与 server 端 record 对齐） ====================

interface ServerStore {
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
  categoryIds: number[]
  ownerId: number
  status: number
  recommended: number
}

interface ServerGoods {
  id: number
  storeId: number
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
}

interface ServerOrderItem {
  goodsId: number
  goodsName: string
  price: number
  quantity: number
  image: string
}

interface ServerAddressInfo {
  addressId: number
  name: string
  phone: string
  detail: string
}

interface ServerOrder {
  id: number
  orderNo: string
  userId: number
  storeId: number
  storeName: string
  status: number
  items: ServerOrderItem[]
  address: ServerAddressInfo
  goodsAmount: number
  deliveryFee: number
  discount: number
  payAmount: number
  remark: string
  reviewed: number
  escrowStatus: number
  createTime: string
  payTime: string
  acceptTime: string
  deliverTime: string
  completeTime: string
}

interface ServerUser {
  id: number
  username: string
  avatar: string
  phone: string
  password: string
  role: number
  balance: number
  createTime: string
}

interface ServerCoupon {
  id: number
  userId: number
  storeId: number
  name: string
  threshold: number
  amount: number
  status: number
  expireTime: string
  source: string
  createTime: string
}

interface ServerAddress {
  id: number
  userId: number
  name: string
  phone: string
  detail: string
  isDefault: number
}

interface ServerReview {
  id: number
  storeId: number
  goodsId: number
  userId: number
  userName: string
  rating: number
  content: string
  tags: string[]
  createTime: string
}

interface ServerAdminEmployee {
  id: number
  username: string
  phone: string
  role: number
  status: number
  storeCount: number
  createTime: string
}

interface ServerAdminProduct {
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

interface ServerAdminUser {
  id: number
  username: string
  phone: string
  role: number
  status: number
  balance: number
  storeCount: number
  createTime: string
}

interface ServerAdminHotGoods {
  goodsId: number
  goodsName: string
  storeId: number
  storeName: string
  sales: number
  price: number
  status: number
}

interface ServerAdminStatistics {
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
  hotGoods: ServerAdminHotGoods[]
}

interface ServerAdminTrendPoint {
  date: string
  orderCount: number
  gmv: number
}

interface LoginResult {
  token: string
  user: ServerUser
}

// ==================== 请求 DTO ====================

interface LoginRequest {
  phone: string
  password: string
  loginType?: string
}

interface RegisterRequest {
  username: string
  phone: string
  password: string
  role: number
}

interface ProfileUpdateRequest {
  username: string
  phone: string
}

interface OrderItemRequest {
  goodsId: number
  goodsName: string
  price: number
  quantity: number
  image: string
}

interface CreateOrderRequest {
  storeId: number
  items: OrderItemRequest[]
  addressId: number
  couponId: number
  remark: string
}

interface ReviewRequest {
  goodsId: number
  rating: number
  content: string
  tags: string[]
}

interface AddressRequest {
  name: string
  phone: string
  detail: string
  isDefault: number
}

interface CouponClaimRequest {
  storeId: number
  name: string
  threshold: number
  amount: number
}

interface MerchantStoreRequest {
  name: string
  categoryId: number
  deliveryFee: number
  minOrder: number
  deliveryTime: string
  notice: string
}

interface MerchantStorePatch {
  name: string
  deliveryFee: number
  minOrder: number
  deliveryTime: string
  notice: string
  status: number
}

interface MerchantGoodsRequest {
  name: string
  description: string
  price: number
  originalPrice: number
  image: string
  categoryId: number
  merchantCategoryId: number
  stock: number
  tag: string
  status: number
}

interface RefundRequest {
  reason: string
}

interface AdminEmployeeCreateRequest {
  username: string
  phone: string
  password: string
}

interface AdminEmployeeProfileRequest {
  username: string
  phone: string
}

interface AdminEmployeeStatusRequest {
  status: number
}

interface AdminStatusRequest {
  status: number
}

interface MerchantCategoryRequest {
  name: string
  sort: number
}

interface StockRequest {
  stock: number
}

interface RefundRejectRequest {
  rejectReason: string
}

// ==================== 认证 ====================

/**
 * 登录：成功设置 token 并返回用户，失败返回 null
 */
export async function apiLogin(phone: string, password: string, loginType?: string): Promise<User | null> {
  const req: LoginRequest = loginType === undefined
    ? { phone: phone, password: password }
    : { phone: phone, password: password, loginType: loginType }
  const resp: ApiResponse<LoginResult> = await post<LoginResult>(API_CONFIG.ENDPOINTS['login'], req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `登录失败：${resp.message}`)
    return null
  }
  setAuthToken(resp.data.token)
  logInfo('Api', `登录成功 userId=${resp.data.user.id}`)
  return toUser(resp.data.user)
}

/**
 * 注册：成功返回用户，失败返回 null
 */
export async function apiRegister(username: string, phone: string, password: string, role: UserRole): Promise<User | null> {
  const req: RegisterRequest = { username: username, phone: phone, password: password, role: role === UserRole.MERCHANT ? 1 : 0 }
  const resp: ApiResponse<ServerUser> = await post<ServerUser>(API_CONFIG.ENDPOINTS['register'], req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `注册失败：${resp.message}`)
    return null
  }
  logInfo('Api', `注册成功 userId=${resp.data.id}`)
  return toUser(resp.data)
}

export async function updateUserProfileApi(username: string, phone: string): Promise<User | undefined> {
  const req: ProfileUpdateRequest = { username: username, phone: phone }
  const resp: ApiResponse<ServerUser> = await put<ServerUser>('/api/auth/me', req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `更新个人资料失败：${resp.message}`)
    return undefined
  }
  return toUser(resp.data)
}

// ==================== 数据拉取（游客可访问） ====================

export async function fetchCategories(): Promise<Category[]> {
  const resp: ApiResponse<Category[]> = await get<Category[]>(API_CONFIG.ENDPOINTS['categories'])
  return resp.code === 200 ? (resp.data || []) : []
}

export async function fetchStores(categoryId?: number): Promise<StoreItem[]> {
  const url: string = categoryId !== undefined && categoryId > 0
    ? `${API_CONFIG.ENDPOINTS['stores']}?categoryId=${categoryId}`
    : API_CONFIG.ENDPOINTS['stores']
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(url)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => toStoreItem(s))
}

export async function fetchRecommendedStoresApi(maxDistanceKm: number = 2, limit: number = 10): Promise<StoreItem[]> {
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(
    `/api/stores/recommended?maxDistanceKm=${maxDistanceKm}&limit=${limit}`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => toStoreItem(s))
}

export async function fetchStoreGoods(storeId: number): Promise<GoodsItem[]> {
  const resp: ApiResponse<ServerGoods[]> = await get<ServerGoods[]>(`/api/stores/${storeId}/goods`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((g: ServerGoods) => toGoodsItem(g))
}

export async function fetchStoreReviews(storeId: number): Promise<Review[]> {
  const resp: ApiResponse<ServerReview[]> = await get<ServerReview[]>(`/api/stores/${storeId}/reviews`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerReview) => toReview(r))
}

export async function fetchGoodsReviews(goodsId: number): Promise<Review[]> {
  const resp: ApiResponse<ServerReview[]> = await get<ServerReview[]>(`/api/goods/${goodsId}/reviews`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerReview) => toReview(r))
}

export async function searchStoresApi(keyword: string): Promise<StoreItem[]> {
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(`${API_CONFIG.ENDPOINTS['search']}?keyword=${encodeURIComponent(keyword)}`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => toStoreItem(s))
}

// ==================== 订单（需登录） ====================

/**
 * 创建订单：items 为购物车项，返回服务端订单（已转换）
 */
export async function createOrderApi(storeId: number, cartItems: CartItem[], addressId: number, couponId: number, remark: string): Promise<Order | null> {
  const items: OrderItemRequest[] = cartItems.map((c: CartItem) => {
    const item: OrderItemRequest = {
      goodsId: c.goods.id,
      goodsName: c.goods.name,
      price: c.goods.price,
      quantity: c.quantity,
      image: c.goods.image
    }
    return item
  })
  const req: CreateOrderRequest = {
    storeId: storeId,
    items: items,
    addressId: addressId,
    couponId: couponId,
    remark: remark
  }
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(API_CONFIG.ENDPOINTS['orders'], req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `下单失败：${resp.message}`)
    return null
  }
  return toOrder(resp.data)
}

export async function fetchUserOrdersApi(): Promise<Order[] | null> {
  const resp: ApiResponse<ServerOrder[]> = await get<ServerOrder[]>(API_CONFIG.ENDPOINTS['orders'])
  if (resp.code !== 200 || resp.data === null) {
    return null
  }
  return resp.data.map((o: ServerOrder) => toOrder(o))
}

export async function fetchOrderDetailApi(orderId: number): Promise<Order | null> {
  const resp: ApiResponse<ServerOrder> = await get<ServerOrder>(`/api/orders/${orderId}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return toOrder(resp.data)
}

export async function cancelOrderApi(orderId: number): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/orders/${orderId}/cancel`, undefined)
  return resp.code === 200
}

export async function confirmOrderApi(orderId: number): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/orders/${orderId}/confirm`, undefined)
  return resp.code === 200
}

export async function submitReviewApi(orderId: number, goodsId: number, rating: number, content: string, tags: string[]): Promise<boolean> {
  const req: ReviewRequest = { goodsId: goodsId, rating: rating, content: content, tags: tags }
  const resp: ApiResponse<ServerReview> = await post<ServerReview>(`/api/orders/${orderId}/review`, req)
  return resp.code === 200
}

// ==================== 商户端（需商户登录） ====================

export async function fetchMerchantOrdersApi(): Promise<Order[]> {
  const resp: ApiResponse<ServerOrder[]> = await get<ServerOrder[]>(API_CONFIG.ENDPOINTS['merchantOrders'])
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((o: ServerOrder) => toOrder(o))
}

/**
 * 商户订单流转：action = accept(接单) / deliver(出餐) / complete(完成)
 */
export async function merchantActionApi(orderId: number, action: string): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/merchant/orders/${orderId}/${action}`, undefined)
  return resp.code === 200
}

export async function fetchMerchantStoresApi(): Promise<StoreItem[]> {
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(API_CONFIG.ENDPOINTS['merchantStores'])
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => toStoreItem(s))
}

export async function fetchMerchantGoodsApi(storeId: number): Promise<GoodsItem[]> {
  const resp: ApiResponse<ServerGoods[]> = await get<ServerGoods[]>(`/api/merchant/stores/${storeId}/goods`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((g: ServerGoods) => toGoodsItem(g))
}

export async function createMerchantStoreApi(name: string, categoryId: number, deliveryFee: number,
  minOrder: number, deliveryTime: string, notice: string): Promise<StoreItem | null> {
  const req: MerchantStoreRequest = {
    name: name, categoryId: categoryId, deliveryFee: deliveryFee, minOrder: minOrder,
    deliveryTime: deliveryTime, notice: notice
  }
  const resp: ApiResponse<ServerStore> = await post<ServerStore>(API_CONFIG.ENDPOINTS['merchantStores'], req)
  return resp.code === 200 && resp.data !== null ? toStoreItem(resp.data) : null
}

export async function updateMerchantStoreApi(storeId: number, name: string, deliveryFee: number,
  minOrder: number, deliveryTime: string, notice: string): Promise<StoreItem | null> {
  const req: MerchantStorePatch = {
    name: name, deliveryFee: deliveryFee, minOrder: minOrder,
    deliveryTime: deliveryTime, notice: notice, status: -1
  }
  const resp: ApiResponse<ServerStore> = await put<ServerStore>(`/api/merchant/stores/${storeId}`, req)
  return resp.code === 200 && resp.data !== null ? toStoreItem(resp.data) : null
}

function toMerchantGoodsRequest(goods: GoodsItem, status: number): MerchantGoodsRequest {
  const req: MerchantGoodsRequest = {
    name: goods.name, description: goods.description, price: goods.price,
    originalPrice: goods.originalPrice || goods.price, image: goods.image,
    categoryId: goods.categoryId, tag: goods.tag || '', status: status,
    merchantCategoryId: goods.merchantCategoryId || 0, stock: goods.stock ?? 999
  }
  return req
}

export async function createMerchantGoodsApi(storeId: number, goods: GoodsItem): Promise<GoodsItem | null> {
  const resp: ApiResponse<ServerGoods> = await post<ServerGoods>(
    `/api/merchant/stores/${storeId}/goods`, toMerchantGoodsRequest(goods, 1))
  return resp.code === 200 && resp.data !== null ? toGoodsItem(resp.data) : null
}

export async function updateMerchantGoodsApi(goods: GoodsItem, onShelf: boolean): Promise<GoodsItem | null> {
  const resp: ApiResponse<ServerGoods> = await put<ServerGoods>(
    `/api/merchant/goods/${goods.id}`, toMerchantGoodsRequest(goods, onShelf ? 1 : 0))
  return resp.code === 200 && resp.data !== null ? toGoodsItem(resp.data) : null
}

export async function deleteMerchantGoodsApi(goodsId: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await del<Object>(`/api/merchant/goods/${goodsId}`)
  return resp.code === 200
}

/** 快速补货/清库存（演进项，见大纲 8.4）。 */
export async function updateGoodsStockApi(goodsId: number, stock: number): Promise<GoodsItem | null> {
  const req: StockRequest = { stock: stock }
  const resp: ApiResponse<ServerGoods> = await put<ServerGoods>(`/api/merchant/goods/${goodsId}/stock`, req)
  return resp.code === 200 && resp.data !== null ? toGoodsItem(resp.data) : null
}

// ==================== 商户分类（演进项，见大纲 8.3） ====================

/** 用户端：店铺详情展示的店内商户分类。 */
export async function fetchStoreMerchantCategoriesApi(storeId: number): Promise<Category[]> {
  const resp: ApiResponse<Category[]> = await get<Category[]>(`/api/stores/${storeId}/categories`)
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function fetchMerchantCategoriesApi(): Promise<Category[]> {
  const resp: ApiResponse<Category[]> = await get<Category[]>('/api/merchant/categories')
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function createMerchantCategoryApi(name: string, sort: number): Promise<Category | null> {
  const req: MerchantCategoryRequest = { name: name, sort: sort }
  const resp: ApiResponse<Category> = await post<Category>('/api/merchant/categories', req)
  return resp.code === 200 && resp.data !== null ? resp.data : null
}

export async function updateMerchantCategoryApi(categoryId: number, name: string, sort: number): Promise<Category | null> {
  const req: MerchantCategoryRequest = { name: name, sort: sort }
  const resp: ApiResponse<Category> = await put<Category>(`/api/merchant/categories/${categoryId}`, req)
  return resp.code === 200 && resp.data !== null ? resp.data : null
}

export async function deleteMerchantCategoryApi(categoryId: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await del<Object>(`/api/merchant/categories/${categoryId}`)
  return resp.code === 200
}

// ==================== 退款（演进项，见大纲 7.11/9.7） ====================

/** 用户申请退款：订单 status=4 且 escrow=0 且未评价时可用。 */
export async function applyRefundApi(orderId: number, reason: string): Promise<RefundRecord | null> {
  const req: RefundRequest = { reason: reason }
  const resp: ApiResponse<RefundRecord> = await post<RefundRecord>(`/api/orders/${orderId}/refund`, req)
  return resp.code === 200 && resp.data !== null ? resp.data : null
}

/** 管理端：退款申请列表（status 为空返回全部）。 */
export async function fetchAdminRefundsApi(status?: string): Promise<RefundRecord[]> {
  const url: string = status !== undefined && status !== ''
    ? `/api/admin/refunds?status=${status}`
    : '/api/admin/refunds'
  const resp: ApiResponse<RefundRecord[]> = await get<RefundRecord[]>(url)
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function approveRefundApi(refundId: number): Promise<boolean> {
  const resp: ApiResponse<RefundRecord> = await post<RefundRecord>(`/api/admin/refunds/${refundId}/approve`, undefined)
  return resp.code === 200
}

export async function rejectRefundApi(refundId: number, reason: string): Promise<boolean> {
  const req: RefundRejectRequest = { rejectReason: reason }
  const resp: ApiResponse<RefundRecord> = await post<RefundRecord>(`/api/admin/refunds/${refundId}/reject`, req)
  return resp.code === 200
}

// ==================== 管理端订单与员工 ====================

export async function adminOrderActionApi(orderId: number, action: string): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/admin/orders/${orderId}/${action}`, undefined)
  return resp.code === 200
}

export async function fetchAdminEmployeesApi(): Promise<AdminEmployee[]> {
  const resp: ApiResponse<ServerAdminEmployee[]> = await get<ServerAdminEmployee[]>('/api/admin/employees')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((employee: ServerAdminEmployee) => {
    const result: AdminEmployee = {
      id: employee.id,
      username: employee.username,
      phone: employee.phone,
      role: employee.role,
      status: employee.status,
      storeCount: employee.storeCount,
      createTime: employee.createTime
    }
    return result
  })
}

export async function createAdminEmployeeApi(username: string, phone: string, password: string): Promise<boolean> {
  const req: AdminEmployeeCreateRequest = {
    username: username,
    phone: phone,
    password: password
  }
  const resp: ApiResponse<ServerAdminEmployee> = await post<ServerAdminEmployee>('/api/admin/employees', req)
  return resp.code === 200
}

export async function updateAdminEmployeeApi(id: number, username: string, phone: string): Promise<boolean> {
  const req: AdminEmployeeProfileRequest = { username: username, phone: phone }
  const resp: ApiResponse<ServerAdminEmployee> = await put<ServerAdminEmployee>(`/api/admin/employees/${id}`, req)
  return resp.code === 200
}

export async function updateAdminEmployeeStatusApi(id: number, status: number): Promise<boolean> {
  const req: AdminEmployeeStatusRequest = { status: status }
  const resp: ApiResponse<Object> = await put<Object>(`/api/admin/employees/${id}/status`, req)
  return resp.code === 200
}

// ==================== 平台用户、商品和统计 ====================

export async function fetchAdminUsersApi(role?: number, status?: number, keyword?: string): Promise<AdminUser[]> {
  const params: string[] = []
  if (role !== undefined) {
    params.push(`userRole=${role}`)
  }
  if (status !== undefined) {
    params.push(`status=${status}`)
  }
  if (keyword !== undefined && keyword.trim() !== '') {
    params.push(`keyword=${encodeURIComponent(keyword.trim())}`)
  }
  const url: string = params.length > 0 ? `/api/admin/users?${params.join('&')}` : '/api/admin/users'
  const resp: ApiResponse<ServerAdminUser[]> = await get<ServerAdminUser[]>(url)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((item: ServerAdminUser) => {
    const user: AdminUser = {
      id: item.id, username: item.username, phone: item.phone, role: item.role,
      status: item.status, balance: item.balance, storeCount: item.storeCount, createTime: item.createTime
    }
    return user
  })
}

export async function updateAdminUserStatusApi(id: number, status: number): Promise<boolean> {
  const req: AdminStatusRequest = { status: status }
  const resp: ApiResponse<Object> = await put<Object>(`/api/admin/users/${id}/status`, req)
  return resp.code === 200
}

export async function fetchAdminProductsApi(keyword?: string, status?: number): Promise<AdminProduct[]> {
  const params: string[] = []
  if (keyword !== undefined && keyword.trim() !== '') {
    params.push(`keyword=${encodeURIComponent(keyword.trim())}`)
  }
  if (status !== undefined) {
    params.push(`status=${status}`)
  }
  const url: string = params.length > 0 ? `/api/admin/products?${params.join('&')}` : '/api/admin/products'
  const resp: ApiResponse<ServerAdminProduct[]> = await get<ServerAdminProduct[]>(url)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((item: ServerAdminProduct) => {
    const product: AdminProduct = {
      id: item.id, storeId: item.storeId, storeName: item.storeName, name: item.name,
      description: item.description, price: item.price, originalPrice: item.originalPrice,
      image: item.image, categoryId: item.categoryId, merchantCategoryId: item.merchantCategoryId,
      stock: item.stock, sales: item.sales, rating: item.rating, tag: item.tag,
      status: item.status, createTime: item.createTime
    }
    return product
  })
}

export async function updateAdminProductStatusApi(id: number, status: number): Promise<boolean> {
  const req: AdminStatusRequest = { status: status }
  const resp: ApiResponse<Object> = await put<Object>(`/api/admin/products/${id}/status`, req)
  return resp.code === 200
}

export async function deleteAdminProductApi(id: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await del<Object>(`/api/admin/products/${id}`)
  return resp.code === 200
}

export async function fetchAdminStatisticsApi(hotLimit: number = 10): Promise<AdminStatisticsData | null> {
  const resp: ApiResponse<ServerAdminStatistics> = await get<ServerAdminStatistics>(`/api/admin/statistics/overview?hotLimit=${hotLimit}`)
  if (resp.code !== 200 || resp.data === null) {
    return null
  }
  const hotGoods: AdminHotGoods[] = (resp.data.hotGoods || []).map((item: ServerAdminHotGoods): AdminHotGoods => {
    const goods: AdminHotGoods = {
      goodsId: item.goodsId, goodsName: item.goodsName, storeId: item.storeId,
      storeName: item.storeName, sales: item.sales, price: item.price, status: item.status
    }
    return goods
  })
  const result: AdminStatisticsData = {
    totalUsers: resp.data.totalUsers, totalMerchants: resp.data.totalMerchants,
    totalStores: resp.data.totalStores, totalGoods: resp.data.totalGoods,
    totalOrders: resp.data.totalOrders, totalGmv: resp.data.totalGmv,
    settledAmount: resp.data.settledAmount, pendingEscrowAmount: resp.data.pendingEscrowAmount,
    todayOrders: resp.data.todayOrders, todayGmv: resp.data.todayGmv, hotGoods: hotGoods
  }
  return result
}

export async function fetchAdminOrderTrendApi(days: number): Promise<AdminTrendPoint[]> {
  const resp: ApiResponse<ServerAdminTrendPoint[]> = await get<ServerAdminTrendPoint[]>(`/api/admin/statistics/order-trend?days=${days}`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((item: ServerAdminTrendPoint) => {
    const point: AdminTrendPoint = { date: item.date, orderCount: item.orderCount, gmv: item.gmv }
    return point
  })
}

// ==================== 用户中心（需登录） ====================

export async function fetchCouponsApi(): Promise<Coupon[]> {
  const resp: ApiResponse<ServerCoupon[]> = await get<ServerCoupon[]>(API_CONFIG.ENDPOINTS['coupons'])
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((c: ServerCoupon) => toCoupon(c))
}

export async function claimCouponApi(storeId: number, name: string, threshold: number, amount: number): Promise<boolean> {
  const req: CouponClaimRequest = { storeId: storeId, name: name, threshold: threshold, amount: amount }
  const resp: ApiResponse<ServerCoupon> = await post<ServerCoupon>('/api/coupons/claim', req)
  return resp.code === 200
}

export async function fetchFavoritesApi(): Promise<Favorite[]> {
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(API_CONFIG.ENDPOINTS['favorites'])
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => {
    const fav: Favorite = {
      id: s.id,
      userId: 0,
      storeId: s.id,
      storeName: s.name,
      storeImage: s.image,
      createTime: ''
    }
    return fav
  })
}

export async function toggleFavoriteApi(storeId: number): Promise<boolean> {
  const resp: ApiResponse<boolean> = await post<boolean>(`${API_CONFIG.ENDPOINTS['favorites']}/toggle?storeId=${storeId}`, undefined)
  return resp.code === 200 ? (resp.data === true) : false
}

export async function fetchAddressesApi(): Promise<Address[]> {
  const resp: ApiResponse<ServerAddress[]> = await get<ServerAddress[]>(API_CONFIG.ENDPOINTS['addresses'])
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((a: ServerAddress) => toAddress(a))
}

export async function addAddressApi(name: string, phone: string, detail: string, isDefault: boolean): Promise<boolean> {
  const req: AddressRequest = { name: name, phone: phone, detail: detail, isDefault: isDefault ? 1 : 0 }
  const resp: ApiResponse<ServerAddress> = await post<ServerAddress>(API_CONFIG.ENDPOINTS['addresses'], req)
  return resp.code === 200
}

export async function addAddressAndFetchApi(name: string, phone: string, detail: string, isDefault: boolean): Promise<Address | null> {
  const req: AddressRequest = { name: name, phone: phone, detail: detail, isDefault: isDefault ? 1 : 0 }
  const resp: ApiResponse<ServerAddress> = await post<ServerAddress>(API_CONFIG.ENDPOINTS['addresses'], req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return toAddress(resp.data)
}

export async function deleteAddressApi(addressId: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await del<Object>(`/api/addresses/${addressId}`)
  return resp.code === 200
}

export async function updateAddressApi(addressId: number, name: string, phone: string, detail: string, isDefault: boolean): Promise<boolean> {
  const req: AddressRequest = { name: name, phone: phone, detail: detail, isDefault: isDefault ? 1 : 0 }
  const resp: ApiResponse<ServerAddress> = await put<ServerAddress>(`/api/addresses/${addressId}`, req)
  return resp.code === 200
}

export async function setDefaultAddressApi(addressId: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await put<Object>(`/api/addresses/${addressId}/default`, undefined)
  return resp.code === 200
}

// ==================== 模型转换 ====================

function toUser(u: ServerUser): User {
  const user: User = {
    id: u.id,
    username: u.username,
    avatar: u.avatar,
    phone: u.phone,
    password: '',
    role: u.role === 2 ? UserRole.ADMIN : u.role === 1 ? UserRole.MERCHANT : UserRole.CUSTOMER,
    balance: u.balance,
    coupons: [],
    orders: [],
    storeIds: []
  }
  return user
}

function toStoreItem(s: ServerStore): StoreItem {
  const store: StoreItem = {
    id: s.id,
    name: s.name,
    image: s.image,
    rating: s.rating,
    monthlySales: s.monthlySales,
    deliveryFee: s.deliveryFee,
    minOrder: s.minOrder,
    deliveryTime: s.deliveryTime,
    distance: s.distance,
    tags: s.tags || [],
    notice: s.notice,
    categoryId: s.categoryId,
    categoryIds: s.categoryIds || [],
    ownerId: s.ownerId,
    recommended: s.recommended || 0
  }
  return store
}

function toGoodsItem(g: ServerGoods): GoodsItem {
  const goods: GoodsItem = {
    id: g.id,
    name: g.name,
    description: g.description,
    price: g.price,
    originalPrice: g.originalPrice,
    image: g.image,
    categoryId: g.categoryId,
    merchantCategoryId: g.merchantCategoryId,
    stock: g.stock,
    sales: g.sales,
    rating: g.rating,
    tag: g.tag,
    isOnShelf: g.status === 1
  }
  return goods
}

function toOrder(o: ServerOrder): Order {
  const items: CartItem[] = (o.items || []).map((it: ServerOrderItem) => {
    const goods: GoodsItem = {
      id: it.goodsId,
      name: it.goodsName,
      description: '',
      price: it.price,
      image: it.image,
      categoryId: 1,
      sales: 0,
      rating: 4.5
    }
    const cart: CartItem = {
      goods: goods,
      quantity: it.quantity,
      storeId: o.storeId,
      storeName: o.storeName
    }
    return cart
  })
  const addr: Address = {
    id: o.address !== null && o.address !== undefined ? o.address.addressId : 0,
    name: o.address !== null && o.address !== undefined ? o.address.name : '',
    phone: o.address !== null && o.address !== undefined ? o.address.phone : '',
    address: '',
    detail: o.address !== null && o.address !== undefined ? o.address.detail : '',
    isDefault: false
  }
  const order: Order = {
    id: o.id,
    storeId: o.storeId,
    storeName: o.storeName,
    storeImage: '',
    items: items,
    totalPrice: o.goodsAmount,
    deliveryFee: o.deliveryFee,
    discountAmount: o.discount,
    payAmount: o.payAmount,
    status: o.status,
    escrowStatus: o.escrowStatus,
    reviewed: o.reviewed,
    createTime: o.createTime,
    payTime: o.payTime,
    deliverTime: o.deliverTime,
    completeTime: o.completeTime,
    address: addr,
    remark: o.remark
  }
  return order
}

function toCoupon(c: ServerCoupon): Coupon {
  const coupon: Coupon = {
    id: c.id,
    amount: c.amount,
    minOrder: c.threshold,
    startTime: c.createTime,
    endTime: c.expireTime,
    used: c.status === 1,
    storeId: c.storeId,
    storeName: '',
    condition: `满${Math.round(c.threshold)}减${Math.round(c.amount)}`
  }
  return coupon
}

function toAddress(a: ServerAddress): Address {
  const addr: Address = {
    id: a.id,
    name: a.name,
    phone: a.phone,
    // 服务端仅保存合并后的地址文本，回填到 address 字段可保证列表展示和编辑内容一致。
    address: a.detail,
    detail: '',
    isDefault: a.isDefault === 1
  }
  return addr
}

function toReview(r: ServerReview): Review {
  const review: Review = {
    id: r.id,
    orderId: 0,
    storeId: r.storeId,
    goodsId: r.goodsId || 0,
    userId: r.userId,
    username: r.userName,
    rating: r.rating,
    content: r.content,
    tags: r.tags || [],
    createTime: r.createTime
  }
  return review
}
