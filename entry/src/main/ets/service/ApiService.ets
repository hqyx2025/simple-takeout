/**
 * 后端 API 适配层
 * 负责：调用后端 REST API（HttpClient）+ 后端 JSON 与客户端 Models 之间的双向转换
 * 所有页面/服务层通过本模块访问真实后端数据
 */
import { get, post, put, del, uploadFile, ApiResponse, setAuthToken } from './HttpClient'
import { API_CONFIG } from '../common/Constants'
import {
  User, UserRole, StoreItem, GoodsItem, SpecialGoodsItem, Category, Order, CartItem,
  Address, Coupon, Review, Rider, Banner, Announcement, Favorite, RefundRecord, AdminEmployee, AdminProduct, AdminUser,
  BankCard,
  AdminStatisticsData, AdminTrendPoint, AdminHotGoods, SeckillItem, BundleInfo, UploadResult, GoodsSpec
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
  address?: string
  latitude?: number
  longitude?: number
  categoryId: number
  categoryIds: number[]
  ownerId: number
  status: number
  recommended: number
}

interface ServerGoodsSpec {
  id: number
  goodsId: number
  name: string
  price: number
  stock: number
  sort: number
  status: number
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
  special: boolean
  status: number
  specs?: ServerGoodsSpec[]
}

interface ServerSpecialGoods {
  goods: ServerGoods
  storeName: string
  storeDistance: string
}

interface ServerOrderItem {
  goodsId: number
  goodsName: string
  price: number
  quantity: number
  image: string
  specId?: number
  specName?: string
}

interface ServerCartItem {
  id: number
  goodsId: number
  storeId: number
  storeName: string
  specId?: number
  specName?: string
  price?: number
  stock?: number
  quantity: number
  goods: ServerGoods
}

interface ServerSeckill {
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
  remainSeconds: number
}

interface ServerBundle {
  storeId: number
  storeName: string
  minOrder: number
  amount: number
  gap: number
  suggestions: ServerGoods[]
}

