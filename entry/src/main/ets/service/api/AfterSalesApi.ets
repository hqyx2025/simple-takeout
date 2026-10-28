import { ApiResponse, get, post, put } from '../HttpClient'
import { DeliveryIssue, RefundRecord, UserRole } from '../../model/Models'

export interface DeliveryIssuePageData {
  list: DeliveryIssue[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

export interface FulfillmentSettings { mode: string }
export interface IssueRequest { type: string; note: string; idempotencyKey: string }
export interface ResolveIssueRequest { action: string; note: string }
export interface RefundEvidenceRequest { reason?: string; response?: string; evidenceImages: string[] }

function issuePath(orderId: number, role: UserRole): string {
  const prefix: string = role === UserRole.MERCHANT ? '/api/merchant/orders'
    : role === UserRole.RIDER ? '/api/rider/orders' : '/api/orders'
  return prefix + '/' + orderId.toString() + '/issues'
}

export async function fetchDeliveryIssuesApi(orderId: number, role: UserRole): Promise<DeliveryIssue[] | null> {
  const resp: ApiResponse<DeliveryIssue[]> = await get<DeliveryIssue[]>(issuePath(orderId, role), false)
  return resp.code === 200 && Array.isArray(resp.data) ? resp.data : null
}

export async function reportDeliveryIssueApi(orderId: number, role: UserRole, request: IssueRequest): Promise<boolean> {
  const resp: ApiResponse<DeliveryIssue> = await post<DeliveryIssue>(issuePath(orderId, role), request, false)
  return resp.code === 200
}

export async function fetchAdminDeliveryIssuesApi(page: number = 1): Promise<DeliveryIssuePageData | null> {
  const resp: ApiResponse<DeliveryIssuePageData> = await get<DeliveryIssuePageData>(
    '/api/admin/delivery-issues?status=OPEN&page=' + page.toString() + '&pageSize=30', false)
  return resp.code === 200 && resp.data !== null && resp.data !== undefined && Array.isArray(resp.data.list) ? resp.data : null
}

export async function resolveDeliveryIssueApi(id: number, request: ResolveIssueRequest): Promise<boolean> {
  const resp: ApiResponse<DeliveryIssue> = await post<DeliveryIssue>('/api/admin/delivery-issues/' + id.toString() + '/resolve', request, false)
  return resp.code === 200
}

export async function fetchFulfillmentApi(storeId: number): Promise<FulfillmentSettings | null> {
  const resp: ApiResponse<FulfillmentSettings> = await get<FulfillmentSettings>('/api/merchant/stores/' + storeId.toString() + '/fulfillment', false)
  return resp.code === 200 && resp.data !== undefined ? resp.data : null
}

export async function saveFulfillmentApi(storeId: number, mode: string): Promise<boolean> {
  const request: FulfillmentSettings = { mode: mode }
  const resp: ApiResponse<FulfillmentSettings> = await put<FulfillmentSettings>('/api/merchant/stores/' + storeId.toString() + '/fulfillment', request, false)
  return resp.code === 200
}

export async function fetchMerchantOrderRefundsApi(orderId: number): Promise<RefundRecord[] | null> {
  const resp: ApiResponse<RefundRecord[]> = await get<RefundRecord[]>('/api/merchant/orders/' + orderId.toString() + '/refunds', false)
  return resp.code === 200 && Array.isArray(resp.data) ? resp.data : null
}

export async function submitMerchantEvidenceApi(refundId: number, request: RefundEvidenceRequest): Promise<boolean> {
  const resp: ApiResponse<RefundRecord> = await post<RefundRecord>('/api/after-sales/' + refundId.toString() + '/merchant-evidence', request, false)
  return resp.code === 200
}

export async function appealRefundApi(orderId: number, refundId: number, request: RefundEvidenceRequest): Promise<RefundRecord | null> {
  const resp: ApiResponse<RefundRecord> = await post<RefundRecord>('/api/orders/' + orderId.toString() + '/refunds/' + refundId.toString() + '/appeal', request, false)
  return resp.code === 200 && resp.data !== undefined ? resp.data : null
}
