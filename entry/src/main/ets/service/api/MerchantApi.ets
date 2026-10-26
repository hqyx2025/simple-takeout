import { get, post, put, del, ApiResponse } from '../HttpClient'

import { API_CONFIG } from '../../common/Constants'
import { StoreItem, GoodsItem, Category, Order, OrderPageData, Review, MarketingActivity, Setmeal, Employee, GoodsSpec, MerchantStatsAggregateData, MerchantSeckill } from '../../model/Models'

import { ServerStore, ServerGoods, ServerOrder, ServerOrderPage, ServerMerchantStats, ServerReview, MerchantStoreRequest, MerchantStorePatch, GoodsSpecsRequest, MerchantEmployeeBody, MerchantCategoryRequest, MerchantMarketingInput, MerchantSeckillInput, StatusUpdateRequest, MerchantRejectOrderRequest } from '../../model/server/Contracts'
import { toMerchantGoodsRequest, toSpecInputs, toStoreItem, toGoodsItem, toOrder, toOrderPageData, toReview } from '../../model/server/Converters'

/** 凑单提示：还差多少元起送 + 店内可凑单菜品。 */
export async function fetchStoreActivitiesApi(storeId: number): Promise<MarketingActivity[]> {
  const resp: ApiResponse<MarketingActivity[]> = await get<MarketingActivity[]>(`/api/stores/${storeId}/activities`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data
}

export async function fetchStoreSetmealsApi(storeId: number): Promise<Setmeal[]> {
  const resp: ApiResponse<Setmeal[]> = await get<Setmeal[]>(`/api/stores/${storeId}/setmeals`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data
}

export async function fetchMerchantReviewsApi(): Promise<Review[]> {
  const resp: ApiResponse<ServerReview[]> = await get<ServerReview[]>('/api/merchant/reviews')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerReview) => toReview(r))
}

// ==================== 商户端（需商户登录） ====================

export async function fetchMerchantOrdersApi(): Promise<Order[]> {
  const resp: ApiResponse<ServerOrder[]> = await get<ServerOrder[]>(API_CONFIG.ENDPOINTS['merchantOrders'])
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((o: ServerOrder) => toOrder(o))
}

export async function fetchMerchantOrdersPageApi(status?: number, page: number = 1,
  pageSize: number = 30): Promise<OrderPageData> {
  const statusQuery: string = status === undefined ? '' : `&status=${status}`
  const resp: ApiResponse<ServerOrderPage> = await get<ServerOrderPage>(
    `/api/merchant/orders/page?page=${page}&pageSize=${pageSize}${statusQuery}`)
  return toOrderPageData(resp, page, pageSize)
}

/** 商户统计聚合：服务端直接返回金额、计数及图表数据，避免拉取全部历史订单。 */
export async function fetchMerchantStatsApi(storeId: number = 0): Promise<MerchantStatsAggregateData | null> {
  const suffix: string = storeId > 0 ? `?storeId=${storeId}` : ''
  const resp: ApiResponse<ServerMerchantStats> = await get<ServerMerchantStats>(`/api/merchant/stats${suffix}`)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  const data: ServerMerchantStats = resp.data
  const weekRevenue: number[] = Array.isArray(data.weekRevenue)
    ? data.weekRevenue.map((value: number) => Number(value ?? 0)) : [0, 0, 0, 0, 0, 0, 0]
  const todayStatus: number[] = Array.isArray(data.todayStatus)
    ? data.todayStatus.map((value: number) => Number(value ?? 0)) : [0, 0, 0, 0, 0]
  return {
    today: {
      todayOrders: Number(data.todayOrderCount ?? data.todayCount ?? 0),
      todayRevenue: Number(data.todayIncome ?? 0),
      completedOrders: Number(data.todayCount ?? data.todayCompleted ?? 0),
      totalOrders: Number(data.totalCount ?? 0),
      totalRevenue: Number(data.totalIncome ?? 0)
    },
    week: {
      todayOrders: Number(data.weekOrderCount ?? data.weekCount ?? 0),
      todayRevenue: Number(data.weekIncome ?? 0),
      completedOrders: Number(data.weekCount ?? data.weekCompleted ?? 0),
      totalOrders: Number(data.totalCount ?? 0),
      totalRevenue: Number(data.totalIncome ?? 0)
    },
    weekRevenue: weekRevenue,
    todayStatus: todayStatus
  }
}