interface ServerUploadResult {
  url: string
  size: number
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
  expectTime: string
  riderName: string
  riderPhone: string
  couponId?: number
  payDeadline?: string
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

/** 钱包银行卡：cardNoMasked 已是掩码卡号（服务端只存后四位，不下发完整卡号）。 */
interface ServerBankCard {
  id: number
  bankName: string
  cardType: string
  cardNoMasked: string
  isDefault: number
  createTime: string
}

interface ServerReview {
  id: number
  orderId: number
  storeId: number
  goodsId: number
  userId: number
  userName: string
  rating: number
  content: string
  tags: string[]
  images: string[]
  anonymous: number
  reply: string
  replyTime: string
  createTime: string
}

interface ServerRider {
  id: number
  userId: number
  name: string
  phone: string
  online: number
  totalOrders: number
  totalIncome: number
  status: number
  createTime: string
}

interface ServerBanner {
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

interface ServerAnnouncement {
  id: number
  title: string
  content: string
  status: number
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

interface RechargeRequest {
  amount: number
}

interface OrderItemRequest {
  goodsId: number
  goodsName: string
  price: number
  quantity: number
  image: string
  specId: number
  specName: string
}

interface CreateOrderRequest {
  storeId: number
  items: OrderItemRequest[]
  addressId: number
  couponId: number
  remark: string
  checkoutGoodsIds: number[]
  expectTime: string
}

interface CartItemRequest {
  goodsId: number
  specId: number
  quantity: number
}

interface CartQuantityRequest {
  quantity: number
}

interface ReviewRequest {
  goodsId: number
  rating: number
  content: string
  tags: string[]
  images: string[]
  anonymous: number
}

interface ReplyRequest {
  reply: string
}

interface RiderStatusRequest {
  online: number
}

interface BannerRequest {
  title: string
  subtitle: string
  image: string
  color: string
  linkType: string
  linkValue: string
  sort: number
}

interface AnnouncementRequest {
  title: string
  content: string
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
  address: string
  latitude: number
  longitude: number
}

interface MerchantStorePatch {
  name: string
  deliveryFee: number
  minOrder: number
  deliveryTime: string
  notice: string
  address: string
  latitude: number
  longitude: number
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
  special: boolean
  status: number
  /** 多规格：非空时后端按规格聚合价格与库存；省略表示本次不修改规格 */
  specs?: SpecInputRequest[]
}

/** 商户提交的规格项（id=0 表示新增） */
interface SpecInputRequest {
  id: number
  name: string
  price: number
  stock: number
}

interface GoodsSpecsRequest {
  specs: SpecInputRequest[]
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
  const req: RegisterRequest = { username: username, phone: phone, password: password, role: toServerRole(role) }
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

export async function fetchCurrentUserApi(): Promise<User | undefined> {
  // /auth/me 是账户余额的权威来源，增加时间戳避免 GET 缓存返回旧余额。
  const resp: ApiResponse<ServerUser> = await get<ServerUser>(`/api/auth/me?refreshAt=${Date.now()}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `获取当前用户失败：${resp.message}`)
    return undefined
  }
  return toUser(resp.data)
}

export async function rechargeBalanceApi(amount: number): Promise<User | undefined> {
  const req: RechargeRequest = { amount: amount }
  const resp: ApiResponse<ServerUser> = await post<ServerUser>(API_CONFIG.ENDPOINTS['recharge'], req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    logWarn('Api', `测试充值失败：${resp.message}`)
    return undefined
  }
  const user: User = toUser(resp.data)
  logInfo('Api', `充值接口返回余额=${user.balance.toFixed(2)}`)
  return user
}

// ==================== 数据拉取（游客可访问） ====================

function appendCoordinates(url: string, latitude?: number, longitude?: number): string {
  if (latitude === undefined || longitude === undefined
    || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return url
  }
  const separator: string = url.indexOf('?') >= 0 ? '&' : '?'
  return `${url}${separator}latitude=${latitude}&longitude=${longitude}`
}

export async function fetchCategories(): Promise<Category[]> {
  const resp: ApiResponse<Category[]> = await get<Category[]>(API_CONFIG.ENDPOINTS['categories'])
  return resp.code === 200 ? (resp.data || []) : []
}

export async function fetchStores(categoryId?: number, latitude?: number, longitude?: number): Promise<StoreItem[]> {
  const baseUrl: string = categoryId !== undefined && categoryId > 0
    ? `${API_CONFIG.ENDPOINTS['stores']}?categoryId=${categoryId}`
    : API_CONFIG.ENDPOINTS['stores']
  const url: string = appendCoordinates(baseUrl, latitude, longitude)
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(url)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => toStoreItem(s))
}

export async function fetchRecommendedStoresApi(maxDistanceKm: number = 2, limit: number = 10,
  latitude?: number, longitude?: number): Promise<StoreItem[]> {
  const baseUrl: string = `/api/stores/recommended?maxDistanceKm=${maxDistanceKm}&limit=${limit}`
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(
    appendCoordinates(baseUrl, latitude, longitude))
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

/** 店铺详情：获取权威店铺信息（rating/notice/deliveryFee/minOrder 等），避免依赖列表缓存导致数据陈旧。 */
export async function fetchStoreDetailApi(storeId: number): Promise<StoreItem | null> {
  const resp: ApiResponse<ServerStore> = await get<ServerStore>(`/api/stores/${storeId}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return toStoreItem(resp.data)
}

export async function fetchSpecialGoodsApi(limit: number = 10, latitude?: number, longitude?: number): Promise<SpecialGoodsItem[]> {
  const baseUrl: string = `/api/goods/special?limit=${limit}`
  const resp: ApiResponse<ServerSpecialGoods[]> = await get<ServerSpecialGoods[]>(
    appendCoordinates(baseUrl, latitude, longitude))
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((item: ServerSpecialGoods): SpecialGoodsItem => {
    const result: SpecialGoodsItem = {
      goods: toGoodsItem(item.goods),
      storeName: item.storeName,
      storeDistance: item.storeDistance
    }
    return result
  })
}

export async function fetchStoreReviews(storeId: number): Promise<Review[]> {
  const resp: ApiResponse<ServerReview[]> = await get<ServerReview[]>(`/api/stores/${storeId}/reviews`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerReview) => toReview(r))
}

// ==================== 营销：榜单 / 限时秒杀 / 凑单 ====================

/** 店铺榜（按月销量与评分）。 */
export async function fetchRankStoresApi(limit: number = 10, latitude?: number, longitude?: number): Promise<StoreItem[]> {
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(
    appendCoordinates(`/api/rankings/stores?limit=${limit}`, latitude, longitude))
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => toStoreItem(s))
}

/** 菜品榜（热销榜）。 */
export async function fetchRankGoodsApi(limit: number = 10, latitude?: number, longitude?: number): Promise<SpecialGoodsItem[]> {
  const resp: ApiResponse<ServerSpecialGoods[]> = await get<ServerSpecialGoods[]>(
    appendCoordinates(`/api/rankings/goods?limit=${limit}`, latitude, longitude))
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((item: ServerSpecialGoods): SpecialGoodsItem => {
    const result: SpecialGoodsItem = {
      goods: toGoodsItem(item.goods),
      storeName: item.storeName,
      storeDistance: item.storeDistance
    }
    return result
  })
}

/** 首页限时秒杀（时间窗口内且仍有名额）。 */
export async function fetchSeckillsApi(limit: number = 6, latitude?: number, longitude?: number): Promise<SeckillItem[]> {
  const resp: ApiResponse<ServerSeckill[]> = await get<ServerSeckill[]>(
    appendCoordinates(`/api/seckills?limit=${limit}`, latitude, longitude))
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerSeckill): SeckillItem => {
    const item: SeckillItem = {
      id: s.id,
      goodsId: s.goodsId,
      goodsName: s.goodsName,
      image: s.image,
      originalPrice: s.originalPrice,
      price: s.price,
      quota: s.quota,
      sold: s.sold,
      startTime: s.startTime,
      endTime: s.endTime,
      storeId: s.storeId,
      storeName: s.storeName,
      storeDistance: s.storeDistance,
      remainSeconds: s.remainSeconds
    }
    return item
  })
}

/** 凑单提示：还差多少元起送 + 店内可凑单菜品。 */
export async function fetchBundleApi(storeId: number, amount: number): Promise<BundleInfo | null> {
  const resp: ApiResponse<ServerBundle> = await get<ServerBundle>(`/api/stores/${storeId}/bundle?amount=${amount}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  const data: ServerBundle = resp.data
  const bundle: BundleInfo = {
    storeId: data.storeId,
    storeName: data.storeName,
    minOrder: data.minOrder,
    amount: data.amount,
    gap: data.gap,
    suggestions: (data.suggestions || []).map((g: ServerGoods) => toGoodsItem(g))
  }
  return bundle
}

/** 图文评价图片上传：返回相对地址（需拼接 API_CONFIG.BASE_URL 展示）。 */
export async function uploadImageApi(fileUri: string, showErrorToast: boolean = true): Promise<UploadResult | null> {
  const url: string = API_CONFIG.BASE_URL + API_CONFIG.ENDPOINTS['upload']
  const result: UploadResult | null = await uploadFile(url, fileUri, showErrorToast)
  return result
}

export async function fetchGoodsReviews(goodsId: number): Promise<Review[]> {
  const resp: ApiResponse<ServerReview[]> = await get<ServerReview[]>(`/api/goods/${goodsId}/reviews`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerReview) => toReview(r))
}

export async function fetchMerchantReviewsApi(): Promise<Review[]> {
  const resp: ApiResponse<ServerReview[]> = await get<ServerReview[]>('/api/merchant/reviews')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerReview) => toReview(r))
}

export async function replyReviewApi(reviewId: number, reply: string): Promise<boolean> {
  const req: ReplyRequest = { reply: reply }
  const resp: ApiResponse<ServerReview> = await put<ServerReview>(`/api/merchant/reviews/${reviewId}/reply`, req)
  return resp.code === 200
}

// ==================== 骑手端（role=3） ====================

export async function fetchRiderProfileApi(): Promise<Rider | null> {
  const resp: ApiResponse<ServerRider> = await get<ServerRider>('/api/rider/profile')
  if (resp.code !== 200 || resp.data === null) {
    return null
  }
  return toRider(resp.data)
}

export async function setRiderStatusApi(online: number): Promise<Rider | null> {
  const req: RiderStatusRequest = { online: online }
  const resp: ApiResponse<ServerRider> = await put<ServerRider>('/api/rider/status', req)
  if (resp.code !== 200 || resp.data === null) {
    return null
  }
  return toRider(resp.data)
}

export async function fetchRiderPoolApi(): Promise<Order[]> {
  const resp: ApiResponse<ServerOrder[]> = await get<ServerOrder[]>('/api/rider/orders/pool')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((o: ServerOrder) => toOrder(o))
}

export async function fetchRiderOrdersApi(): Promise<Order[]> {
  const resp: ApiResponse<ServerOrder[]> = await get<ServerOrder[]>('/api/rider/orders')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((o: ServerOrder) => toOrder(o))
}

export async function grabOrderApi(orderId: number): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(`/api/rider/orders/${orderId}/grab`, undefined)
  return resp.code === 200
}

export async function pickupOrderApi(orderId: number): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/rider/orders/${orderId}/pickup`, undefined)
  return resp.code === 200
}

export async function deliverOrderApi(orderId: number): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/rider/orders/${orderId}/deliver`, undefined)
  return resp.code === 200
}

// ==================== 内容管理（Banner / 公告） ====================

export async function fetchBannersApi(): Promise<Banner[]> {
  const resp: ApiResponse<ServerBanner[]> = await get<ServerBanner[]>('/api/banners')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((b: ServerBanner) => toBanner(b))
}

export async function fetchAnnouncementsApi(): Promise<Announcement[]> {
  const resp: ApiResponse<ServerAnnouncement[]> = await get<ServerAnnouncement[]>('/api/announcements')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((a: ServerAnnouncement) => toAnnouncement(a))
}

// ==================== 管理端：骑手管理 / 内容管理 ====================

export async function fetchAdminRidersApi(): Promise<Rider[]> {
  const resp: ApiResponse<ServerRider[]> = await get<ServerRider[]>('/api/admin/riders')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerRider) => toRider(r))
}

export async function updateRiderStatusApi(riderId: number, status: number): Promise<boolean> {
  const req: AdminStatusRequest = { status: status }
  const resp: ApiResponse<ServerRider> = await put<ServerRider>(`/api/admin/riders/${riderId}/status`, req)
  return resp.code === 200
}

export async function fetchAdminBannersApi(): Promise<Banner[]> {
  const resp: ApiResponse<ServerBanner[]> = await get<ServerBanner[]>('/api/admin/banners')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((b: ServerBanner) => toBanner(b))
}

export async function createBannerApi(title: string, subtitle: string, image: string, color: string,
                                      linkType: string, linkValue: string, sort: number): Promise<boolean> {
  const req: BannerRequest = {
    title: title, subtitle: subtitle, image: image, color: color,
    linkType: linkType, linkValue: linkValue, sort: sort
  }
  const resp: ApiResponse<ServerBanner> = await post<ServerBanner>('/api/admin/banners', req)
  return resp.code === 200
}

export async function updateBannerStatusApi(bannerId: number, status: number): Promise<boolean> {
  const req: AdminStatusRequest = { status: status }
  const resp: ApiResponse<ServerBanner> = await put<ServerBanner>(`/api/admin/banners/${bannerId}/status`, req)
  return resp.code === 200
}

export async function deleteBannerApi(bannerId: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await del<Object>(`/api/admin/banners/${bannerId}`)
  return resp.code === 200
}

export async function fetchAdminAnnouncementsApi(): Promise<Announcement[]> {
  const resp: ApiResponse<ServerAnnouncement[]> = await get<ServerAnnouncement[]>('/api/admin/announcements')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((a: ServerAnnouncement) => toAnnouncement(a))
}

export async function createAnnouncementApi(title: string, content: string): Promise<boolean> {
  const req: AnnouncementRequest = { title: title, content: content }
  const resp: ApiResponse<ServerAnnouncement> = await post<ServerAnnouncement>('/api/admin/announcements', req)
  return resp.code === 200
}

export async function updateAnnouncementStatusApi(announcementId: number, status: number): Promise<boolean> {
  const req: AdminStatusRequest = { status: status }
  const resp: ApiResponse<ServerAnnouncement> = await put<ServerAnnouncement>(`/api/admin/announcements/${announcementId}/status`, req)
  return resp.code === 200
}

export async function deleteAnnouncementApi(announcementId: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await del<Object>(`/api/admin/announcements/${announcementId}`)
  return resp.code === 200
}

export async function searchStoresApi(keyword: string, latitude?: number, longitude?: number): Promise<StoreItem[]> {
  const baseUrl: string = `${API_CONFIG.ENDPOINTS['search']}?keyword=${encodeURIComponent(keyword)}`
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(appendCoordinates(baseUrl, latitude, longitude))
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((s: ServerStore) => toStoreItem(s))
}

// ==================== 购物车（需登录） ====================

function toCartItem(item: ServerCartItem): CartItem {
  const goods: GoodsItem = toGoodsItem(item.goods)
  return {
    goods: goods,
    quantity: item.quantity,
    storeId: item.storeId,
    storeName: item.storeName,
    specId: item.specId ?? 0,
    specName: item.specName ?? '',
    price: item.price ?? goods.price,
    stock: item.stock ?? goods.stock
  }
}

export async function fetchCartApi(): Promise<CartItem[] | null> {
  const resp: ApiResponse<ServerCartItem[]> = await get<ServerCartItem[]>('/api/cart')
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return resp.data.map((item: ServerCartItem) => toCartItem(item))
}

/** 加入购物车：多规格菜品必须传 specId（无规格传 0）。 */
export async function addCartItemApi(goodsId: number, specId: number, quantity: number): Promise<CartItem[] | null> {
  const req: CartItemRequest = { goodsId: goodsId, specId: specId, quantity: quantity }
  const resp: ApiResponse<ServerCartItem[]> = await post<ServerCartItem[]>('/api/cart/items', req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return resp.data.map((item: ServerCartItem) => toCartItem(item))
}

export async function updateCartItemQuantityApi(goodsId: number, specId: number, quantity: number): Promise<CartItem[] | null> {
  const req: CartQuantityRequest = { quantity: quantity }
  const resp: ApiResponse<ServerCartItem[]> = await put<ServerCartItem[]>(`/api/cart/items/${goodsId}?specId=${specId}`, req)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return resp.data.map((item: ServerCartItem) => toCartItem(item))
}

export async function deleteCartItemApi(goodsId: number, specId: number): Promise<CartItem[] | null> {
  const resp: ApiResponse<ServerCartItem[]> = await del<ServerCartItem[]>(`/api/cart/items/${goodsId}?specId=${specId}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return resp.data.map((item: ServerCartItem) => toCartItem(item))
}

