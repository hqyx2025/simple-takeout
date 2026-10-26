import { get, post, put, del, ApiResponse } from '../HttpClient'

import { StoreItem, Rider, Banner, Announcement, RefundRecord, RefundPageData, AdminEmployee, AdminProduct, AdminProductPage, AdminUser, AdminUserPageData, AdminOperationLogPageData, AdminStatisticsData, AdminTrendPoint, AdminHotGoods, AdminDashboard, MarketingActivity, AdminSeckill } from '../../model/Models'

import { ServerStore, ServerOrder, ServerRider, ServerBanner, ServerAnnouncement, ServerAdminEmployee, ServerAdminProduct, ServerAdminProductPage, ServerAdminUser, ServerAdminUserPage, ServerRefundPage, ServerAdminOperationLogPage, ServerAdminHotGoods, ServerAdminStatistics, ServerAdminTrendPoint, AdminEmployeeCreateRequest, AdminEmployeeProfileRequest, AdminEmployeeStatusRequest, AdminStatusRequest, RefundRejectRequest, StatusUpdateRequest } from '../../model/server/Contracts'
import { toStoreItem, toRider, toBanner, toAnnouncement } from '../../model/server/Converters'

// ==================== 管理端：骑手管理 / 内容管理 ====================

export async function fetchAdminRidersApi(): Promise<Rider[]> {
  const resp: ApiResponse<ServerRider[]> = await get<ServerRider[]>('/api/admin/riders')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((r: ServerRider) => toRider(r))
}

export async function fetchAdminBannersApi(): Promise<Banner[]> {
  const resp: ApiResponse<ServerBanner[]> = await get<ServerBanner[]>('/api/admin/banners')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((b: ServerBanner) => toBanner(b))
}

export async function fetchAdminAnnouncementsApi(): Promise<Announcement[]> {
  const resp: ApiResponse<ServerAnnouncement[]> = await get<ServerAnnouncement[]>('/api/admin/announcements')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((a: ServerAnnouncement) => toAnnouncement(a))
}

