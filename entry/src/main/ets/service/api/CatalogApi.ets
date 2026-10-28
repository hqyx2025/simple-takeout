import { get, post, put, del, ApiResponse } from '../HttpClient'

import { API_CONFIG } from '../../common/Constants'
import { StoreItem, GoodsItem, SpecialGoodsItem, Category, Order, Address, Coupon, Review, Banner, Announcement, Favorite, SeckillItem, BundleInfo } from '../../model/Models'

import { ServerStore, ServerGoods, ServerSpecialGoods, ServerSeckill, ServerBundle, ServerOrder, ServerCoupon, ServerAddress, ServerReview, ServerBanner, ServerAnnouncement, ReplyRequest, BannerRequest, AnnouncementRequest, AddressRequest, CouponClaimRequest, AdminStatusRequest, StockRequest } from '../../model/server/Contracts'
import { toStoreItem, toGoodsItem, toOrder, toCoupon, toAddress, toReview, toBanner, toAnnouncement } from '../../model/server/Converters'

// ==================== 数据拉取（游客可访问） ====================

export function appendCoordinates(url: string, latitude?: number, longitude?: number): string {
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
  return (await fetchStoresResultApi(categoryId, latitude, longitude)) ?? []
}

export async function fetchStoresResultApi(categoryId?: number, latitude?: number, longitude?: number): Promise<StoreItem[] | null> {
  const baseUrl: string = categoryId !== undefined && categoryId > 0
    ? `${API_CONFIG.ENDPOINTS['stores']}?categoryId=${categoryId}`
    : API_CONFIG.ENDPOINTS['stores']
  const url: string = appendCoordinates(baseUrl, latitude, longitude)
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(url)
  if (resp.code !== 200 || !Array.isArray(resp.data)) {
    return null
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
  return (await fetchStoreGoodsResultApi(storeId)) ?? []
}

export async function fetchStoreGoodsResultApi(storeId: number): Promise<GoodsItem[] | null> {
  const resp: ApiResponse<ServerGoods[]> = await get<ServerGoods[]>(`/api/stores/${storeId}/goods`)
  if (resp.code !== 200 || !Array.isArray(resp.data)) {
    return null
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

export async function fetchBundleApi(storeId: number, amount: number,
  showErrorToast: boolean = true): Promise<BundleInfo | null> {
  const resp: ApiResponse<ServerBundle> = await get<ServerBundle>(
    `/api/stores/${storeId}/bundle?amount=${amount}`, showErrorToast)
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

export async function fetchGoodsReviews(goodsId: number): Promise<Review[]> {
  const resp: ApiResponse<ServerReview[]> = await get<ServerReview[]>(`/api/goods/${goodsId}/reviews`)
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

export interface StoreSearchResult {
  success: boolean
  stores: StoreItem[]
}

/** 搜索结果显式携带请求状态，避免把请求失败误判为成功的空结果。 */
export async function searchStoresResultApi(keyword: string, latitude?: number,
  longitude?: number): Promise<StoreSearchResult> {
  const baseUrl: string = `${API_CONFIG.ENDPOINTS['search']}?keyword=${encodeURIComponent(keyword)}`
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>(appendCoordinates(baseUrl, latitude, longitude))
  if (resp.code !== 200 || !Array.isArray(resp.data)) {
    return { success: false, stores: [] }
  }
  return { success: true, stores: resp.data.map((s: ServerStore) => toStoreItem(s)) }
}

/** 保留原数组返回契约，供现有非交互调用继续使用。 */
export async function searchStoresApi(keyword: string, latitude?: number, longitude?: number): Promise<StoreItem[]> {
  const result: StoreSearchResult = await searchStoresResultApi(keyword, latitude, longitude)
  return result.stores
}

/** 查询第三方支付结果；服务端会向支付渠道查单并在确认成功后推进订单状态。 */
export async function queryPaymentApi(orderId: number): Promise<Order | null> {
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(`/api/orders/${orderId}/payment/query`, undefined, false)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return toOrder(resp.data)
}

/** 快速补货/清库存（演进项，见大纲 8.4）。 */
export async function updateGoodsStockApi(goodsId: number, stock: number): Promise<GoodsItem | null> {
  const req: StockRequest = { stock: stock }
  const resp: ApiResponse<ServerGoods> = await put<ServerGoods>(`/api/merchant/goods/${goodsId}/stock`, req)
  return resp.code === 200 && resp.data !== null ? toGoodsItem(resp.data) : null
}

// ==================== 用户中心（需登录） ====================

export async function fetchCouponsApi(showErrorToast: boolean = true): Promise<Coupon[] | null> {
  const resp: ApiResponse<ServerCoupon[]> = await get<ServerCoupon[]>(API_CONFIG.ENDPOINTS['coupons'], showErrorToast)
  if (resp.code !== 200 || !Array.isArray(resp.data)) {
    return null
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

export async function fetchAddressesApi(showErrorToast: boolean = true): Promise<Address[] | null> {
  const resp: ApiResponse<ServerAddress[]> = await get<ServerAddress[]>(
    API_CONFIG.ENDPOINTS['addresses'], showErrorToast)
  if (resp.code !== 200 || !Array.isArray(resp.data)) {
    return null
  }
  return resp.data.map((a: ServerAddress) => toAddress(a))
}

export async function addAddressApi(name: string, phone: string, detail: string, isDefault: boolean,
  latitude?: number, longitude?: number, mapAddress?: string, doorDetail?: string, tag?: string): Promise<boolean> {
  const req: AddressRequest = {
    name: name, phone: phone, detail: detail, isDefault: isDefault ? 1 : 0,
    latitude: latitude, longitude: longitude, mapAddress: mapAddress, doorDetail: doorDetail, tag: tag
  }
  const resp: ApiResponse<ServerAddress> = await post<ServerAddress>(API_CONFIG.ENDPOINTS['addresses'], req)
  return resp.code === 200
}

export async function addAddressAndFetchApi(name: string, phone: string, detail: string, isDefault: boolean,
  latitude?: number, longitude?: number, mapAddress?: string, doorDetail?: string,
  tag?: string): Promise<Address | null> {
  const req: AddressRequest = {
    name: name, phone: phone, detail: detail, isDefault: isDefault ? 1 : 0,
    latitude: latitude, longitude: longitude, mapAddress: mapAddress, doorDetail: doorDetail, tag: tag
  }
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

export async function updateAddressApi(addressId: number, name: string, phone: string, detail: string,
  isDefault: boolean, latitude?: number, longitude?: number, mapAddress?: string,
  doorDetail?: string, tag?: string): Promise<boolean> {
  const req: AddressRequest = {
    name: name, phone: phone, detail: detail, isDefault: isDefault ? 1 : 0,
    latitude: latitude, longitude: longitude, mapAddress: mapAddress, doorDetail: doorDetail, tag: tag
  }
  const resp: ApiResponse<ServerAddress> = await put<ServerAddress>(`/api/addresses/${addressId}`, req)
  return resp.code === 200
}

export async function setDefaultAddressApi(addressId: number): Promise<boolean> {
  const resp: ApiResponse<Object> = await put<Object>(`/api/addresses/${addressId}/default`, undefined)
  return resp.code === 200
}