export async function deleteCartItemsApi(goodsIds: number[]): Promise<CartItem[] | null> {
  const query: string = goodsIds.map((goodsId: number) => `goodsIds=${goodsId}`).join('&')
  const resp: ApiResponse<ServerCartItem[]> = await del<ServerCartItem[]>(`/api/cart/items?${query}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return resp.data.map((item: ServerCartItem) => toCartItem(item))
}

export async function clearCartApi(): Promise<CartItem[] | null> {
  const resp: ApiResponse<ServerCartItem[]> = await del<ServerCartItem[]>('/api/cart')
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return resp.data.map((item: ServerCartItem) => toCartItem(item))
}

// ==================== 订单（需登录） ====================

/**
 * 创建订单：items 为购物车项，返回服务端订单（已转换）
 */
export async function createOrderApi(storeId: number, cartItems: CartItem[], addressId: number, couponId: number, remark: string, checkoutGoodsIds: number[], expectTime: string): Promise<Order | null> {
  const items: OrderItemRequest[] = cartItems.map((c: CartItem) => {
    const item: OrderItemRequest = {
      goodsId: c.goods.id,
      goodsName: c.goods.name,
      price: c.price ?? c.goods.price,
      quantity: c.quantity,
      image: c.goods.image,
      specId: c.specId ?? 0,
      specName: c.specName ?? ''
    }
    return item
  })
  const req: CreateOrderRequest = {
    storeId: storeId,
    items: items,
    addressId: addressId,
    couponId: couponId,
    remark: remark,
    checkoutGoodsIds: checkoutGoodsIds,
    expectTime: expectTime
  }
  // 下单失败由结算页统一提示，避免 HttpClient 与结算页连续弹出两个 Toast 互相覆盖。
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(API_CONFIG.ENDPOINTS['orders'], req, false)
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

/** 支付待付款订单：扣余额并流转到待接单（余额支付模型）。 */
export async function payOrderApi(orderId: number): Promise<Order | null> {
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(`/api/orders/${orderId}/pay`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return toOrder(resp.data)
}

export async function confirmOrderApi(orderId: number): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/orders/${orderId}/confirm`, undefined)
  return resp.code === 200
}