/** 管理端：退款申请列表（status 为空返回全部）。 */
export async function fetchAdminRefundsApi(status?: string): Promise<RefundRecord[]> {
  const url: string = status !== undefined && status !== ''
    ? `/api/admin/refunds?status=${status}`
    : '/api/admin/refunds'
  const resp: ApiResponse<RefundRecord[]> = await get<RefundRecord[]>(url)
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function fetchAdminRefundsPageApi(status?: string, page: number = 1,
  pageSize: number = 50): Promise<RefundPageData | null> {
  const params: string[] = [`page=${page}`, `pageSize=${pageSize}`]
  if (status !== undefined && status !== '') {
    params.push(`status=${encodeURIComponent(status)}`)
  }
  const resp: ApiResponse<ServerRefundPage> = await get<ServerRefundPage>(`/api/admin/refunds/page?${params.join('&')}`)
  if (resp.code !== 200 || resp.data === null) {
    return null
  }
  return { list: resp.data.list, total: resp.data.total, page: resp.data.page,
    pageSize: resp.data.pageSize, hasMore: resp.data.hasMore }
}

export async function fetchAdminRefundDetailApi(refundId: number): Promise<RefundRecord | null> {
  const resp: ApiResponse<RefundRecord> = await get<RefundRecord>(`/api/admin/refunds/${refundId}`)
  return resp.code === 200 ? resp.data : null
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

export async function fetchAdminUsersPageApi(role?: number, status?: number, keyword?: string,
  page: number = 1, pageSize: number = 50): Promise<AdminUserPageData> {
  const params: string[] = [`page=${page}`, `pageSize=${pageSize}`]
  if (role !== undefined) {
    params.push(`userRole=${role}`)
  }
  if (status !== undefined) {
    params.push(`status=${status}`)
  }
  if (keyword !== undefined && keyword.trim() !== '') {
    params.push(`keyword=${encodeURIComponent(keyword.trim())}`)
  }
  const resp: ApiResponse<ServerAdminUserPage> = await get<ServerAdminUserPage>(`/api/admin/users/page?${params.join('&')}`)
  if (resp.code !== 200 || resp.data === null) {
    return { list: [], total: 0, page: page, pageSize: pageSize, hasMore: false }
  }
  const list: AdminUser[] = resp.data.list.map((item: ServerAdminUser): AdminUser => ({
    id: item.id, username: item.username, phone: item.phone, role: item.role,
    status: item.status, balance: item.balance, storeCount: item.storeCount, createTime: item.createTime
  }))
  return { list: list, total: resp.data.total, page: resp.data.page,
    pageSize: resp.data.pageSize, hasMore: resp.data.hasMore }
}

export async function fetchAdminOperationLogsApi(page: number = 1, pageSize: number = 50): Promise<AdminOperationLogPageData> {
  const resp: ApiResponse<ServerAdminOperationLogPage> = await get<ServerAdminOperationLogPage>(
    `/api/admin/audit-logs?page=${page}&pageSize=${pageSize}`)
  if (resp.code !== 200 || resp.data === null) {
    return { list: [], total: 0, page: page, pageSize: pageSize, hasMore: false }
  }
  return { list: resp.data.list, total: resp.data.total, page: resp.data.page,
    pageSize: resp.data.pageSize, hasMore: resp.data.hasMore }
}

export async function updateAdminUserStatusApi(id: number, status: number): Promise<boolean> {
  const req: AdminStatusRequest = { status: status }
  const resp: ApiResponse<Object> = await put<Object>(`/api/admin/users/${id}/status`, req)
  return resp.code === 200
}

export async function fetchAdminProductsApi(keyword?: string, status?: number, page: number = 1, pageSize: number = 50): Promise<AdminProductPage> {
  const params: string[] = []
  if (keyword !== undefined && keyword.trim() !== '') {
    params.push(`keyword=${encodeURIComponent(keyword.trim())}`)
  }
  if (status !== undefined) {
    params.push(`status=${status}`)
  }
  params.push(`page=${page}`)
  params.push(`pageSize=${pageSize}`)
  const url: string = params.length > 0 ? `/api/admin/products?${params.join('&')}` : '/api/admin/products'
  const resp: ApiResponse<ServerAdminProductPage> = await get<ServerAdminProductPage>(url)
  if (resp.code !== 200 || resp.data === null) {
    return { list: [], total: 0, page: page, pageSize: pageSize, hasMore: false }
  }
  const list: AdminProduct[] = resp.data.list.map((item: ServerAdminProduct) => {
    const product: AdminProduct = {
      id: item.id, storeId: item.storeId, storeName: item.storeName, name: item.name,
      description: item.description, price: item.price, originalPrice: item.originalPrice,
      image: item.image, categoryId: item.categoryId, merchantCategoryId: item.merchantCategoryId,
      stock: item.stock, sales: item.sales, rating: item.rating, tag: item.tag,
      status: item.status, createTime: item.createTime
    }
    return product
  })
  return { list: list, total: resp.data.total, page: resp.data.page, pageSize: resp.data.pageSize, hasMore: resp.data.hasMore }
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

export async function fetchAdminMarketingStoresApi(): Promise<StoreItem[]> {
  const resp: ApiResponse<ServerStore[]> = await get<ServerStore[]>('/api/admin/stores')
  return resp.code === 200 && resp.data !== null ? resp.data.map((store: ServerStore) => toStoreItem(store)) : []
}

export async function fetchAdminMarketingActivitiesApi(storeId: number = 0, status: number = -1): Promise<MarketingActivity[]> {
  const params: string[] = []
  if (storeId > 0) params.push(`storeId=${storeId}`)
  if (status >= 0) params.push(`status=${status}`)
  const query: string = params.length > 0 ? `?${params.join('&')}` : ''
  const resp: ApiResponse<MarketingActivity[]> = await get<MarketingActivity[]>(`/api/admin/marketing/activities${query}`)
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function updateAdminMarketingActivityStatusApi(id: number, status: number): Promise<boolean> {
  const req: StatusUpdateRequest = { status: status }
  const resp: ApiResponse<MarketingActivity> = await put<MarketingActivity>(`/api/admin/marketing/activities/${id}/status`, req)
  return resp.code === 200
}

export async function deleteAdminMarketingActivityApi(id: number): Promise<boolean> {
  const resp: ApiResponse<null> = await del<null>(`/api/admin/marketing/activities/${id}`)
  return resp.code === 200
}

export async function fetchAdminMarketingSeckillsApi(storeId: number = 0, status: number = -1): Promise<AdminSeckill[]> {
  const params: string[] = []
  if (storeId > 0) params.push(`storeId=${storeId}`)
  if (status >= 0) params.push(`status=${status}`)
  const query: string = params.length > 0 ? `?${params.join('&')}` : ''
  const resp: ApiResponse<AdminSeckill[]> = await get<AdminSeckill[]>(`/api/admin/marketing/seckills${query}`)
  return resp.code === 200 && resp.data !== null ? resp.data : []
}

export async function updateAdminMarketingSeckillStatusApi(id: number, status: number): Promise<boolean> {
  const req: StatusUpdateRequest = { status: status }
  const resp: ApiResponse<AdminSeckill> = await put<AdminSeckill>(`/api/admin/marketing/seckills/${id}/status`, req)
  return resp.code === 200
}

export async function deleteAdminMarketingSeckillApi(id: number): Promise<boolean> {
  const resp: ApiResponse<null> = await del<null>(`/api/admin/marketing/seckills/${id}`)
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

/** 数据大屏：一次性返回 指标 + 趋势 + 状态分布 + 店铺排行。 */
export async function fetchAdminDashboardApi(): Promise<AdminDashboard | null> {
  const resp: ApiResponse<AdminDashboard> = await get<AdminDashboard>('/api/admin/dashboard')
  if (resp.code !== 200 || resp.data === null) {
    return null
  }
  return resp.data
}
