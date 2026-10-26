import { get, post, put, ApiResponse } from '../HttpClient'

import { Order, OrderPageData, Rider } from '../../model/Models'

import { ServerOrder, ServerOrderPage, ServerRider, RiderRadiusRequest, RiderLocationRequest, RiderStatusRequest, AdminStatusRequest } from '../../model/server/Contracts'
import { toOrder, toOrderPageData, toRider } from '../../model/server/Converters'

// ==================== 骑手端（role=3） ====================

export async function fetchRiderProfileApi(showErrorToast: boolean = true): Promise<Rider | null> {
  const resp: ApiResponse<ServerRider> = await get<ServerRider>('/api/rider/profile', showErrorToast)
  if (resp.code !== 200 || resp.data === null) {
    return null
  }
  return toRider(resp.data)
}

/** 骑手设置配送半径（米）。 */
export async function updateRiderRadiusApi(radiusMeters: number): Promise<Rider | null> {
  const req: RiderRadiusRequest = { radiusMeters: radiusMeters }
  const resp: ApiResponse<ServerRider> = await put<ServerRider>('/api/rider/range/radius', req)
  return resp.code === 200 && resp.data !== null ? toRider(resp.data) : null
}

/** 骑手设置接单位置（抢单圆心）。 */
export async function updateRiderLocationApi(latitude: number, longitude: number,
  address: string): Promise<Rider | null> {
  const req: RiderLocationRequest = { latitude: latitude, longitude: longitude, address: address }
  const resp: ApiResponse<ServerRider> = await put<ServerRider>('/api/rider/range/location', req)
  return resp.code === 200 && resp.data !== null ? toRider(resp.data) : null
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
  return (await fetchRiderPoolResultApi()) ?? []
}

export async function fetchRiderPoolResultApi(showErrorToast: boolean = true): Promise<Order[] | null> {
  const resp: ApiResponse<ServerOrder[]> = await get<ServerOrder[]>('/api/rider/orders/pool', showErrorToast)
  if (resp.code !== 200 || !Array.isArray(resp.data)) {
    return null
  }
  return resp.data.map((o: ServerOrder) => toOrder(o))
}

export async function fetchRiderOrdersPageApi(page: number = 1, pageSize: number = 30): Promise<OrderPageData> {
  const resp: ApiResponse<ServerOrderPage> = await get<ServerOrderPage>(
    `/api/rider/orders/page?page=${page}&pageSize=${pageSize}`)
  return toOrderPageData(resp, page, pageSize)
}

/** 可区分“真实空列表”和“请求失败”，供状态操作后的权威对账使用。 */
export async function fetchRiderOrdersPageResultApi(page: number = 1, pageSize: number = 30,
  showErrorToast: boolean = true): Promise<OrderPageData | null> {
  const resp: ApiResponse<ServerOrderPage> = await get<ServerOrderPage>(
    `/api/rider/orders/page?page=${page}&pageSize=${pageSize}`, showErrorToast)
  if (resp.code !== 200 || resp.data === null || resp.data === undefined) {
    return null
  }
  return toOrderPageData(resp, page, pageSize)
}

export async function fetchRiderOrdersApi(): Promise<Order[]> {
  const resp: ApiResponse<ServerOrder[]> = await get<ServerOrder[]>('/api/rider/orders')
  if (resp.code !== 200 || resp.data === null) {
    return []
  }
  return resp.data.map((o: ServerOrder) => toOrder(o))
}

export async function grabOrderApi(orderId: number, showErrorToast: boolean = true): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(
    `/api/rider/orders/${orderId}/grab`, undefined, showErrorToast)
  return resp.code === 200
}

export async function pickupOrderApi(orderId: number, showErrorToast: boolean = true): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(
    `/api/rider/orders/${orderId}/pickup`, undefined, showErrorToast)
  return resp.code === 200
}

export async function deliverOrderApi(orderId: number, showErrorToast: boolean = true): Promise<boolean> {
  const resp: ApiResponse<ServerOrder> = await put<ServerOrder>(
    `/api/rider/orders/${orderId}/deliver`, undefined, showErrorToast)
  return resp.code === 200
}

export async function updateRiderStatusApi(riderId: number, status: number): Promise<boolean> {
  const req: AdminStatusRequest = { status: status }
  const resp: ApiResponse<ServerRider> = await put<ServerRider>(`/api/admin/riders/${riderId}/status`, req)
  return resp.code === 200
}