export async function submitReviewApi(orderId: number, goodsId: number, rating: number, content: string, tags: string[], images: string[], anonymous: number): Promise<boolean> {
  const req: ReviewRequest = { goodsId: goodsId, rating: rating, content: content, tags: tags, images: images, anonymous: anonymous }
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
  minOrder: number, deliveryTime: string, notice: string, address: string,
  latitude: number, longitude: number): Promise<StoreItem | null> {
  const req: MerchantStoreRequest = {
    name: name, categoryId: categoryId, deliveryFee: deliveryFee, minOrder: minOrder,
    deliveryTime: deliveryTime, notice: notice, address: address, latitude: latitude, longitude: longitude
  }
  const resp: ApiResponse<ServerStore> = await post<ServerStore>(API_CONFIG.ENDPOINTS['merchantStores'], req)
  return resp.code === 200 && resp.data !== null ? toStoreItem(resp.data) : null
}

export async function updateMerchantStoreApi(storeId: number, name: string, deliveryFee: number,
  minOrder: number, deliveryTime: string, notice: string, address: string,
  latitude: number, longitude: number): Promise<StoreItem | null> {
  const req: MerchantStorePatch = {
    name: name, deliveryFee: deliveryFee, minOrder: minOrder,
    deliveryTime: deliveryTime, notice: notice, address: address,
    latitude: latitude, longitude: longitude, status: -1
  }
  const resp: ApiResponse<ServerStore> = await put<ServerStore>(`/api/merchant/stores/${storeId}`, req)
  return resp.code === 200 && resp.data !== null ? toStoreItem(resp.data) : null
}

