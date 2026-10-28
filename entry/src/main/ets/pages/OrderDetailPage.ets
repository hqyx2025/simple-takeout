import { AppButtonStyle, AppCardStyle, AppTextAreaStyle } from '../common/theme/AppTheme'
/**
 * 订单详情页
 * 展示订单状态时间轴、店铺与商品、配送信息、金额明细、订单信息
 * 根据订单状态显示对应操作按钮（取消订单 / 确认收货 / 再来一单 / 去评价）
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor } from '../common/Constants'
import { Order, CartItem, DeliveryStep, RefundRecord, User, createEmptyUser } from '../model/Models'
import { cancelOrderRemote, confirmOrderRemote, applyRefundRemote, addCartItemRemote, fetchOrderDetailRemote, getLastRemoteErrorMessage, syncCartRemote, payOrderRemote, queryPaymentRemote } from '../service/AppStorageManager'
import { fetchOrderRefundsApi } from '../service/ApiService'
import { EvidenceImages } from '../components/EvidenceImages'
import { appealRefundApi, RefundEvidenceRequest } from '../service/api/AfterSalesApi'
import { canOrderAction } from '../service/OrderStatus'
import { OrderStatusTimeline } from '../components/OrderStatusTimeline'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { logInfo } from '../service/AppLogger'
import { bundleManager } from '@kit.AbilityKit'
import { getAuthSessionEpoch, getServerClockOffsetMs, getApiBaseUrl } from '../service/HttpClient'

class RefundReasonOption {
  code: string
  label: string
  constructor(code: string, label: string) {
    this.code = code
    this.label = label
  }
}

class PayChannelOption {
  code: string
  label: string
  constructor(code: string, label: string) {
    this.code = code
    this.label = label
  }
}

@Entry
@Component
export struct OrderDetailPage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
  }

  @StorageLink('user') @Watch('onOwnerChanged') sessionUser: User = createEmptyUser()
  private detailOwner: number = 0
  private detailRole: number = -1
  @State order: Order | null = null
  @StorageLink('isLoggedIn') @Watch('onLoginChanged') loggedIn: boolean = false
  @StorageLink('appForeground') @Watch('onAppForegroundChanged') appForeground: boolean = true
  @State showCancelDialog: boolean = false
  @State showConfirmDialog: boolean = false
  @State showRefundDialog: boolean = false
  @State refundReason: string = ''
  @State refundAmount: string = ''
  @State refundImages: string[] = []
  @State refundUploading: boolean = false
  @State refundAppealId: number = 0
  @State refundPayloadLocked: boolean = false
  @State refundReasonType: string = ''
  @State refundRecords: RefundRecord[] = []
  @State refundHistoryLoading: boolean = false
  @State refundHistoryLoaded: boolean = false
  @State refundHistoryError: string = ''
  @State refundOrderError: string = ''
  @State refundPreventsSettlement: boolean = false
  @State refundSubmitting: boolean = false
  @State refundSubmitError: string = ''
  private refundSubmitKey: string = ''
  private refundHistoryVersion: number = 0
  private refundOrderVersion: number = 0
  private refundDialogVersion: number = 0
  private refundReasonOptions: RefundReasonOption[] = [
    new RefundReasonOption('NOT_RECEIVED', '未收到餐'),
    new RefundReasonOption('QUALITY_ISSUE', '餐品质量问题'),
    new RefundReasonOption('WRONG_ITEM', '商品不符'),
    new RefundReasonOption('DONOT_WANT', '不想要了'),
    new RefundReasonOption('OTHER', '其他')
  ]
  @State payChannel: string = 'BALANCE'
  @State balancePaymentPassword: string = ''
  private payChannelOptions: PayChannelOption[] = [
    new PayChannelOption('BALANCE', '余额支付'),
    new PayChannelOption('ALIPAY', '支付宝'),
    new PayChannelOption('WECHAT', '微信支付')
  ]
  orderId: number = 0
  // 待付款倒计时（秒）；>0 时展示支付倒计时，归零后提示已自动取消
  @State payRemainSeconds: number = 0
  @State paying: boolean = false
  @State paymentUrl: string = ''
  @State showPaymentCode: boolean = false
  @State paymentMessage: string = ''
  @State paymentChecking: boolean = false
  @State manualPaymentChecking: boolean = false
  @State paymentAttempted: boolean = false
  private payTimer: number = -1
  private paymentQueryTimer: number = -1
  private pageActive: boolean = false
  private paymentAdvanced: boolean = false
  private paymentScroller: Scroller = new Scroller()
  // 服务端返回当前时间，倒计时用偏移后的时间，避免模拟器系统时钟不准。
  private serverClockOffsetMs: number = 0
  @State reorderAdding: boolean = false
  @State reorderFailedItems: CartItem[] = []
  @State reorderHasUncertainItems: boolean = false
  private reorderRequestVersion: number = 0

  private cartQuantity(item: CartItem): number {
    const cart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
    const matched: CartItem | undefined = cart.find((cartItem: CartItem) =>
      cartItem.storeId === item.storeId && cartItem.goods.id === item.goods.id &&
      (cartItem.specId ?? 0) === (item.specId ?? 0))
    return matched === undefined ? 0 : matched.quantity
  }

  private resetReorderState(): void {
    this.reorderRequestVersion += 1
    this.reorderAdding = false
    this.reorderFailedItems = []
    this.reorderHasUncertainItems = false
  }

  private async addAgain(): Promise<void> {
    if (this.order === null || this.reorderAdding) {
      return
    }
    if (this.reorderHasUncertainItems && this.reorderFailedItems.length === 0) {
      promptAction.showToast({ message: '请先到购物车确认商品数量', duration: 2000 })
      return
    }
    const pendingItems: CartItem[] = this.reorderFailedItems.length > 0
      ? this.reorderFailedItems.slice() : this.order.items.slice()
    if (pendingItems.length === 0) {
      promptAction.showToast({ message: '订单中没有可再次加入的商品', duration: 1800 })
      return
    }
    const reorderOrderId: number = this.order.id
    const requestVersion: number = this.reorderRequestVersion + 1
    this.reorderRequestVersion = requestVersion
    this.reorderAdding = true
    const failedItems: CartItem[] = []
    let succeededCount: number = 0
    let failedCount: number = 0
    let uncertainCount: number = 0
    let hasUncertainItems: boolean = this.reorderHasUncertainItems
    try {
      if (!await syncCartRemote(false)) {
        promptAction.showToast({ message: '购物车同步失败，请检查网络后重试', duration: 2200 })
        return
      }
      if (requestVersion !== this.reorderRequestVersion || this.orderId !== reorderOrderId) {
        return
      }
      for (let i = 0; i < pendingItems.length; i++) {
        const item: CartItem = pendingItems[i]
        const beforeQuantity: number = this.cartQuantity(item)
        let ok: boolean = false
        try {
          ok = await addCartItemRemote(item, false)
        } catch (_) {
          ok = false
        }
        if (requestVersion !== this.reorderRequestVersion || this.orderId !== reorderOrderId) {
          return
        }
        if (!ok) {
          const reconciled: boolean = await syncCartRemote(false)
          if (requestVersion !== this.reorderRequestVersion || this.orderId !== reorderOrderId) {
            return
          }
          if (!reconciled) {
            uncertainCount += item.quantity
            hasUncertainItems = true
            continue
          }
          const afterQuantity: number = this.cartQuantity(item)
          ok = afterQuantity >= beforeQuantity + item.quantity
          if (!ok && afterQuantity !== beforeQuantity) {
            uncertainCount += item.quantity
            hasUncertainItems = true
            continue
          }
        }
        if (ok) {
          succeededCount += item.quantity
        } else {
          failedItems.push(item)
          failedCount += item.quantity
        }
      }
      this.reorderFailedItems = failedItems
      this.reorderHasUncertainItems = hasUncertainItems
      let message: string = ''
      if (hasUncertainItems) {
        if (succeededCount > 0) {
          message = `已确认加入 ${succeededCount} 件；`
        }
        if (failedCount > 0) {
          message += `${failedCount} 件未加入；`
        }
        message += uncertainCount > 0
          ? `${uncertainCount} 件结果待确认，请稍后查看购物车`
          : '此前仍有商品结果待确认，请查看购物车'
      } else if (failedCount > 0 && succeededCount > 0) {
        message = `已加入 ${succeededCount} 件，${failedCount} 件未加入；可只重试失败商品`
      } else if (failedCount > 0) {
        message = `${failedCount} 件商品未加入，请检查商品状态后重试`
      } else {
        message = `已加入 ${succeededCount} 件商品，可在购物车查看`
      }
      promptAction.showToast({ message: message, duration: 2400 })
    } finally {
      if (requestVersion === this.reorderRequestVersion) {
        this.reorderAdding = false
      }
    }
  }

  async aboutToAppear(): Promise<void> {
    this.pageActive = true
    this.detailOwner = this.sessionUser.id
    this.detailRole = this.sessionUser.role
    const routerOrderId: number = AppStorage.get<number>('currentOrderId') || 0
    if (routerOrderId !== this.orderId) {
      this.resetReorderState()
      this.clearRefundSession()
      this.orderId = routerOrderId
    }
    if (!this.loggedIn) {
      this.order = null
      logInfo('Page', '进入订单详情页：当前未登录，不读取订单数据')
      return
    }
    if (this.orderId <= 0) {
      this.order = null
      logInfo('Page', '进入订单详情页：缺少有效订单 ID')
      return
    }
    const sessionEpoch: number = getAuthSessionEpoch()
    const requestedOrderId: number = this.orderId
    const requestVersion: number = ++this.refundOrderVersion
    const remoteOrder: Order | null = await fetchOrderDetailRemote(requestedOrderId)
    if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch() ||
      requestedOrderId !== this.orderId || requestVersion !== this.refundOrderVersion) { return }
    this.order = remoteOrder
    this.refundOrderError = ''
    if (remoteOrder !== null) { this.loadRefundHistory() }
    this.syncServerClock(remoteOrder)
    if (remoteOrder !== null && remoteOrder.status === 0) {
      const storedChannel: string = remoteOrder.paymentChannel ?? ''
      this.payChannel = storedChannel === 'ALIPAY' || storedChannel === 'BALANCE'
        ? storedChannel : 'BALANCE'
      this.paymentUrl = remoteOrder.paymentUrl ?? ''
      this.paymentAttempted = storedChannel === 'ALIPAY'
      this.paymentMessage = storedChannel !== 'ALIPAY' ? '' : remoteOrder.paymentSandbox === true
        ? '当前使用支付宝沙箱，可通过本机支付宝 SDK 支付或使用沙箱钱包扫码'
        : '支付已准备，可使用本机支付宝或选择其他设备扫码'
    } else {
      this.paymentUrl = ''
    }
    logInfo('Page', `进入订单详情页 OrderDetailPage orderId=${this.orderId} 状态=${this.order !== null ? this.order.status : -1}`)
    // 待付款状态启动支付倒计时（超时后端会自动取消订单）
    if (this.order !== null && this.order.status === 0) {
      this.startPayCountdown()
      this.startPaymentPolling()
    }
  }

  aboutToDisappear() {
    this.balancePaymentPassword = ''
    this.pageActive = false
    this.stopPayCountdown()
    this.stopPaymentPolling()
    this.pauseRefundRequests()
  }

  onPageShow(): void {
    this.pageActive = true
    if (this.order !== null && (this.order.status === 4 || this.order.status === 6 || this.refundRecords.length > 0)) {
      this.refreshRefundProgress()
    }
    if (this.order !== null && this.order.status === 0) {
      this.startPayCountdown()
      this.startPaymentPolling()
      if (this.paymentAttempted || this.hasPendingPayment()) { this.refreshPaymentStatus(false) }
    }
  }

  onPageHide(): void {
    this.pageActive = false
    this.stopPaymentPolling()
    this.stopPayCountdown()
    this.pauseRefundRequests()
  }

  private onAppForegroundChanged(): void {
    if (!this.appForeground) {
      this.stopPaymentPolling()
      return
    }
    if (this.pageActive && this.order !== null && this.order.status === 0) {
      this.startPayCountdown()
      this.startPaymentPolling()
      if (this.paymentAttempted || this.hasPendingPayment()) { this.refreshPaymentStatus(false) }
    }
    if (this.pageActive && this.order !== null && (this.order.status === 4 || this.order.status === 6)) {
      this.refreshRefundProgress()
    }
  }

  private onOwnerChanged(): void {
    if (this.detailOwner <= 0 || (this.detailOwner === this.sessionUser.id && this.detailRole === this.sessionUser.role)) { return }
    this.pageActive = false
    this.resetReorderState()
    this.clearPaymentSession()
    this.clearRefundSession()
    this.order = null
    this.orderId = 0
  }

  private onLoginChanged(): void {
    if (this.loggedIn) { return }
    this.resetReorderState()
    this.clearPaymentSession()
    this.clearRefundSession()
    this.order = null
  }

  private pauseRefundRequests(): void {
    this.refundHistoryVersion += 1
    this.refundOrderVersion += 1
    this.refundDialogVersion += 1
    this.refundHistoryLoading = false
    this.refundSubmitting = false
    this.refundUploading = false
    this.showRefundDialog = false
  }

  private clearRefundSession(): void {
    this.pauseRefundRequests()
    this.refundRecords = []
    this.refundHistoryLoaded = false
    this.refundHistoryError = ''
    this.refundOrderError = ''
    this.refundPreventsSettlement = false
    this.refundSubmitError = ''
    this.refundSubmitKey = ''
    this.refundReason = ''
    this.refundReasonType = ''
    this.refundImages = []
    this.refundUploading = false
    this.refundAppealId = 0
    this.refundPayloadLocked = false
  }

  private async loadRefundHistory(): Promise<void> {
    if (!this.pageActive || !this.loggedIn || this.order === null) { return }
    const requestedOrderId: number = this.order.id
    const sessionEpoch: number = getAuthSessionEpoch()
    const requestVersion: number = ++this.refundHistoryVersion
    this.refundHistoryLoading = true
    const records: RefundRecord[] | null = await fetchOrderRefundsApi(requestedOrderId)
    if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch() ||
      requestVersion !== this.refundHistoryVersion || requestedOrderId !== this.orderId) { return }
    this.refundHistoryLoading = false
    if (records === null) {
      this.refundHistoryError = this.refundHistoryLoaded
        ? '退款进度更新失败，以下为上次读取的记录。请重试。'
        : '退款记录未能加载，请检查网络后重试。'
      return
    }
    this.refundRecords = records.slice().sort((a: RefundRecord, b: RefundRecord) => b.id - a.id)
    this.refundPreventsSettlement = records.some((record: RefundRecord) =>
      record.status === 'PENDING' || record.status === 'APPROVED')
    this.refundHistoryLoaded = true
    this.refundHistoryError = ''
  }

  private refreshRefundProgress(): void {
    this.loadRefundHistory()
    this.refreshRefundOrder()
  }

  private async refreshRefundOrder(): Promise<void> {
    if (!this.pageActive || !this.loggedIn || this.order === null) { return }
    const requestedOrderId: number = this.order.id
    const sessionEpoch: number = getAuthSessionEpoch()
    const requestVersion: number = ++this.refundOrderVersion
    const latest: Order | null = await fetchOrderDetailRemote(requestedOrderId, false)
    if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch() ||
      requestVersion !== this.refundOrderVersion || requestedOrderId !== this.orderId) { return }
    if (latest !== null) {
      this.order = latest
      this.syncServerClock(latest)
      this.refundOrderError = ''
    } else {
      this.refundOrderError = '订单状态更新失败，请刷新进度后再进行订单操作。'
    }
  }

  private startPaymentPolling(): void {
    this.stopPaymentPolling()
    if (!this.pageActive || !this.appForeground || !this.loggedIn || this.order === null ||
      !this.hasPendingPayment() || this.computePayRemain() <= 0) { return }
    this.paymentQueryTimer = setInterval(() => { this.refreshPaymentStatus(false) }, 3000)
  }

  private stopPaymentPolling(): void {
    if (this.paymentQueryTimer >= 0) {
      clearInterval(this.paymentQueryTimer)
      this.paymentQueryTimer = -1
    }
  }

  private hasPendingPayment(): boolean {
    return this.order !== null && this.order.status === 0 && this.order.paymentChannel === 'ALIPAY' &&
      (this.paymentUrl !== '' || (this.order.outTradeNo ?? '') !== '')
  }

  // ============ 待付款支付倒计时 ============

  /** 依据后端返回的 payDeadline 计算剩余秒数并每秒刷新。 */
  private startPayCountdown(): void {
    this.stopPayCountdown()
    this.payRemainSeconds = this.computePayRemain()
    this.payTimer = setInterval(() => {
      this.payRemainSeconds = this.computePayRemain()
      if (this.payRemainSeconds <= 0) {
        this.stopPayCountdown()
        this.stopPaymentPolling()
        // 超时后由后端定时任务取消，这里刷新一次拿到最新状态并提示用户
        this.refreshAfterTimeout()
      }
    }, 1000)
  }

  private stopPayCountdown(): void {
    if (this.payTimer >= 0) {
      clearInterval(this.payTimer)
      this.payTimer = -1
    }
  }

  private computePayRemain(): number {
    if (this.order === null || this.order.status !== 0) {
      return 0
    }
    const epochMs: number = this.order.payDeadlineEpochMs ?? 0
    if (epochMs <= 0) {
      return 0
    }
    const serverNowMs: number = Date.now() + this.serverClockOffsetMs
    return Math.max(Math.floor((epochMs - serverNowMs) / 1000), 0)
  }

  private syncServerClock(order: Order | null): void {
    const serverNowMs: number = order?.serverNowEpochMs ?? 0
    this.serverClockOffsetMs = serverNowMs > 0 ? serverNowMs - Date.now() : getServerClockOffsetMs()
  }

  /** mm:ss 倒计时文案。 */
  private payCountdownText(): string {
    const minute: number = Math.floor(this.payRemainSeconds / 60)
    const second: number = this.payRemainSeconds % 60
    const mm: string = minute < 10 ? `0${minute}` : `${minute}`
    const ss: string = second < 10 ? `0${second}` : `${second}`
    return `${mm}:${ss}`
  }

  private async refreshAfterTimeout(): Promise<void> {
    const sessionEpoch: number = getAuthSessionEpoch()
    const latest: Order | null = await fetchOrderDetailRemote(this.orderId)
    if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch()) { return }
    this.order = latest
    this.syncServerClock(latest)
    if (latest === null || latest.status !== 0) { this.clearPaymentSession() }
    if (latest !== null && latest.status === 5) {
      promptAction.showToast({ message: '超过支付时限，订单已自动取消', duration: 3000 })
    }
  }

  private canDispatchOrder(action: string, legacy: boolean): boolean {
    return this.pageActive && this.loggedIn && this.order !== null
      && this.detailOwner === this.sessionUser.id && this.detailRole === this.sessionUser.role
      && canOrderAction(this.order, action, legacy)
  }

  /** 待付款订单支付：成功后刷新订单并提示。 */
  private async payNow(): Promise<void> {
    if (!this.canDispatchOrder('PAY', this.order?.status === 0)) { return }
    if (!this.loggedIn || this.order === null || this.order.status !== 0 || this.paying || this.paymentChecking) {
      return
    }
    if (this.payChannel === 'ALIPAY') {
      this.paymentAttempted = true
      this.showPaymentCode = false
      this.paymentScroller.scrollTo({ xOffset: 0, yOffset: 0 })
      try {
        if (!bundleManager.canOpenLink('alipays://')) {
          this.paymentMessage = '未检测到可用的支付宝，请选择其他设备扫码支付'
          return
        }
      } catch (_) {
        this.paymentMessage = '暂时无法检测支付宝，可选择其他设备扫码支付'
        return
      }
      const signed: Order | null = await this.preparePayment('APP')
      if (signed === null || signed.status !== 0) { return }
      if ((signed.appOrderInfo ?? '') === '') {
        this.paymentMessage = '暂时无法打开支付宝，可选择其他设备扫码支付'
        return
      }
      this.startPaymentPolling()
      this.launchAlipay(signed.appOrderInfo ?? '')
      return
    }
    await this.preparePayment('QR')
  }

  private async preparePayment(mode: string): Promise<Order | null> {
    if (!this.canDispatchOrder('PAY', this.order?.status === 0)) { return null }
    if (this.order === null) { return null }
    if (this.payChannel === 'BALANCE' && !/^[0-9]{6}$/.test(this.balancePaymentPassword)) {
      promptAction.showToast({ message: '请输入 6 位支付密码；未设置请前往账号安全', duration: 3000 })
      return null
    }
    const paymentPassword: string = this.balancePaymentPassword
    this.balancePaymentPassword = ''
    this.paying = true
    const sessionEpoch: number = getAuthSessionEpoch()
    const paid: Order | null = await payOrderRemote(this.order.id, this.payChannel, mode, paymentPassword)
    this.paying = false
    if (!this.pageActive || !this.appForeground || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch()) { return null }
    if (paid === null) {
      const errorMessage: string = getLastRemoteErrorMessage()
      if (this.payChannel === 'ALIPAY') {
        this.paymentMessage = errorMessage === '' ? '支付暂不可用，请稍后重试或选择其他设备扫码支付' : errorMessage
      } else {
        promptAction.showToast({ message: errorMessage === '' ? '支付失败，请稍后重试' : errorMessage, duration: 3000 })
      }
      return null
    }
    this.order = paid
    this.syncServerClock(paid)
    if (paid.status === 0) {
      this.paymentUrl = paid.paymentUrl ?? ''
      this.startPaymentPolling()
      return paid
    }
    this.clearPaymentSession()
    if (paid.status < 1 || paid.status > 4) {
      promptAction.showToast({ message: '订单状态已变化，请查看最新详情', duration: 2500 })
      return paid
    }
    promptAction.showToast({ message: `支付成功，已支付 ¥${paid.payAmount.toFixed(2)}`, duration: 2500 })
    this.advanceAfterPayment(paid)
    return paid
  }

  /** 通过支付宝官方 Harmony SDK 拉起支付，最终状态仅由服务端查单确认。 */
  private async launchAlipay(orderInfo: string): Promise<void> {
    const sessionEpoch: number = getAuthSessionEpoch()
    this.paymentMessage = '正在打开支付宝，完成支付后将自动更新订单'
    try {
      // 禁止 SDK 自动打开 H5；无法唤端时按用户选择进入其他设备扫码。
      const cashier = await import('@cashier_alipay/cashiersdk')
      const result: Map<string, string> = await new cashier.Pay().payWithNav(orderInfo, true, undefined, undefined, false)
      if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch() ||
        this.order === null || this.order.status !== 0) { return }
      const resultStatus: string = result.get('resultStatus') ?? ''
      this.paymentMessage = resultStatus === '9000' || resultStatus === '8000'
        ? '正在确认支付结果，确认后将自动更新订单'
        : '支付尚未完成，可重新打开支付宝或选择其他设备扫码支付'
      this.refreshPaymentStatus(false)
    } catch (_) {
      if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch()) { return }
      this.paymentMessage = '暂时无法打开支付宝，可重试或选择其他设备扫码支付'
    }
  }

  private async showOtherDevicePayment(): Promise<void> {
    if (!this.loggedIn || this.order === null || this.order.status !== 0 || this.paying || this.paymentChecking) { return }
    if (this.paymentUrl === '' || this.order.paymentMode === 'APP') {
      const qrPayment: Order | null = await this.preparePayment('QR')
      if (qrPayment === null || qrPayment.status !== 0) { return }
    }
    if (this.paymentUrl === '') {
      this.paymentMessage = '扫码支付暂不可用，请稍后重试'
      return
    }
    this.showPaymentCode = true
    this.paymentMessage = this.order.paymentSandbox === true
      ? '请使用另一台设备的支付宝沙箱钱包扫码，支付后将自动更新订单'
      : '请使用另一台设备的支付宝扫码，支付后将自动更新订单'
    this.startPaymentPolling()
  }

  private clearPaymentSession(): void {
    this.balancePaymentPassword = ''
    this.paymentUrl = ''
    this.showPaymentCode = false
    this.paymentMessage = ''
    this.paymentAttempted = false
    this.manualPaymentChecking = false
    this.stopPaymentPolling()
    this.stopPayCountdown()
  }

  private advanceAfterPayment(latest: Order): void {
    if (latest.status < 1 || latest.status > 4 || this.paymentAdvanced || !this.pageActive || !this.appForeground) { return }
    this.paymentAdvanced = true
    AppStorage.setOrCreate<number>('currentOrderId', latest.id)
    // 重新进入服务端确认后的订单阶段，重建时间轴并移除待付款操作。
    this.getUIContext().runScopedTask(() => { router.replaceUrl({ url: 'pages/OrderDetailPage' }) })
  }

  private payChannelName(): string {
    if (this.payChannel === 'ALIPAY') {
      return '支付宝'
    }
    if (this.payChannel === 'WECHAT') {
      return '微信'
    }
    return '余额'
  }

  private payButtonText(): string {
    return this.paying ? '支付中…' : `使用${this.payChannelName()}支付 ¥${this.order!.payAmount.toFixed(2)}`
  }

  private async refreshPaymentStatus(manual: boolean = true): Promise<void> {
    if (!this.pageActive || !this.appForeground || !this.loggedIn || this.paying || this.paymentChecking ||
      this.order === null || this.order.status !== 0) { return }
    if (manual) { this.manualPaymentChecking = true }
    this.paymentChecking = true
    const sessionEpoch: number = getAuthSessionEpoch()
    const latest: Order | null = await queryPaymentRemote(this.orderId)
    this.paymentChecking = false
    if (!this.pageActive || !this.appForeground || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch() ||
      this.order === null || this.order.status !== 0) {
      if (manual) { this.manualPaymentChecking = false }
      return
    }
    if (latest === null) {
      if (manual) {
        const errorMessage: string = getLastRemoteErrorMessage()
        promptAction.showToast({ message: errorMessage === '' ? '查询支付状态失败，请稍后重试' : errorMessage, duration: 3000 })
        this.manualPaymentChecking = false
      }
      return
    }
    this.order = latest
    this.syncServerClock(latest)
    if (latest.status !== 0) {
      this.clearPaymentSession()
      promptAction.showToast({ message: latest.status >= 1 && latest.status <= 4 ? '支付已确认' : '订单状态已更新', duration: 1800 })
      this.advanceAfterPayment(latest)
    } else {
      this.paymentUrl = latest.paymentUrl ?? this.paymentUrl
      this.startPaymentPolling()
      if (manual) { promptAction.showToast({ message: '尚未收到支付成功通知，将继续自动查询', duration: 1800 }) }
    }
    if (manual) { this.manualPaymentChecking = false }
  }

  /** 取消前直接说明扣款/退款后果，避免用户靠状态名猜测资金去向。 */
  private cancelDialogContent(): string {
    if (this.order !== null && this.order.status === 0) {
      return '该订单为待付款，平台尚未扣款；取消后将释放占用的库存与优惠券，确定取消吗？'
    }
    return '取消后支付金额将原路退回；已付款用户主动取消不返优惠券。进入制作后取消不恢复库存，确定取消吗？'
  }

  private reloadOrder(): void {
    if (!this.loggedIn) {
      this.order = null
      return
    }
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    this.order = orders.find(o => o.id === this.orderId) || null
    this.syncServerClock(this.order)
  }

  private getDeliverySteps(): DeliveryStep[] {
    if (this.order === null) {
      return []
    }
    const order: Order = this.order
    const steps: DeliveryStep[] = [
      { status: 1, title: '已下单', time: order.createTime, completed: order.status >= 1 },
      { status: 2, title: '商家接单', time: order.payTime || '', completed: order.status >= 2 },
      { status: 3, title: '配送中', time: order.deliverTime || '', completed: order.status >= 3 },
      { status: 4, title: '已送达', time: order.completeTime || '', completed: order.status >= 4 }
    ]
    return steps
  }

  build() {
    Stack() {
      Column() {
        // 导航栏
        PageHeader({ title: '订单详情', backText: '‹', backId: 'order-detail-back', onBack: () => { router.back() } })

        if (this.order === null) {
          Column({ space: SPACING.SM }) {
            Image(this.loggedIn ? $r('app.media.ui_gift') : $r('app.media.login_lock')).width(60).height(60).objectFit(ImageFit.Contain).margin({ top: 100 })
            Text(this.loggedIn ? '订单不存在' : '暂无登录')
              .fontSize(FONT_SIZE.LG)
              .fontColor(COLORS.TEXT_HINT)
              .margin({ top: SPACING.MD })
            if (!this.loggedIn) {
              Text('请登录后查看订单')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_HINT)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll(this.paymentScroller) {
            Column({ space: SPACING.SM }) {
              if (this.order!.status === 0 && this.payChannel === 'ALIPAY' && this.paymentAttempted) {
                Column({ space: SPACING.SM }) {
                  Text(this.showPaymentCode ? '其他设备扫码支付' : '支付宝支付').fontSize(FONT_SIZE.LG)
                    .fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                  Text(this.paymentMessage).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                    .textAlign(TextAlign.Center).id('order-payment-message')
                  if (this.showPaymentCode) {
                    QRCode(this.paymentUrl).width(180).height(180).color('#000000').backgroundColor('#FFFFFF')
                      .id('order-payment-qrcode')
                  } else {
                    Button('其他设备扫码支付').attributeModifier(new AppButtonStyle())
                      .enabled(!this.paying && !this.manualPaymentChecking)
                      .id('order-scan-other-device').onClick(() => { this.showOtherDevicePayment() })
                  }
                  Button('刷新支付状态').attributeModifier(new AppButtonStyle())
                    .enabled(this.hasPendingPayment() && !this.manualPaymentChecking && !this.paying)
                    .id('order-refresh-payment').onClick(() => { this.refreshPaymentStatus() })
                }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD).id('order-payment-panel')
              }

              this.StatusCard()

              if (this.order!.status === 4 || this.order!.status === 6 || this.refundRecords.length > 0) {
                this.RefundProgressCard()
              }

              // 店铺与商品卡片
              this.StoreAndItemsCard()

              Button('配送异常与处理记录').attributeModifier(new AppButtonStyle()).height(44).width('100%')
                .id('customer-order-support')
                .onClick(() => { router.pushUrl({ url: 'pages/OrderSupportPage', params: { orderId: this.orderId, canReport: canOrderAction(this.order!, 'REPORT_ISSUE', this.order!.status === 2 || this.order!.status === 3) } }) })

              // 配送信息卡片
              this.DeliveryInfoCard()

              // 金额明细卡片
              this.AmountDetailCard()

              // 订单信息卡片
              this.OrderInfoCard()
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .backgroundColor(COLORS.BG_PRIMARY)

          // 底部操作栏：固定于页面底部，不随内容滚动，避免操作按钮被长内容遮挡
          if (this.order!.status >= 0 && this.order!.status <= 4) {
            Column() {
              Divider().color(COLORS.DIVIDER)
              this.ActionButtons()
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.MD })
            .backgroundColor(COLORS.BG_WHITE)
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 取消订单确认弹窗
      if (this.showCancelDialog) {
        ConfirmDialog({
          title: '提示',
          content: this.cancelDialogContent(),
          confirmText: '确定取消',
          cancelText: '再想想',
          onConfirm: async () => {
            if (this.order !== null) {
              // 待付款订单未扣款；待接单订单取消后按原支付渠道全额退款。
              const unpaid: boolean = this.order.status === 0
              const refundAmount: number = this.order.payAmount
              if (!this.canDispatchOrder('CANCEL', this.order.status === 0 || this.order.status === 1)) { this.showCancelDialog = false; return }
              const ok: boolean = await cancelOrderRemote(this.order.id)
              if (ok) {
                this.clearPaymentSession()
                this.reloadOrder()
                promptAction.showToast({
                  message: unpaid
                    ? '订单已取消，平台未扣款；库存与优惠券已释放'
                    : `订单已取消，¥${refundAmount.toFixed(2)} 已按原支付渠道全额退回`,
                  duration: 2500
                })
              } else {
                const errorMessage: string = getLastRemoteErrorMessage()
                promptAction.showToast({ message: errorMessage === '' ? '取消订单失败，请稍后重试' : errorMessage, duration: 3000 })
              }
            }
            this.showCancelDialog = false
          },
          onCancel: () => {
            this.showCancelDialog = false
          }
        })
      }

      // 确认收货确认弹窗
      if (this.showConfirmDialog) {
        ConfirmDialog({
          title: '确认收到餐品？',
          content: '确认后订单款项将结算；送达48小时内仍可申请售后退款',
          confirmText: '确认收到',
          cancelText: '暂不确认',
          onConfirm: async () => {
            if (this.order !== null) {
              if (!this.canDispatchOrder('CONFIRM', this.order.status === 4 && (this.order.escrowStatus ?? 0) === 0)) { this.showConfirmDialog = false; return }
              const ok: boolean = await confirmOrderRemote(this.order.id)
              if (ok) {
                this.reloadOrder()
                promptAction.showToast({ message: '已确认收货', duration: 1500 })
                // 确认收货后返回订单列表，列表 onPageShow 会重新同步后端数据。
                router.back()
              } else {
                const errorMessage: string = getLastRemoteErrorMessage()
                promptAction.showToast({ message: errorMessage === '' ? '确认收货失败，请稍后重试' : errorMessage, duration: 2200 })
              }
            }
            this.showConfirmDialog = false
          },
          onCancel: () => {
            this.showConfirmDialog = false
          }
        })
      }

      // 申请退款弹窗（演进项：退款审批流程，见大纲 7.11）
      if (this.showRefundDialog) {
        this.RefundDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  private openRefundDialog(): void {
    if (!this.canDispatchOrder('REFUND', this.order?.status === 4 && (this.order?.escrowStatus ?? 0) === 0 && this.order?.reviewed === 0)) { return }
    if (this.order === null || this.refundSubmitting || this.refundPreventsSettlement || this.refundOrderError !== '') { return }
    this.refundDialogVersion += 1
    this.refundReason = ''
    this.refundReasonType = ''
    this.refundSubmitError = ''
    this.refundAmount = (this.order.capabilities?.refundRemaining ?? this.order.payAmount).toFixed(2)
    this.refundImages = []
    this.refundUploading = false
    this.refundAppealId = 0
    this.refundPayloadLocked = false
    this.refundSubmitKey = `refund-${this.order.id}-${Date.now().toString(36)}-${Math.random().toString(36).substring(2, 10)}`
    this.showRefundDialog = true
  }

  private openRefundAppeal(record: RefundRecord): void {
    if (this.order === null || record.status !== 'REJECTED' || (record.appealCount ?? 0) > 0) { return }
    if (this.refundSubmitting || this.refundUploading) { return }
    this.refundDialogVersion += 1
    this.refundReason = ''
    this.refundSubmitError = ''
    this.refundImages = []
    this.refundPayloadLocked = false
    this.refundAppealId = record.id
    this.refundReasonType = 'OTHER'
    this.refundAmount = record.amount.toFixed(2)
    this.showRefundDialog = true
  }

  private closeRefundDialog(): void {
    if (this.refundSubmitting || this.refundUploading) { return }
    this.showRefundDialog = false
    this.refundDialogVersion += 1
  }

  private refundReasonLabel(code: string): string {
    const option: RefundReasonOption | undefined = this.refundReasonOptions.find((item: RefundReasonOption) => item.code === code)
    return option?.label ?? '其他'
  }

  private refundStatusText(status: string): string {
    if (status === 'PENDING') { return '待审核' }
    if (status === 'REFUNDED') { return '已退款' }
    if (status === 'REJECTED') { return '已拒绝' }
    if (status === 'APPROVED') { return '退款处理中' }
    return '状态待更新'
  }

  private refundStatusColor(status: string): ResourceColor {
    if (status === 'REFUNDED') { return COLORS.SUCCESS }
    if (status === 'REJECTED') { return COLORS.ERROR }
    return COLORS.PRIMARY
  }

  // 同一弹层始终复用 key；响应丢失后重试取回原申请，失败保留原因与补充说明。
  private async submitRefund(): Promise<void> {
    if (this.order === null || this.refundSubmitting || this.refundUploading) { return }
    if (this.refundAppealId === 0 && !this.canDispatchOrder('REFUND', this.order.status === 4 && (this.order.escrowStatus ?? 0) === 0 && this.order.reviewed === 0)) { return }
    const amount: number = Number(this.refundAmount)
    const remaining: number = this.order.capabilities?.refundRemaining ?? this.order.payAmount
    if (this.refundAppealId === 0 && !this.refundPayloadLocked && (!Number.isFinite(amount) || amount <= 0 || amount > remaining || !/^[0-9]+(\.[0-9]{1,2})?$/.test(this.refundAmount))) {
      this.refundSubmitError = '请输入不超过可退余额的金额（最多两位小数）'
      return
    }
    if (this.refundReasonType === '') {
      this.refundSubmitError = '请选择退款原因'
      return
    }
    if (this.refundReasonType === 'OTHER' && this.refundReason.trim() === '') {
      this.refundSubmitError = '选择“其他”时，请说明遇到的问题'
      return
    }
    const requestedOrderId: number = this.order.id
    const sessionEpoch: number = getAuthSessionEpoch()
    const dialogVersion: number = this.refundDialogVersion
    this.refundSubmitting = true
    this.refundSubmitError = ''
    this.refundPayloadLocked = true
    const evidence: RefundEvidenceRequest = { reason: this.refundReason.trim(), evidenceImages: this.refundImages }
    const record: RefundRecord | null = this.refundAppealId > 0
      ? await appealRefundApi(requestedOrderId, this.refundAppealId, evidence)
      : await applyRefundRemote(requestedOrderId, this.refundReasonType, this.refundReason.trim(),
        this.refundSubmitKey, amount, this.refundImages)
    if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch() ||
      dialogVersion !== this.refundDialogVersion || requestedOrderId !== this.orderId) { return }
    this.refundSubmitting = false
    if (record === null) {
      const errorMessage: string = getLastRemoteErrorMessage()
      this.refundSubmitError = errorMessage === '' || errorMessage.indexOf('网络') >= 0 || errorMessage.indexOf('后端') >= 0
        ? '暂未确认提交结果，请检查网络后重试；重试会核对同一申请。'
        : `${errorMessage}；填写内容已保留，可重试核对同一申请。`
      return
    }
    this.showRefundDialog = false
    this.refundRecords = [record].concat(this.refundRecords.filter((item: RefundRecord) => item.id !== record.id))
      .sort((a: RefundRecord, b: RefundRecord) => b.id - a.id)
    this.refundPreventsSettlement = this.refundRecords.some((item: RefundRecord) =>
      item.status === 'PENDING' || item.status === 'APPROVED')
    this.refundHistoryLoaded = true
    this.refundHistoryError = ''
    const message: string = record.status === 'REFUNDED'
      ? `申请 #${record.id} 已退款 ¥${record.amount.toFixed(2)}，请查看退款记录`
      : record.status === 'REJECTED'
        ? `申请 #${record.id} 已被拒绝，请查看拒绝原因`
        : `申请 #${record.id} ${this.refundStatusText(record.status)}，可在退款进度中查看`
    promptAction.showToast({ message: message, duration: 2400 })
    this.refreshRefundProgress()
  }

  @Builder
  RefundProgressCard() {
    Column({ space: SPACING.SM }) {
      Row({ space: SPACING.SM }) {
        Text('退款进度').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        Button(this.refundHistoryLoading ? '更新中…' : '刷新进度')
          .attributeModifier(new AppButtonStyle()).height(44)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY).backgroundColor(Color.Transparent)
          .enabled(!this.refundHistoryLoading).id('order-refund-refresh')
          .onClick(() => { this.refreshRefundProgress() })
      }.width('100%')
      if ((this.order?.capabilities?.afterSalesDeadline ?? '') !== '') {
        Text(`售后申请截止：${this.order?.capabilities?.afterSalesDeadline ?? ''}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      }
      if (this.refundOrderError !== '') {
        Text(this.refundOrderError).width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
          .id('order-refund-order-error')
      }
      if (this.refundHistoryError !== '') {
        Text(this.refundHistoryError).width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
          .id('order-refund-load-error')
        Button('重试加载退款记录').attributeModifier(new AppButtonStyle()).height(44).width('100%')
          .enabled(!this.refundHistoryLoading).id('order-refund-retry')
          .onClick(() => { this.refreshRefundProgress() })
      } else if (this.refundHistoryLoading && !this.refundHistoryLoaded) {
        Text('正在加载退款记录…').width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      } else if (this.refundHistoryLoaded && this.refundRecords.length === 0) {
        Text('暂无退款申请记录').width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          .id('order-refund-empty')
      }
      ForEach(this.refundRecords, (record: RefundRecord) => {
        this.RefundRecordContent(record)
      }, (record: RefundRecord) => `${record.id}-${record.status}-${record.processTime ?? ''}-${record.rejectReason ?? ''}`)
    }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.LG).id('order-refund-progress')
  }

  @Builder
  RefundRecordContent(record: RefundRecord) {
    Column({ space: SPACING.SM }) {
      Divider().color(COLORS.DIVIDER)
      Row({ space: SPACING.SM }) {
        Text(`${record.id === this.refundRecords[0]?.id ? '最新申请' : '历史申请'} #${record.id}`)
          .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        Text(this.refundStatusText(record.status)).fontSize(FONT_SIZE.SM).fontColor(this.refundStatusColor(record.status))
          .id(`order-refund-status-${record.id}`)
      }.width('100%')
      Text(`退款金额：¥${record.amount.toFixed(2)}`).width('100%').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
      Text(this.refundReasonLabel(record.reasonType)).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY)
        .backgroundColor(COLORS.TAG_BG).padding({ left: SPACING.SM, right: SPACING.SM, top: 4, bottom: 4 })
        .borderRadius(BORDER_RADIUS.SM)
      Text(`补充说明：${(record.reason ?? '').trim() === '' ? '未填写' : record.reason}`)
        .width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      Text(`申请时间：${record.applyTime}`).width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      if ((record.merchantResponse ?? '') !== '') {
        Text(`商家举证：${record.merchantResponse ?? ''}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      }
      ForEach(record.evidenceImages ?? [], (url: string) => {
        Image(url.startsWith('/') ? getApiBaseUrl() + url : url).width(80).height(80).objectFit(ImageFit.Cover)
      }, (url: string) => url)
      ForEach(record.merchantEvidenceImages ?? [], (url: string) => {
        Image(url.startsWith('/') ? getApiBaseUrl() + url : url).width(80).height(80).objectFit(ImageFit.Cover)
      }, (url: string) => url)
      Text(`处理时间：${(record.processTime ?? '').trim() === '' ? '尚未处理' : record.processTime ?? ''}`)
        .width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      if (record.status === 'REJECTED') {
        Text(`拒绝原因：${(record.rejectReason ?? '').trim() === '' ? '未提供说明' : record.rejectReason ?? ''}`)
          .width('100%').fontSize(FONT_SIZE.MD).fontColor(COLORS.ERROR).id(`order-refund-reject-reason-${record.id}`)
        if ((record.appealCount ?? 0) === 0) {
          Button('申诉一次').attributeModifier(new AppButtonStyle()).height(44)
            .id(`order-refund-appeal-${record.id}`).onClick(() => { this.openRefundAppeal(record) })
        }
      } else if (record.status === 'PENDING') {
        Text('审核结果会显示在这里，可刷新进度查看更新。').width('100%')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      } else if (record.status === 'REFUNDED') {
        Text('款项已按原支付渠道退回，请查看支付账户。').width('100%')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: SPACING.SM, bottom: SPACING.SM })
  }

  @Builder
  RefundDialog() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.TEXT_PRIMARY)
        .opacity(0.4)
        .onClick(() => { this.closeRefundDialog() })

      Column() {
        Row() {
          Text(this.refundAppealId > 0 ? '退款申诉' : '申请退款')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
          Button() {
            Image($r('app.media.ui_close')).width(FONT_SIZE.LG).height(FONT_SIZE.LG).objectFit(ImageFit.Contain)
          }.width(44).height(44).backgroundColor(Color.Transparent).enabled(!this.refundSubmitting)
            .accessibilityText('关闭退款申请').id('order-refund-close')
            .onClick(() => { this.closeRefundDialog() })
        }
        .width('100%')
        .padding({ bottom: SPACING.MD })

        Scroll() {
          Column({ space: SPACING.SM }) {
            Text(`可退余额：¥${(this.order?.capabilities?.refundRemaining ?? this.order?.payAmount ?? 0).toFixed(2)}（审核通过后原路退回）`)
              .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).width('100%')
            Text('申请金额（元）').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY)
            TextInput({ text: this.refundAmount, placeholder: '例如：10.50' }).type(InputType.NUMBER_DECIMAL)
              .enabled(this.refundAppealId === 0 && !this.refundSubmitting && !this.refundPayloadLocked)
              .id('order-refund-amount').onChange((value: string) => { this.refundAmount = value })
            EvidenceImages({ images: $refundImages, uploading: $refundUploading, disabled: this.refundSubmitting || this.refundPayloadLocked, contextVersion: (): number => this.refundDialogVersion })
            Text('退款原因（请选择一项）').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium)
              .fontColor(COLORS.TEXT_PRIMARY).width('100%').margin({ top: SPACING.SM })
            ForEach(this.refundReasonOptions, (opt: RefundReasonOption) => {
              this.RefundReasonChoice(opt)
            }, (opt: RefundReasonOption) => opt.code)
            Text(this.refundReasonType === 'OTHER' ? '补充说明（必填）' : '补充说明（选填）')
              .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).width('100%').margin({ top: SPACING.SM })
            TextArea({ text: this.refundReason, placeholder: '例如：少送了一份米饭，最多50字' })
              .attributeModifier(new AppTextAreaStyle()).width('100%').height(100).maxLength(50)
              .enabled(!this.refundSubmitting && !this.refundPayloadLocked).id('order-refund-note')
              .onChange((value: string) => { this.refundReason = value })
          }.width('100%').padding({ bottom: SPACING.SM })
        }.layoutWeight(1).scrollBar(BarState.Auto).width('100%')

        if (this.refundSubmitError !== '') {
          Text(this.refundSubmitError).width('100%').fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
            .margin({ top: SPACING.SM }).id('order-refund-submit-error')
        }

        Row({ space: SPACING.MD }) {
          Button('取消')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.refundSubmitting).id('order-refund-cancel')
            .onClick(() => { this.closeRefundDialog() })
          Button(this.refundSubmitting ? '提交中…' : '提交申请')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.refundSubmitting && !this.refundUploading).id('order-refund-submit')
            .onClick(() => { this.submitRefund() })
        }
        .width('100%')
        .margin({ top: SPACING.LG })
      }
      .width('100%')
      .height('85%')
      .padding(SPACING.LG)
      .backgroundColor(COLORS.BG_WHITE)
      .borderRadius({ topLeft: BORDER_RADIUS.XL, topRight: BORDER_RADIUS.XL })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  RefundReasonChoice(option: RefundReasonOption) {
    Button(option.label)
      .attributeModifier(new AppButtonStyle()).width('100%').constraintSize({ minHeight: 44 })
      .fontSize(FONT_SIZE.MD).fontColor(this.refundReasonType === option.code ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
      .backgroundColor(this.refundReasonType === option.code ? COLORS.PRIMARY : COLORS.TAG_BG)
      .borderRadius(BORDER_RADIUS.MD).enabled(!this.refundSubmitting && !this.refundPayloadLocked)
      .accessibilitySelected(this.refundReasonType === option.code)
      .accessibilityText(`${option.label}${this.refundReasonType === option.code ? '，已选择' : '，未选择'}`)
      .id(`order-refund-reason-${option.code}`)
      .onClick(() => { this.refundReasonType = option.code; this.refundSubmitError = '' })
  }

  @Builder
  StatusCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text((this.order!.cancelSource ?? '') === 'MERCHANT'
          ? '商家未能接单' : getOrderStatusText(this.order!.status, this.order!.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.BIG_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(getOrderStatusColor(this.order!.status, this.order!.escrowStatus ?? 0))
          // 设备端 UiTest 用：断言订单状态文案（待付款/已取消/已完成…）
          .id('order-detail-status')
      }
      .width('100%')

      if ((this.order!.cancelSource ?? '') === 'MERCHANT') {
        Column({ space: SPACING.XS }) {
          Text(`原因：${(this.order!.cancelReason ?? '').trim() === ''
            ? '商家无法承接本次订单' : this.order!.cancelReason}`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
          Text('款项处理进度以订单资金状态为准')
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
        }
        .width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_PRIMARY)
        .borderRadius(BORDER_RADIUS.MD).id('order-merchant-reject-reason')
      }

      if (this.order!.status === 2) {
        Text('商家正在制作餐品，请留意后续配送状态')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
      } else if (this.order!.status === 3) {
        Text('配送中，暂无法准确预计送达时间')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
      }

      // 待付款：支付倒计时提示（超时由后端自动取消）
      if (this.order!.status === 0) {
        Row() {
          Image($r('app.media.home_clock')).width(FONT_SIZE.LG).height(FONT_SIZE.LG).objectFit(ImageFit.Contain)
          Text(this.payRemainSeconds > 0
            ? `请在剩余 ${this.payCountdownText()} 内完成支付，超时订单将自动取消`
            : '支付时限已到，正在确认订单状态…')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.ERROR)
            .layoutWeight(1)
            .margin({ left: SPACING.SM })
            .id('order-pay-countdown')
        }
        .width('100%')
        .padding(SPACING.MD)
        .backgroundColor(COLORS.BG_PRIMARY)
        .borderRadius(BORDER_RADIUS.MD)
      }

      if ((this.order!.cancelSource ?? '') !== 'MERCHANT') {
        OrderStatusTimeline({ steps: this.getDeliverySteps() })
      }

      // 配送中：仅展示服务端确认的真实阶段，不模拟位置或预计时间。
      if (this.order!.status === 3) {
        this.DeliveryStatusNotice()
      }
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  DeliveryStatusNotice() {
    Column({ space: SPACING.SM }) {
      Row() {
        Image($r('app.media.login_rider')).width(18).height(18).objectFit(ImageFit.Contain)
        Text(' 骑手配送中')
          .fontSize(FONT_SIZE.MD)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRIMARY)
      }
      .width('100%')
      Text('配送状态由骑手实际操作更新，暂无法准确预计送达时间')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.WARM_BG)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  StoreAndItemsCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Image($r('app.media.login_store')).width(FONT_SIZE.LG).height(FONT_SIZE.LG).objectFit(ImageFit.Contain)
        Text(this.order!.storeName)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      ForEach(this.order!.items, (item: CartItem) => {
        Row() {
          Column({ space: SPACING.XS }) {
            Text(item.goods.name)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_PRIMARY)
            // 多规格：展示下单时锁定的规格快照
            if ((item.specName ?? '') !== '') {
              Text(`规格：${item.specName}`)
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.TEXT_HINT)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(`x${item.quantity}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ right: SPACING.MD })
          Text(`¥${((item.price ?? item.goods.price) * item.quantity).toFixed(2)}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: SPACING.XS, bottom: SPACING.XS })
      }, (item: CartItem, index: number) => `${index}_${item.goods.id}_${item.specId ?? 0}`)
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  DeliveryInfoCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('配送信息')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      Row() {
        Text('收货人')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(this.order!.address.name)
          .fontSize(FONT_SIZE.MD)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .margin({ left: SPACING.SM })
        Text(this.order!.address.phone)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ left: SPACING.MD })
      }
      .width('100%')

      Row() {
        Text('收货地址')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(`${this.order!.address.address} ${this.order!.address.detail}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
      }
      .width('100%')

      Row() {
        if (this.order!.deliveryType !== 'PICKUP') {
          Image($r('app.media.login_rider')).width(18).height(18).objectFit(ImageFit.Contain)
        }
        Text(this.order!.deliveryType === 'PICKUP' ? '取餐方式' : '配送骑手')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ left: SPACING.SM })
        if (this.order!.deliveryType === 'PICKUP') {
          Text('到店自取，无需骑手配送')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .layoutWeight(1)
            .margin({ left: SPACING.SM })
        } else if (this.order!.riderName !== undefined && this.order!.riderName !== '') {
          Text(`${this.order!.riderName} ${this.order!.riderPhone ?? ''}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .margin({ left: SPACING.SM })
        } else {
          Text(this.order!.status === 0 ? '支付后等待接单' : this.order!.status <= 3 ? '待骑手接单' : '未分配骑手')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_HINT)
            .layoutWeight(1)
            .margin({ left: SPACING.SM })
            .id('order-rider-pending')
        }
      }
      .width('100%')
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  AmountDetailCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('金额明细')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      Row() {
        Text('商品总价')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(`¥${this.order!.totalPrice.toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')

      Row() {
        Text('配送费')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(`¥${this.order!.deliveryFee.toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')

      if (this.order!.discountAmount > 0) {
        Row() {
          Text('优惠')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .layoutWeight(1)
          Text(`-¥${this.order!.discountAmount.toFixed(2)}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
        }
        .width('100%')
      }

      Divider()
        .color(COLORS.DIVIDER)
        .margin({ top: SPACING.SM, bottom: SPACING.SM })

      Row() {
        Text('实付')
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.TEXT_PRIMARY)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text(`¥${this.order!.payAmount.toFixed(2)}`)
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.PRICE_RED)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  OrderInfoCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('订单信息')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      Row() {
        Text('订单号')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(this.order!.orderNo ?? this.order!.id.toString())
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row() {
        Text('下单时间')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(this.order!.createTime)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      if (this.order!.remark !== '') {
        Row() {
          Text('备注')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text(this.order!.remark)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }

      if ((this.order!.expectTime ?? '') !== '') {
        Row() {
          Text('预约送达')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text(this.order!.expectTime ?? '')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
            .id('order-expect-time')
        }
        .width('100%')
      }
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  ActionButtons() {
    // 服务端能力优先；旧服务端沿用原状态规则。确认与评价不关闭送达48小时内售后。
    if (this.order!.status >= 0 && this.order!.status <= 4) {
      if (canOrderAction(this.order!, 'PAY', this.order!.status === 0)) {
        Row({ space: SPACING.SM }) {
          ForEach(this.payChannelOptions, (opt: PayChannelOption) => {
            this.PayChannelChip(opt)
          }, (opt: PayChannelOption) => opt.code)
        }
        .width('100%')
        .margin({ bottom: SPACING.MD })
        if (this.payChannel === 'BALANCE') {
          Text('支付密码')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width('100%')
          TextInput({ placeholder: '请输入 6 位数字支付密码', text: this.balancePaymentPassword })
            .type(InputType.Password)
            .inputFilter('[0-9]')
            .maxLength(6)
            .fontColor(COLORS.TEXT_PRIMARY)
            .backgroundColor(COLORS.BG_PRIMARY)
            .border({ width: 1, color: COLORS.DIVIDER })
            .borderRadius(BORDER_RADIUS.MD)
            .height(44)
            .margin({ bottom: SPACING.MD })
            .id('order-payment-password')
            .onChange((value: string) => { this.balancePaymentPassword = value })
        }
      }
      Row({ space: SPACING.MD }) {
        // 待付款：取消订单（未支付，仅释放库存与优惠券）
        if (this.order!.status === 0) {
          Button('取消订单')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.paying && !this.manualPaymentChecking && canOrderAction(this.order!, 'CANCEL', true))
            .id('order-cancel')
            .onClick(() => { this.showCancelDialog = true })

          Button(this.payButtonText())
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(2)
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.paying && !this.manualPaymentChecking && canOrderAction(this.order!, 'PAY', true))
            .id('order-pay')
            .onClick(() => { this.payNow() })
        }

        // 商家接单前仍可自助取消，并按原支付渠道全额退款。
        if (this.order!.status !== 0 && canOrderAction(this.order!, 'CANCEL', this.order!.status === 1 && (this.order!.escrowStatus ?? 0) === 0)) {
          Button('取消订单')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.showCancelDialog = true })
        }

        if (this.order!.status === 2 || this.order!.status === 3) {
          Text(this.order!.status === 2
            ? '订单已进入制作，如需处理请联系平台'
            : '订单已进入配送，如需处理请联系平台')
            .layoutWeight(1)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_HINT)
            .textAlign(TextAlign.Center)
        }

        // status===4 且托管款未结算：确认收货并结算
        if (canOrderAction(this.order!, 'CONFIRM', this.order!.status === 4 && (this.order!.escrowStatus ?? 0) === 0)) {
          Button('确认收到')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.refundPreventsSettlement && this.refundOrderError === '' && !this.refundSubmitting)
            .onClick(() => { this.showConfirmDialog = true })
        }

        // 服务端计算售后时限与可退余额，支持已确认/已评价订单部分退款。
        if (canOrderAction(this.order!, 'REFUND', this.order!.status === 4 && (this.order!.escrowStatus ?? 0) === 0 && this.order!.reviewed === 0)) {
          Button('申请退款')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.ERROR)
            .backgroundColor(Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .borderWidth(1)
            .borderColor(COLORS.ERROR)
            .enabled(!this.refundPreventsSettlement && this.refundOrderError === '' && !this.refundSubmitting)
            .id('order-refund-entry')
            .onClick(() => { this.openRefundDialog() })
        }

        // status===4 (已送达/已完成): 再来一单 + 商品评价
        if (this.order!.status === 4) {
          Button(this.reorderAdding ? '加入中…'
            : this.reorderFailedItems.length > 0 ? '只重试失败商品'
              : this.reorderHasUncertainItems ? '请先查看购物车' : '再来一单')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
            .backgroundColor(Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .borderWidth(1)
            .borderColor(COLORS.PRIMARY)
            .enabled(!this.reorderAdding &&
              (!this.reorderHasUncertainItems || this.reorderFailedItems.length > 0))
            .id('order-reorder')
            .onClick(() => {
              if (this.order !== null) {
                logInfo('Order', `再来一单 orderId=${this.order.id} 商品数=${this.order.items.length}`)
                this.addAgain()
              }
            })
          if (canOrderAction(this.order!, 'REVIEW', (this.order!.escrowStatus ?? 0) === 1 && this.order!.reviewed === 0)) {
            Button('评价商品')
              .attributeModifier(new AppButtonStyle())
              .layoutWeight(1)
              .height(44)
              .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
              .backgroundColor(COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .id('order-review-entry')
              .onClick(() => {
                if (!this.canDispatchOrder('REVIEW', this.order?.status === 4 && (this.order?.escrowStatus ?? 0) === 1 && this.order?.reviewed === 0)) { return }
                if (this.order !== null && this.order.items.length > 0) {
                  AppStorage.setOrCreate<number>('currentOrderId', this.order.id)
                  AppStorage.setOrCreate<number>('currentReviewGoodsId', this.order.items[0].goods.id)
                  router.pushUrl({ url: 'pages/ReviewPage' })
                } else {
                  promptAction.showToast({ message: '订单中没有可评价的商品' })
                }
              })
          } else if ((this.order!.escrowStatus ?? 0) === 0 && this.order!.reviewed === 0) {
            Text('确认收货后可评价商品').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          } else if (this.order!.reviewed === 1) {
            Text('已评价商品').fontSize(FONT_SIZE.SM).fontColor(COLORS.SUCCESS)
          }
        }
      }
      .width('100%')
      .margin({ top: SPACING.MD })
    }
  }

  @Builder
  PayChannelChip(opt: PayChannelOption) {
    Text(opt.label)
      .fontSize(FONT_SIZE.XS)
      .fontColor(this.payChannel === opt.code ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
      .backgroundColor(this.payChannel === opt.code ? COLORS.PRIMARY : COLORS.TAG_BG)
      .padding({ left: SPACING.SM, right: SPACING.SM, top: 4, bottom: 4 })
      .borderRadius(BORDER_RADIUS.SM)
      .accessibilitySelected(this.payChannel === opt.code)
      .enabled(opt.code !== 'WECHAT' && !this.paying && !this.manualPaymentChecking)
      .opacity(opt.code === 'WECHAT' ? 0.45 : 1)
      .id(`order-pay-channel-${opt.code}`)
      .onClick(() => {
        this.payChannel = opt.code
        this.balancePaymentPassword = ''
        this.showPaymentCode = false
      })
  }
}
