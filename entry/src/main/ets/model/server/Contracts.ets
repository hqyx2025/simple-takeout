

import { RefundRecord, AdminOperationLog, SetmealOrder } from '../Models'

import { AssistantReply } from '../../service/api/AssistantApi'

// ==================== 后端响应结构（与 server 端 record 对齐） ====================

export interface ServerStore {
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
  /** 配送半径（米，0=不限） */
  deliveryRadius?: number
  /** 当前用户定位下是否在配送范围内（服务端按坐标判定） */
  deliverable?: boolean
}

export interface ServerGoodsSpec {
  id: number
  goodsId: number
  name: string
  price: number
  stock: number
  sort: number
  status: number
}

export interface ServerGoods {
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

export interface ServerSpecialGoods {
  goods: ServerGoods
  storeName: string
  storeDistance: string
}

export interface ServerOrderItem {
  goodsId: number
  goodsName: string
  price: number
  quantity: number
  image: string
  specId?: number
  specName?: string
}

export interface ServerCartItem {
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

export interface ServerSeckill {
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

export interface ServerBundle {
  storeId: number
  storeName: string
  minOrder: number
  amount: number
  gap: number
  suggestions: ServerGoods[]
}

export interface ServerUploadResult {
  url: string
  size: number
}

export interface ServerAddressInfo {
  addressId: number
  name: string
  phone: string
  detail: string
}

export interface ServerOrder {
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
  deliveryType?: string
  readyTime?: string
  couponId?: number
  payDeadline?: string
  payDeadlineEpochMs?: number
  serverNowEpochMs?: number
  paymentChannel?: string
  outTradeNo?: string
  paymentUrl?: string
  appOrderInfo?: string
  paymentMode?: string
  paymentSandbox?: boolean
}

export interface ServerOrderPage {
  list: ServerOrder[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

export interface ServerMerchantStats {
  todayCount: number
  todayIncome: number
  todayCompleted?: number
  todayOrderCount?: number
  weekCount: number
  weekIncome: number
  weekCompleted?: number
  weekOrderCount?: number
  monthCount: number
  monthIncome: number
  monthOrderCount?: number
  totalCount?: number
  totalIncome?: number
  weekRevenue?: number[]
  todayStatus?: number[]
}

export interface ServerUser {
  id: number
  username: string
  avatar: string
  phone: string
  email?: string
  password: string
  role: number
  balance: number
  createTime: string
}

export interface ServerCoupon {
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

export interface ServerAddress {
  id: number
  userId: number
  name: string
  phone: string
  detail: string
  isDefault: number
  latitude?: number
  longitude?: number
}

/** 钱包银行卡：cardNoMasked 已是掩码卡号（服务端只存后四位，不下发完整卡号）。 */
export interface ServerBankCard {
  id: number
  bankName: string
  cardType: string
  cardNoMasked: string
  isDefault: number
  createTime: string
}

export interface ServerRevealedBankCard {
  cardNumber: string
}

export interface ServerReview {
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

export interface ServerRider {
  id: number
  userId: number
  name: string
  phone: string
  online: number
  totalOrders: number
  totalIncome: number
  status: number
  /** 配送半径（米）：默认 25 公里 */
  deliveryRadius?: number
  /** 接单位置（抢单圆心） */
  latitude?: number
  longitude?: number
  locationAddress?: string
  createTime: string
}

export interface RiderRadiusRequest {
  radiusMeters: number
}

export interface RiderLocationRequest {
  latitude: number
  longitude: number
  address: string
}

export interface ServerBanner {
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

export interface ServerAnnouncement {
  id: number
  title: string
  content: string
  status: number
  createTime: string
}

export interface ServerAdminEmployee {
  id: number
  username: string
  phone: string
  role: number
  status: number
  storeCount: number
  createTime: string
}

export interface ServerAdminProduct {
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

export interface ServerAdminProductPage {
  list: ServerAdminProduct[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

export interface ServerAdminUser {
  id: number
  username: string
  phone: string
  role: number
  status: number
  balance: number
  storeCount: number
  createTime: string
}

export interface ServerAdminUserPage {
  list: ServerAdminUser[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

export interface ServerRefundPage {
  list: RefundRecord[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

export interface ServerAdminOperationLogPage {
  list: AdminOperationLog[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

export interface ServerAdminHotGoods {
  goodsId: number
  goodsName: string
  storeId: number
  storeName: string
  sales: number
  price: number
  status: number
}

export interface ServerAdminStatistics {
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

export interface ServerAdminTrendPoint {
  date: string
  orderCount: number
  gmv: number
}

export interface LoginResult {
  token: string
  refreshToken?: string
  user: ServerUser
}

export interface LogoutRequest {
  refreshToken: string
  pushToken: string
}

// ==================== 请求 DTO ====================

export interface LoginRequest {
  phone: string
  password: string
  loginType?: string
}

export interface RegisterRequest {
  username: string
  phone: string
  email: string
  code: string
  password: string
  role: number
}

export interface ChangePasswordRequest {
  oldPassword: string
  newPassword: string
}

export interface ProfileUpdateRequest {
  username: string
  phone: string
  email: string
  currentPassword: string
}

export interface RechargeRequest {
  amount: number
}

export interface OrderItemRequest {
  goodsId: number
  goodsName: string
  price: number
  quantity: number
  image: string
  specId: number
  specName: string
}

export interface CreateOrderRequest {
  storeId: number
  items: OrderItemRequest[]
  addressId: number
  couponId: number
  remark: string
  checkoutGoodsIds: number[]
  expectTime: string
  idempotencyKey: string
  deliveryType: string
  setmeals: SetmealOrder[]
}

export interface CartItemRequest {
  goodsId: number
  specId: number
  quantity: number
}

export interface CartQuantityRequest {
  quantity: number
}

export interface ReviewRequest {
  goodsId: number
  rating: number
  content: string
  tags: string[]
  images: string[]
  anonymous: number
}

export interface ReplyRequest {
  reply: string
}

export interface RiderStatusRequest {
  online: number
}

export interface BannerRequest {
  title: string
  subtitle: string
  image: string
  color: string
  linkType: string
  linkValue: string
  sort: number
}

export interface AnnouncementRequest {
  title: string
  content: string
}

export interface AddressRequest {
  name: string
  phone: string
  detail: string
  isDefault: number
  latitude?: number
  longitude?: number
}

export interface CouponClaimRequest {
  storeId: number
  name: string
  threshold: number
  amount: number
}

export interface MerchantStoreRequest {
  name: string
  categoryId: number
  deliveryFee: number
  minOrder: number
  deliveryTime: string
  notice: string
  address: string
  latitude: number
  longitude: number
  /** 店铺照片（上传接口返回的相对地址 /uploads/...），未上传为空串 */
  image: string
  /** 配送半径（米，0=不限） */
  deliveryRadius: number
}

export interface MerchantStorePatch {
  name: string
  deliveryFee: number
  minOrder: number
  deliveryTime: string
  notice: string
  address: string
  latitude: number
  longitude: number
  status: number
  /** 店铺照片（null/缺省=不修改，本次统一传当前值） */
  image: string
  /** 配送半径（米）：-1=不修改；前端统一回传当前值，避免保存时被当成 0（不限）清掉 */
  deliveryRadius: number
}

export interface MerchantGoodsRequest {
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
export interface SpecInputRequest {
  id: number
  name: string
  price: number
  stock: number
}

export interface GoodsSpecsRequest {
  specs: SpecInputRequest[]
}

export interface RefundRequest {
  reasonType: string
  reason: string
}

export interface MerchantEmployeeBody {
  userId: number
  roleName: string
}

export interface AdminEmployeeCreateRequest {
  username: string
  phone: string
  password: string
}

export interface AdminEmployeeProfileRequest {
  username: string
  phone: string
}

export interface AdminEmployeeStatusRequest {
  status: number
}

export interface AdminStatusRequest {
  status: number
}

export interface MerchantCategoryRequest {
  name: string
  sort: number
}

export interface StockRequest {
  stock: number
}

export interface RefundRejectRequest {
  rejectReason: string
}

export interface EmailCodeApiResult { code: string; mock: boolean }

export interface EmailCodeResult { success: boolean; message: string; code?: string; mock?: boolean }

export interface ForgotPasswordRequest { phone: string; email: string; code: string; newPassword: string }

export interface ForgotPaymentPasswordRequest { phone: string; email: string; code: string; paymentPassword: string }

export interface EmailCodeRequest { phone: string; email: string; purpose: string; username: string }

export interface MerchantMarketingInput {
  type: string
  title: string
  discountRate: number
  reduceAmount: number
  threshold: number
  giftGoodsId: number
  startTime: string
  endTime: string
  status: number
}

export interface MerchantSeckillInput {
  goodsId: number
  price: number
  quota: number
  startTime: string
  endTime: string
  status: number
}

export interface StatusUpdateRequest {
  status: number
}

// ==================== 钱包：银行卡管理 ====================

export interface BankCardRequest {
  bankName: string
  cardType: string
  fullCardNumber: string
}

export interface RevealBankCardRequest { paymentPassword: string }

export interface SetPaymentPasswordRequest { loginPassword: string; paymentPassword: string }

export interface RevealBankCardResult { cardNumber: string | null; message: string }

export interface PaymentPasswordResult { success: boolean; message: string }

// ===================== AI 智能助手 =====================

export interface AssistantHistoryMessage {
  role: string
  content: string
}

export interface AssistantAction {
  label: string
  target: string
  value?: string
}

/** 助手提问请求体（后端 AskRequest 对应字段）。 */
export interface AssistantAskRequest {
  question: string
  history: AssistantHistoryMessage[]
}

/** 助手回答（后端 AssistantReply 对应字段）。 */
export interface ServerAssistantReply {
  answer: string
  suggestions: string[]
  actions?: AssistantAction[]
  source?: string
}
