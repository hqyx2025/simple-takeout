import { AppButtonStyle, AppCardStyle, AppTextAreaStyle } from '../common/theme/AppTheme'
/**
 * 订单详情页
 * 展示订单状态时间轴、店铺与商品、配送信息、金额明细、订单信息
 * 根据订单状态显示对应操作按钮（取消订单 / 确认收货 / 再来一单 / 去评价）
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor } from '../common/Constants'
import { Order, CartItem, DeliveryStep } from '../model/Models'
import { cancelOrderRemote, confirmOrderRemote, applyRefundRemote, addCartItemRemote, fetchOrderDetailRemote, getLastRemoteErrorMessage, syncCartRemote, payOrderRemote, queryPaymentRemote } from '../service/AppStorageManager'
import { OrderStatusTimeline } from '../components/OrderStatusTimeline'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { logInfo } from '../service/AppLogger'
import { bundleManager } from '@kit.AbilityKit'
import { getAuthSessionEpoch, getServerClockOffsetMs } from '../service/HttpClient'

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

  @State order: Order | null = null
  @StorageLink('isLoggedIn') @Watch('onLoginChanged') loggedIn: boolean = false
  @StorageLink('appForeground') @Watch('onAppForegroundChanged') appForeground: boolean = true
  @State showCancelDialog: boolean = false
  @State showConfirmDialog: boolean = false
  @State showRefundDialog: boolean = false
  @State refundReason: string = ''
  @State refundReasonType: string = 'OTHER'
  private refundReasonOptions: RefundReasonOption[] = [
    new RefundReasonOption('NOT_RECEIVED', '未收到餐'),
    new RefundReasonOption('QUALITY_ISSUE', '餐品质量问题'),
    new RefundReasonOption('WRONG_ITEM', '商品不符'),
    new RefundReasonOption('DONOT_WANT', '不想要了'),
    new RefundReasonOption('OTHER', '其他')
  ]
  @State payChannel: string = 'BALANCE'
  private payChannelOptions: PayChannelOption[] = [
    new PayChannelOption('BALANCE', '余额支付'),
    new PayChannelOption('ALIPAY', '支付宝'),
    new PayChannelOption('WECHAT', '微信支付')
  ]
  orderId: number = 0
  // 骑手配送动画状态
  @State riderProgress: number = 0
  @State trackWidth: number = 300
  private riderTimer: number = -1
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

  private async addAgain(): Promise<void> {
    if (this.order === null) {
      return
    }
    let allSucceeded: boolean = true
    for (let i = 0; i < this.order.items.length; i++) {
      const item: CartItem = this.order.items[i]
      const ok: boolean = await addCartItemRemote(item)
      if (!ok) {
        allSucceeded = false
      }
    }
    if (!allSucceeded) {
      await syncCartRemote()
      promptAction.showToast({ message: '部分商品加入购物车失败，请检查商品状态', duration: 2200 })
      return
    }
    promptAction.showToast({ message: '已加入购物车' })
  }

  async aboutToAppear(): Promise<void> {
    this.pageActive = true
    const routerOrderId: number = AppStorage.get<number>('currentOrderId') || 0
    this.orderId = this.orderId || routerOrderId
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
    const remoteOrder: Order | null = await fetchOrderDetailRemote(this.orderId)
    if (!this.pageActive || !this.loggedIn || sessionEpoch !== getAuthSessionEpoch()) { return }
    this.order = remoteOrder
    this.syncServerClock(remoteOrder)
    if (remoteOrder !== null && remoteOrder.status === 0) {
      const storedChannel: string = remoteOrder.paymentChannel ?? ''
      this.payChannel = storedChannel === 'ALIPAY' || storedChannel === 'BALANCE'
        ? storedChannel : 'BALANCE'
      this.paymentUrl = remoteOrder.paymentUrl ?? ''
      this.paymentAttempted = storedChannel === 'ALIPAY'
      this.paymentMessage = storedChannel !== 'ALIPAY' ? '' : remoteOrder.paymentSandbox === true
        ? '当前沙箱仅支持其他设备的支付宝沙箱钱包扫码支付'
        : '支付已准备，可使用本机支付宝或选择其他设备扫码'
    } else {
      this.paymentUrl = ''
    }
    logInfo('Page', `进入订单详情页 OrderDetailPage orderId=${this.orderId} 状态=${this.order !== null ? this.order.status : -1}`)
    // 配送中状态启动骑手动画
    if (this.order !== null && this.order.status === 3) {
      this.startRiderAnimation()
    }
    // 待付款状态启动支付倒计时（超时后端会自动取消订单）
    if (this.order !== null && this.order.status === 0) {
      this.startPayCountdown()
      this.startPaymentPolling()
    }
  }

  aboutToDisappear() {
    this.pageActive = false
    this.stopRiderAnimation()
    this.stopPayCountdown()
    this.stopPaymentPolling()
  }

  onPageShow(): void {
    this.pageActive = true
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
  }

  private onLoginChanged(): void {
    if (this.loggedIn) { return }
    this.clearPaymentSession()
    this.stopRiderAnimation()
    this.order = null
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

  /** 待付款订单支付：成功后刷新订单并提示。 */
  private async payNow(): Promise<void> {
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
    if (this.order === null) { return null }
    this.paying = true
    const sessionEpoch: number = getAuthSessionEpoch()
    const paid: Order | null = await payOrderRemote(this.order.id, this.payChannel, mode)
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

  // 启动配送进度展示动画
  private startRiderAnimation(): void {
    this.stopRiderAnimation()
    this.riderProgress = 0
    this.riderTimer = setInterval(() => {
      if (this.riderProgress >= 0.88) {
        this.stopRiderAnimation()
        return
      }
      this.riderProgress += 0.02
    }, 250)
  }

  private stopRiderAnimation(): void {
    if (this.riderTimer >= 0) {
      clearInterval(this.riderTimer)
      this.riderTimer = -1
    }
  }

  // 计算配送预估剩余时间（基于下单时间，预估总时长30分钟）
  private getEstimatedTime(): string {
    if (this.order === null) {
      return ''
    }
    const createDate: Date = new Date(this.order.createTime.replace(/-/g, '/'))
    const elapsed: number = Math.floor((Date.now() - createDate.getTime()) / 60000)
    let remain: number = 30 - elapsed
    if (remain < 5) {
      remain = 5
    }
    return `预计 ${remain} 分钟送达`
  }

  /** 取消订单弹窗文案：待付款订单未扣款，说明释放库存与优惠券即可。 */
  private cancelDialogContent(): string {
    if (this.order !== null && this.order.status === 0) {
      return '该订单尚未支付，取消后将释放占用的库存与优惠券，确定取消吗？'
    }
    return '确定要取消该订单吗？取消后支付金额将按原支付渠道退回。'
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

              // 店铺与商品卡片
              this.StoreAndItemsCard()

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
              // 待付款订单未扣款，仅释放库存与优惠券；已支付订单取消即退款（现状口径）
              const unpaid: boolean = this.order.status === 0
              const refundAmount: number = this.order.payAmount
              const ok: boolean = await cancelOrderRemote(this.order.id)
              if (ok) {
                this.clearPaymentSession()
                this.reloadOrder()
                promptAction.showToast({
                  message: unpaid
                    ? '订单已取消，库存与优惠券已释放'
                    : `订单已取消，退款 ¥${refundAmount.toFixed(2)} 已按原支付渠道退回`,
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
          title: '提示',
          content: '确认已收到商品吗？',
          confirmText: '确认收货',
          cancelText: '取消',
          onConfirm: async () => {
            if (this.order !== null) {
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

  // 提交退款申请
  private async submitRefund(): Promise<void> {
    if (this.order === null) {
      this.showRefundDialog = false
      return
    }
    const ok: boolean = await applyRefundRemote(this.order.id, this.refundReasonType, this.refundReason)
    this.showRefundDialog = false
    if (ok) {
      this.reloadOrder()
      promptAction.showToast({ message: '退款申请已提交，等待平台审核', duration: 1800 })
    } else {
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: errorMessage === '' ? '退款申请失败，请稍后重试' : errorMessage, duration: 2200 })
    }
  }

  @Builder
  RefundDialog() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.TEXT_PRIMARY)
        .opacity(0.4)
        .onClick(() => { this.showRefundDialog = false })

      Column() {
        Row() {
          Text('申请退款')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
Image($r('app.media.ui_close')).width(FONT_SIZE.LG).height(FONT_SIZE.LG).objectFit(ImageFit.Contain)
.onClick(() => { this.showRefundDialog = false })
        }
        .width('100%')
        .padding({ bottom: SPACING.MD })

        Text(`退款金额：¥${this.order !== null ? this.order.payAmount.toFixed(2) : '0.00'}（审核通过后按原支付渠道退回）`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
          .margin({ bottom: SPACING.SM })

        Row({ space: SPACING.SM }) {
          ForEach(this.refundReasonOptions, (opt: RefundReasonOption) => {
            Text(opt.label)
              .fontSize(FONT_SIZE.XS)
              .fontColor(this.refundReasonType === opt.code ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
              .backgroundColor(this.refundReasonType === opt.code ? COLORS.PRIMARY : COLORS.TAG_BG)
              .padding({ left: SPACING.SM, right: SPACING.SM, top: 4, bottom: 4 })
              .borderRadius(BORDER_RADIUS.SM)
              .onClick(() => { this.refundReasonType = opt.code })
          }, (opt: RefundReasonOption) => opt.code)
        }
        .width('100%')
        .margin({ bottom: SPACING.MD })

        TextArea({ placeholder: '补充说明（选填，最多50字）' })
          .attributeModifier(new AppTextAreaStyle())
          .width('100%')
          .height(90)
          .maxLength(50)
          .onChange((value: string) => { this.refundReason = value })

        Row({ space: SPACING.MD }) {
          Button('取消')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.showRefundDialog = false })
          Button('提交申请')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.submitRefund() })
        }
        .width('100%')
        .margin({ top: SPACING.LG })
      }
      .width('100%')
      .padding(SPACING.LG)
      .backgroundColor(COLORS.BG_WHITE)
      .borderRadius({ topLeft: BORDER_RADIUS.XL, topRight: BORDER_RADIUS.XL })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  StatusCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text(getOrderStatusText(this.order!.status, this.order!.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.BIG_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(getOrderStatusColor(this.order!.status, this.order!.escrowStatus ?? 0))
          // 设备端 UiTest 用：断言订单状态文案（待付款/已取消/已完成…）
          .id('order-detail-status')
        if (this.order!.status === 3) {
          Text(this.getEstimatedTime())
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
      }
      .width('100%')

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

      OrderStatusTimeline({ steps: this.getDeliverySteps() })

      // 配送中：骑手位置跟踪动画
      if (this.order!.status === 3) {
        this.RiderTracking()
      }
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  // 骑手配送位置跟踪动画
  @Builder
  RiderTracking() {
    Column({ space: SPACING.SM }) {
      Row() {
        Image($r('app.media.login_rider')).width(18).height(18).objectFit(ImageFit.Contain)
        Text(' 骑手配送中')
          .fontSize(FONT_SIZE.MD)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRIMARY)
        Text(this.getEstimatedTime())
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Stack({ alignContent: Alignment.Start }) {
        // 轨道背景
        Row()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor(COLORS.DIVIDER)

        // 已行进进度
        Row()
          .width(`${Math.round(this.riderProgress * 100)}%`)
          .height(6)
          .borderRadius(3)
          .backgroundColor(COLORS.PRIMARY)

        // 骑手图标（沿轨道移动）
        Image($r('app.media.login_rider')).width(20).height(20).objectFit(ImageFit.Contain)
          .translate({ x: this.riderProgress * (this.trackWidth - 30) })
          .animation({ duration: 250, curve: Curve.Linear })
      }
      .width('100%')
      .height(28)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w: Length = newValue.width
        if (typeof w === 'number') {
          this.trackWidth = w
        } else if (typeof w === 'string') {
          this.trackWidth = Number.parseFloat(w)
        }
      })
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
      }, (item: CartItem) => `${item.goods.id}_${item.specId ?? 0}`)
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
    // 可操作状态：0 待付款可支付/取消；1/2/3 可取消（现状口径：用户取消无商家确认、即时退款）；
    // 4 且托管未结算可确认收货；4 已结算后提供再来一单/去评价
    if (this.order!.status >= 0 && this.order!.status <= 4) {
      if (this.order!.status === 0) {
        Row({ space: SPACING.SM }) {
          ForEach(this.payChannelOptions, (opt: PayChannelOption) => {
            this.PayChannelChip(opt)
          }, (opt: PayChannelOption) => opt.code)
        }
        .width('100%')
        .margin({ bottom: SPACING.MD })
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
            .enabled(!this.paying && !this.manualPaymentChecking)
            .id('order-cancel')
            .onClick(() => { this.showCancelDialog = true })

          Button(this.payButtonText())
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(2)
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.paying && !this.manualPaymentChecking)
            .id('order-pay')
            .onClick(() => { this.payNow() })
        }

        // 待接单/制作中/配送中且托管未处理：取消订单
        if (this.order!.status >= 1 && this.order!.status <= 3 && (this.order!.escrowStatus ?? 0) === 0) {
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

        // status===4 且托管款未结算：确认收货并结算
        if (this.order!.status === 4 && (this.order!.escrowStatus ?? 0) === 0) {
          Button('确认收货并结算')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.showConfirmDialog = true })
        }

        // status===4 且托管未结算、未评价：申请退款（演进项：退款审批，见大纲 7.11）
        if (this.order!.status === 4 && (this.order!.escrowStatus ?? 0) === 0 && this.order!.reviewed === 0) {
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
            .onClick(() => { this.showRefundDialog = true })
        }

        // status===4 (已送达/已完成): 再来一单 + 商品评价
        if (this.order!.status === 4) {
          Button('再来一单')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
            .backgroundColor(Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .borderWidth(1)
            .borderColor(COLORS.PRIMARY)
            .onClick(() => {
              if (this.order !== null) {
                logInfo('Order', `再来一单 orderId=${this.order.id} 商品数=${this.order.items.length}`)
                this.addAgain()
              }
            })
          if ((this.order!.escrowStatus ?? 0) === 1 && this.order!.reviewed === 0) {
            Button('评价商品')
              .attributeModifier(new AppButtonStyle())
              .layoutWeight(1)
              .height(44)
              .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
              .backgroundColor(COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .id('order-review-entry')
              .onClick(() => {
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
        this.showPaymentCode = false
      })
  }
}
