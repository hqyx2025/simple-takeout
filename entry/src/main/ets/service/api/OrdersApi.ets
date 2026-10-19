import { get, post, put, del, getApiBaseUrl, uploadFile, ApiResponse } from '../HttpClient'

import { API_CONFIG } from '../../common/Constants'
import { Order, OrderPageData, CartItem, RefundRecord, SetmealOrder, UploadResult } from '../../model/Models'
import { logWarn } from '../AppLogger'
import { ServerCartItem, ServerOrder, ServerOrderPage, ServerReview, OrderItemRequest, CreateOrderRequest, CartItemRequest, CartQuantityRequest, ReviewRequest, RefundRequest } from '../../model/server/Contracts'
import { toCartItem, toOrder, toOrderPageData } from '../../model/server/Converters'

/** 图文评价图片上传：返回相对地址（需拼接 API_CONFIG.BASE_URL 展示）。 */
export async function uploadImageApi(fileUri: string, showErrorToast: boolean = true): Promise<UploadResult | null> {
  const url: string = getApiBaseUrl() + API_CONFIG.ENDPOINTS['upload']
  const result: UploadResult | null = await uploadFile(url, fileUri, showErrorToast)
  return result
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
export async function createOrderApi(storeId: number, cartItems: CartItem[], addressId: number, couponId: number, remark: string, checkoutGoodsIds: number[], expectTime: string, idempotencyKey: string, deliveryType: string = 'DELIVERY', setmeals: SetmealOrder[] = []): Promise<Order | null> {
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
    expectTime: expectTime,
    idempotencyKey: idempotencyKey,
    deliveryType: deliveryType,
    setmeals: setmeals
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

export async function fetchUserOrdersPageApi(status?: number, page: number = 1,
  pageSize: number = 30): Promise<OrderPageData> {
  const statusQuery: string = status === undefined ? '' : `&status=${status}`
  const resp: ApiResponse<ServerOrderPage> = await get<ServerOrderPage>(
    `/api/orders/page?page=${page}&pageSize=${pageSize}${statusQuery}`)
  return toOrderPageData(resp, page, pageSize)
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

/** 按明确选择的渠道支付：余额即时扣款，第三方返回待扫码支付信息。 */
export async function payOrderApi(orderId: number, channel: string, mode: string = 'QR'): Promise<Order | null> {
  const resp: ApiResponse<ServerOrder> = await post<ServerOrder>(
    `/api/orders/${orderId}/pay?channel=${channel}&mode=${mode}`, undefined, false)
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

// ==================== 退款（演进项，见大纲 7.11/9.7） ====================

/** 用户申请退款：订单 status=4 且 escrow=0 且未评价时可用。 */
export async function applyRefundApi(orderId: number, reasonType: string, reason: string): Promise<RefundRecord | null> {
  const req: RefundRequest = { reasonType: reasonType, reason: reason }
  const resp: ApiResponse<RefundRecord> = await post<RefundRecord>(`/api/orders/${orderId}/refund`, req)
  return resp.code === 200 && resp.data !== null ? resp.data : null
}