export async function fetchMerchantActivitiesApi(storeId: number): Promise<MarketingActivity[]> {
  const resp: ApiResponse<MarketingActivity[]> = await get<MarketingActivity[]>(`/api/merchant/activities?storeId=${storeId}`)
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function saveMerchantActivityApi(storeId: number, input: MerchantMarketingInput,
  activityId: number = 0): Promise<MarketingActivity | null> {
  const path: string = activityId > 0
    ? `/api/merchant/activities/${activityId}?storeId=${storeId}`
    : `/api/merchant/activities?storeId=${storeId}`
  const resp: ApiResponse<MarketingActivity> = activityId > 0
    ? await put<MarketingActivity>(path, input)
    : await post<MarketingActivity>(path, input)
  return resp.code === 200 && resp.data !== null ? resp.data : null
}

export async function updateMerchantActivityStatusApi(storeId: number, activityId: number, status: number): Promise<boolean> {
  const req: StatusUpdateRequest = { status: status }
  const resp: ApiResponse<MarketingActivity> = await put<MarketingActivity>(
    `/api/merchant/activities/${activityId}/status?storeId=${storeId}`, req)
  return resp.code === 200
}

export async function deleteMerchantActivityApi(storeId: number, activityId: number): Promise<boolean> {
  const resp: ApiResponse<null> = await del<null>(`/api/merchant/activities/${activityId}?storeId=${storeId}`)
  return resp.code === 200
}

export async function fetchMerchantSeckillsApi(storeId: number): Promise<MerchantSeckill[]> {
  const resp: ApiResponse<MerchantSeckill[]> = await get<MerchantSeckill[]>(`/api/merchant/seckills?storeId=${storeId}`)
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function saveMerchantSeckillApi(storeId: number, input: MerchantSeckillInput,
  seckillId: number = 0): Promise<MerchantSeckill | null> {
  const path: string = seckillId > 0
    ? `/api/merchant/seckills/${seckillId}?storeId=${storeId}`
    : `/api/merchant/seckills?storeId=${storeId}`
  const resp: ApiResponse<MerchantSeckill> = seckillId > 0
    ? await put<MerchantSeckill>(path, input)
    : await post<MerchantSeckill>(path, input)
  return resp.code === 200 && resp.data !== null ? resp.data : null
}

export async function updateMerchantSeckillStatusApi(storeId: number, seckillId: number, status: number): Promise<boolean> {
  const req: StatusUpdateRequest = { status: status }
  const resp: ApiResponse<MerchantSeckill> = await put<MerchantSeckill>(
    `/api/merchant/seckills/${seckillId}/status?storeId=${storeId}`, req)
  return resp.code === 200
}

export async function deleteMerchantSeckillApi(storeId: number, seckillId: number): Promise<boolean> {
  const resp: ApiResponse<null> = await del<null>(`/api/merchant/seckills/${seckillId}?storeId=${storeId}`)
  return resp.code === 200
}

/**
 * 商户订单流转：action = accept(接单 1→2) / ready(出餐完成，写 ready_time 进入骑手待取餐池)
 * / deliver(2→3) / complete(3→4)。出餐必须用 ready，否则订单不会进入骑手抢单池。
 */
export async function merchantActionApi(orderId: number, action: string): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(`/api/merchant/orders/${orderId}/${action}`, undefined)
  return resp.code === 200
}

/** 商家只能拒绝待接单订单；原因和缺货 SKU 由服务端校验并写入订单。 */
export async function rejectMerchantOrderApi(orderId: number,
  request: MerchantRejectOrderRequest): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(`/api/merchant/orders/${orderId}/reject`, request)
  return resp.code === 200
}

/** 商户门店员工（按店按角色）：列表。 */
export async function fetchMerchantEmployeesApi(storeId: number): Promise<Employee[]> {
  const resp: ApiResponse<Employee[]> = await get<Employee[]>(`/api/merchant/employees?storeId=${storeId}`)
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data
}

/** 商户门店员工：添加（userId + roleName）。 */
export async function addMerchantEmployeeApi(storeId: number, userId: number, roleName: string): Promise<boolean> {
  const req: MerchantEmployeeBody = { userId: userId, roleName: roleName }
  const resp: ApiResponse<Employee> = await post<Employee>(`/api/merchant/employees?storeId=${storeId}`, req)
  return resp.code === 200
}

/** 商户门店员工：移除。 */
export async function removeMerchantEmployeeApi(storeId: number, employeeId: number): Promise<boolean> {
  const resp: ApiResponse<null> = await del<null>(`/api/merchant/employees/${employeeId}?storeId=${storeId}`)
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
  latitude: number, longitude: number, image: string,
  deliveryRadius: number = 0): Promise<StoreItem | null> {
  const req: MerchantStoreRequest = {
    name: name, categoryId: categoryId, deliveryFee: deliveryFee, minOrder: minOrder,
    deliveryTime: deliveryTime, notice: notice, address: address, latitude: latitude, longitude: longitude,
    image: image, deliveryRadius: deliveryRadius
  }
  const resp: ApiResponse<ServerStore> = await post<ServerStore>(API_CONFIG.ENDPOINTS['merchantStores'], req)
  return resp.code === 200 && resp.data !== null ? toStoreItem(resp.data) : null
}

export async function updateMerchantStoreApi(storeId: number, name: string, deliveryFee: number,
  minOrder: number, deliveryTime: string, notice: string, address: string,
  latitude: number, longitude: number, image: string,
  deliveryRadius: number = -1): Promise<StoreItem | null> {
  const req: MerchantStorePatch = {
    name: name, deliveryFee: deliveryFee, minOrder: minOrder,
    deliveryTime: deliveryTime, notice: notice, address: address,
    latitude: latitude, longitude: longitude, status: -1, image: image, deliveryRadius: deliveryRadius
  }
  const resp: ApiResponse<ServerStore> = await put<ServerStore>(`/api/merchant/stores/${storeId}`, req)
  return resp.code === 200 && resp.data !== null ? toStoreItem(resp.data) : null
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