function toMerchantGoodsRequest(goods: GoodsItem, status: number): MerchantGoodsRequest {
  const req: MerchantGoodsRequest = {
    name: goods.name, description: goods.description, price: goods.price,
    originalPrice: goods.originalPrice !== undefined ? goods.originalPrice : goods.price, image: goods.image,
    categoryId: goods.categoryId, tag: goods.tag || '', status: status,
    merchantCategoryId: goods.merchantCategoryId || 0, stock: goods.stock ?? 999,
    special: goods.isSpecial === true
  }
  // 多规格：仅在有规格时随商品一起提交；清空规格走专用接口，避免误删商户已维护的规格
  if (goods.specs !== undefined && goods.specs.length > 0) {
    req.specs = toSpecInputs(goods.specs)
  }
  return req
}

function toSpecInputs(specs: GoodsSpec[]): SpecInputRequest[] {
  return specs.map((s: GoodsSpec): SpecInputRequest => {
    const input: SpecInputRequest = { id: s.id, name: s.name, price: s.price, stock: s.stock }
    return input
  })
}

/** 商户整体覆盖菜品规格（含清空：传空数组即可）。 */
export async function updateMerchantGoodsSpecsApi(goodsId: number, specs: GoodsSpec[]): Promise<GoodsItem | null> {
  const req: GoodsSpecsRequest = { specs: toSpecInputs(specs) }
  const resp: ApiResponse<ServerGoods> = await put<ServerGoods>(`/api/merchant/goods/${goodsId}/specs`, req)
  return resp.code === 200 && resp.data !== null ? toGoodsItem(resp.data) : null
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

// ==================== 钱包：已绑定银行卡（只读） ====================

export async function fetchBankCardsApi(): Promise<BankCard[]> {
  const resp: ApiResponse<ServerBankCard[]> = await get<ServerBankCard[]>('/api/wallet/bank-cards')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((c: ServerBankCard) => {
    const card: BankCard = {
      id: c.id,
      bankName: c.bankName,
      cardType: c.cardType,
      cardNoMasked: c.cardNoMasked,
      isDefault: c.isDefault === 1,
      createTime: c.createTime
    }
    return card
  })
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

/**
 * 前端角色 → 服务端角色码（0=用户 1=商户 2=管理端 3=骑手）。
 * 与 toUser() 必须成对覆盖全部四种角色：只用「是商户吗」二分会让骑手注册成 role=0，
 * 注册虽然返回成功，但注册后的自动登录带 loginType=RIDER，服务端按角色校验直接 403，
 * 表现为「骑手注册成功却始终进不去骑手端」。
 */
function toServerRole(role: UserRole): number {
  return role === UserRole.MERCHANT ? 1
    : role === UserRole.ADMIN ? 2
    : role === UserRole.RIDER ? 3
    : 0
}

function toUser(u: ServerUser): User {
  const user: User = {
    id: u.id,
    username: u.username,
    avatar: u.avatar,
    phone: u.phone,
    password: '',
    // 角色映射必须覆盖骑手（role=3）：漏掉时骑手会被当成普通用户，
    // 登录页的角色校验（user.role !== 期望角色）随即 logout()，骑手端完全进不去。
    role: u.role === 2 ? UserRole.ADMIN
      : u.role === 1 ? UserRole.MERCHANT
      : u.role === 3 ? UserRole.RIDER
      : UserRole.CUSTOMER,
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
    address: s.address || '',
    latitude: s.latitude,
    longitude: s.longitude,
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
    storeId: g.storeId,
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
    isSpecial: g.special === true,
    isOnShelf: g.status === 1,
    specs: (g.specs || []).map((s: ServerGoodsSpec): GoodsSpec => {
      const spec: GoodsSpec = {
        id: s.id,
        goodsId: s.goodsId,
        name: s.name,
        price: s.price,
        stock: s.stock,
        sort: s.sort,
        status: s.status
      }
      return spec
    })
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
      storeName: o.storeName,
      specId: it.specId ?? 0,
      specName: it.specName ?? '',
      price: it.price
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
    expectTime: o.expectTime || '',
    payDeadline: o.payDeadline || '',
    couponId: o.couponId ?? 0,
    orderNo: o.orderNo || '',
    riderName: o.riderName || '',
    riderPhone: o.riderPhone || '',
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
    // 券状态 0=可用 1=已使用 2=已过期失效：只有 0 才可用，
    // 否则过期券会被列进「可用券」，选中后下单必被后端拒绝（提示还与券列表自相矛盾）
    used: c.status !== 0,
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
    orderId: r.orderId || 0,
    storeId: r.storeId,
    goodsId: r.goodsId || 0,
    userId: r.userId,
    username: r.userName,
    rating: r.rating,
    content: r.content,
    tags: r.tags || [],
    images: r.images || [],
    anonymous: r.anonymous || 0,
    reply: r.reply || '',
    replyTime: r.replyTime || '',
    createTime: r.createTime
  }
  return review
}

function toRider(r: ServerRider): Rider {
  const rider: Rider = {
    id: r.id,
    userId: r.userId,
    name: r.name,
    phone: r.phone,
    online: r.online,
    totalOrders: r.totalOrders,
    totalIncome: r.totalIncome,
    status: r.status,
    createTime: r.createTime
  }
  return rider
}

function toBanner(b: ServerBanner): Banner {
  const banner: Banner = {
    id: b.id,
    title: b.title,
    subtitle: b.subtitle || '',
    image: b.image || '',
    color: b.color || '#FF6B35',
    linkType: b.linkType || 'NONE',
    linkValue: b.linkValue || '',
    sort: b.sort || 0,
    status: b.status,
    createTime: b.createTime
  }
  return banner
}

function toAnnouncement(a: ServerAnnouncement): Announcement {
  const announcement: Announcement = {
    id: a.id,
    title: a.title,
    content: a.content,
    status: a.status,
    createTime: a.createTime
  }
  return announcement
}
