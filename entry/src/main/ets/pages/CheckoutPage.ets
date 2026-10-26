import { AppButtonStyle, AppCardStyle, AppTextAreaStyle, AppTheme } from '../common/theme/AppTheme'
/**
 * 结算页
 * 展示收货地址、商品明细、金额计算、优惠券选择、备注输入
 * 提交订单后生成订单、清空购物车、标记优惠券已用
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText } from '../common/Constants'
import { CartItem, Order, Address, Coupon, StoreItem, User, createEmptyUser } from '../model/Models'
import { createOrderRemote, syncCartRemote, getAllStoresList, syncCouponsRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { LoadingIndicator } from '../components/LoadingIndicator'
import { PageHeader } from '../components/PageHeader'
import { logInfo } from '../service/AppLogger'
import { calculatePayAmount } from '../service/OrderCalculations'
import { getAuthSessionEpoch, getServerNowEpochMs } from '../service/HttpClient'
import { checkoutCents, checkoutCouponReason } from '../service/CheckoutCouponRules'
import { OrderCreateFeedback } from '../service/api/OrdersApi'

interface UnavailableCheckoutCoupon {
  coupon: Coupon
  reason: string
}

interface PendingCheckoutSubmission {
  storeId: number
  items: CartItem[]
  addressId: number
  couponId: number
  remark: string
  checkoutGoodsIds: number[]
  key: string
  expectedPay: number
}

@Entry
@Component
export struct CheckoutPage {
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

  @StorageLink('isLoggedIn') @Watch('onAccountChanged') loggedIn: boolean = false
  @StorageLink('user') @Watch('onAccountChanged') sessionUser: User = createEmptyUser()
  @State checkoutStoreId: number = 0
  @State checkoutStoreIds: number[] = []
  @State storeItems: CartItem[] = []
  @State storeInfo: StoreItem | null = null
  @State currentAddress: Address | null = null
  @StorageLink('couponList') @Watch('onCouponListChanged') couponList: Coupon[] = []
  @State selectedCoupon: Coupon | null = null
  @State availableCoupons: Coupon[] = []
  @State unavailableCoupons: UnavailableCheckoutCoupon[] = []
  @State bestCouponId: number = 0
  @State couponSummary: string = '有 0 张可用，预估最多省 ¥0.00'
  @State couponChoiceMode: string = 'AUTO'
  private couponOptionsReady: boolean = false
  private rejectedCouponId: number = 0
  @State remark: string = ''
  @State showCouponDialog: boolean = false
  @State submitting: boolean = false
  // 每个结算页实例生成一次，重试共用；服务端持久幂等记录可在响应丢失后返回原单。
  // 多店按 storeId 派生子 key，避免把第二家店当作重复提交。
  private submitKey: string = Date.now().toString(36) + '-' + Math.random().toString(36).substring(2, 10)
  @State showOrderFailureDialog: boolean = false
  @State orderFailureMessage: string = ''
  @State createdOrderCount: number = 0
  @State reconciledOrderStatus: string = ''
  @State retryNeedsReview: boolean = false
  @State sessionChanged: boolean = false
  @State submissionUncertain: boolean = false
  private pendingSubmission: PendingCheckoutSubmission | null = null
  private pageActive: boolean = false
  private pageOwnerId: number = 0
  private pageSessionEpoch: number = 0
  private requestVersion: number = 0

  async aboutToAppear(): Promise<void> {
    this.pageActive = true
    logInfo('Page', '进入结算页 CheckoutPage')
    if (!this.loggedIn || (this.sessionUser?.id ?? 0) <= 0) {
      promptAction.showToast({ message: '请先登录后提交订单', duration: 1800 })
      router.back()
      return
    }
    this.pageOwnerId = this.sessionUser?.id ?? 0
    this.pageSessionEpoch = getAuthSessionEpoch()
    const requestVersion: number = this.requestVersion
    this.checkoutStoreId = AppStorage.get<number>('checkoutStoreId') || 0
    const cart: CartItem[] = AppStorage.get<CartItem[]>('cartItems') || []
    const stores: StoreItem[] = getAllStoresList()
    if (this.checkoutStoreId > 0) {
      this.storeItems = cart.filter((c: CartItem) => c.storeId === this.checkoutStoreId)
      this.checkoutStoreIds = [this.checkoutStoreId]
    } else {
      this.storeItems = cart.slice()
      const storeIds: number[] = []
      for (let i = 0; i < cart.length; i++) {
        if (storeIds.indexOf(cart[i].storeId) < 0) {
          storeIds.push(cart[i].storeId)
        }
      }
      this.checkoutStoreIds = storeIds
    }
    this.storeInfo = this.checkoutStoreIds.length > 0
      ? stores.find((s: StoreItem) => s.id === this.checkoutStoreIds[0]) || null
      : null
    this.currentAddress = AppStorage.get<Address>('currentAddress') ?? null
    const storedCoupon: Coupon | null = AppStorage.get<Coupon | null>('selectedCoupon') ?? null
    this.selectedCoupon = storedCoupon
    this.couponChoiceMode = storedCoupon === null ? 'AUTO' : 'COUPON'
    this.couponOptionsReady = true
    this.refreshCouponOptions()
    // 结算权益以服务端为准；拉取失败时 syncCouponsRemote 会保留账号隔离后的本地缓存。
    await syncCouponsRemote(false)
    if (!this.isCheckoutCurrent(requestVersion)) { return }
    this.refreshCouponOptions()
  }

  onPageShow(): void {
    this.pageActive = true
    if (!this.hasCheckoutSession()) {
      if (this.pageOwnerId > 0) { this.clearCheckoutSession() }
      return
    }
    // 从地址管理页返回后，立即刷新本次结算使用的地址。
    if (this.submitting || this.submissionUncertain) { return }
    this.currentAddress = AppStorage.get<Address>('currentAddress') ?? null
    this.refreshCouponOptions()
  }

  onPageHide(): void {
    if (this.pendingSubmission !== null) { this.submissionUncertain = true }
    this.pageActive = false
    this.requestVersion += 1
    this.submitting = false
    this.showCouponDialog = false
    this.showOrderFailureDialog = false
  }

  aboutToDisappear(): void { this.onPageHide() }

  onBackPress(): boolean {
    if (!this.submitting) { return false }
    promptAction.showToast({ message: '订单正在提交，请稍候', duration: 1500 })
    return true
  }

  private hasCheckoutSession(): boolean {
    return this.loggedIn && this.pageOwnerId > 0 && this.pageOwnerId === (this.sessionUser?.id ?? 0)
      && this.pageSessionEpoch === getAuthSessionEpoch()
  }

  private isCheckoutCurrent(requestVersion: number): boolean {
    return this.pageActive && requestVersion === this.requestVersion && this.hasCheckoutSession()
  }

  private onAccountChanged(): void {
    if (this.pageOwnerId > 0 && !this.hasCheckoutSession()) { this.clearCheckoutSession() }
  }

  private clearCheckoutSession(): void {
    this.requestVersion += 1
    this.couponOptionsReady = false
    this.sessionChanged = true
    this.submitting = false
    this.showCouponDialog = false
    this.showOrderFailureDialog = false
    this.currentAddress = null
    this.remark = ''
    this.selectedCoupon = null
    this.availableCoupons = []
    this.unavailableCoupons = []
    this.storeItems = []
    this.checkoutStoreIds = []
    this.storeInfo = null
    this.createdOrderCount = 0
    this.reconciledOrderStatus = ''
    this.retryNeedsReview = false
    this.submissionUncertain = false
    this.pendingSubmission = null
  }

  private openAddressSelector(): void {
    if (this.submitting || this.submissionUncertain || !this.isCheckoutCurrent(this.requestVersion)) { return }
    AppStorage.setOrCreate<boolean>('addressSelectionMode', true)
    router.pushUrl({ url: 'pages/AddressListPage' })
  }

  // ============ 金额计算 ============
  private getGoodsTotalPrice(): number {
    let total: number = 0
    for (let i = 0; i < this.storeItems.length; i++) {
      // 多规格菜品必须用行单价（规格价），goods.price 是规格最低价，用它算会少算金额
      total += (this.storeItems[i].price ?? this.storeItems[i].goods.price) * this.storeItems[i].quantity
    }
    return checkoutCents(total) / 100
  }

  private getDeliveryFee(): number {
    const stores: StoreItem[] = getAllStoresList()
    let total: number = 0
    for (let i = 0; i < this.checkoutStoreIds.length; i++) {
      const store: StoreItem | undefined = stores.find((s: StoreItem) => s.id === this.checkoutStoreIds[i])
      if (store !== undefined) {
        total += store.deliveryFee
      }
    }
    return checkoutCents(total) / 100
  }

  private getStoreGoodsTotalPrice(storeId: number): number {
    let total: number = 0
    const items: CartItem[] = this.storeItems.filter((item: CartItem) => item.storeId === storeId)
    for (let i = 0; i < items.length; i++) {
      total += (items[i].price ?? items[i].goods.price) * items[i].quantity
    }
    return checkoutCents(total) / 100
  }

  private getStoreDeliveryFee(storeId: number): number {
    const store: StoreItem | undefined = getAllStoresList().find((item: StoreItem) => item.id === storeId)
    return store?.deliveryFee ?? 0
  }

  private getCheckoutMinOrder(): number {
    const stores: StoreItem[] = getAllStoresList()
    let minOrder: number = 0
    for (let i = 0; i < this.checkoutStoreIds.length; i++) {
      const store: StoreItem | undefined = stores.find((s: StoreItem) => s.id === this.checkoutStoreIds[i])
      if (store !== undefined && store.minOrder > minOrder) {
        minOrder = store.minOrder
      }
    }
    return minOrder
  }

  private getStoreItems(storeId: number): CartItem[] {
    return this.storeItems.filter((item: CartItem) => item.storeId === storeId)
  }

  private getStoreName(storeId: number): string {
    const stores: StoreItem[] = getAllStoresList()
    const store: StoreItem | undefined = stores.find((s: StoreItem) => s.id === storeId)
    if (store !== undefined) {
      return store.name
    }
    const items: CartItem[] = this.getStoreItems(storeId)
    return items.length > 0 ? items[0].storeName : '\u5e97\u94fa'
  }

  private getCartItemStoreName(item: CartItem): string {
    const itemStoreName: string = item.storeName.trim()
    return itemStoreName !== '' ? itemStoreName : this.getStoreName(item.storeId)
  }

  /** 返回优惠券实际抵扣的单个店铺；0 表示当前结算商品中不可用。 */
  private getCouponStoreId(coupon: Coupon): number {
    for (let i = 0; i < this.checkoutStoreIds.length; i++) {
      const storeId: number = this.checkoutStoreIds[i]
      if (checkoutCouponReason(coupon, storeId, this.getStoreGoodsTotalPrice(storeId),
        this.getStoreDeliveryFee(storeId), getServerNowEpochMs(), this.rejectedCouponId) === '') {
        return storeId
      }
    }
    return 0
  }

  private couponUnavailableReason(coupon: Coupon): string {
    let reason: string = '当前没有可结算商品'
    const couponStoreId: number = coupon.storeId ?? 0
    if (couponStoreId > 0 && this.checkoutStoreIds.indexOf(couponStoreId) < 0) {
      return '仅限指定店铺使用'
    }
    for (let i = 0; i < this.checkoutStoreIds.length; i++) {
      const storeId: number = this.checkoutStoreIds[i]
      if (couponStoreId > 0 && couponStoreId !== storeId) { continue }
      reason = checkoutCouponReason(coupon, storeId, this.getStoreGoodsTotalPrice(storeId),
        this.getStoreDeliveryFee(storeId), getServerNowEpochMs(), this.rejectedCouponId)
      if (reason === '') { return '' }
    }
    return reason
  }

  private getDiscountAmount(): number {
    if (this.selectedCoupon !== null && this.getCouponStoreId(this.selectedCoupon) > 0) {
      return this.selectedCoupon.amount
    }
    return 0
  }

  private getPayAmount(): number {
    return calculatePayAmount(this.getGoodsTotalPrice(), this.getDeliveryFee(), this.getDiscountAmount())
  }

  // ============ 优惠券筛选 ============
  private onCouponListChanged(): void {
    if (this.couponOptionsReady && !this.submitting && !this.submissionUncertain && this.hasCheckoutSession()) {
      // 只有成功同步才会替换 couponList；此时允许服务端最新状态重新参与筛选。
      this.rejectedCouponId = 0
      this.refreshCouponOptions()
    }
  }

  private refreshCouponOptions(): void {
    if (!this.couponOptionsReady || this.submitting || this.submissionUncertain || !this.hasCheckoutSession()) { return }
    const coupons: Coupon[] = Array.isArray(this.couponList) ? this.couponList : []
    const goodsTotal: number = this.getGoodsTotalPrice()
    const deliveryFee: number = this.getDeliveryFee()
    const available: Coupon[] = coupons
      .filter((coupon: Coupon) => this.getCouponStoreId(coupon) > 0)
      .sort((left: Coupon, right: Coupon): number => {
        const leftPay: number = calculatePayAmount(goodsTotal, deliveryFee, left.amount)
        const rightPay: number = calculatePayAmount(goodsTotal, deliveryFee, right.amount)
        if (leftPay !== rightPay) {
          return leftPay - rightPay
        }
        if (left.amount !== right.amount) {
          return right.amount - left.amount
        }
        return left.id - right.id
      })
    this.availableCoupons = available
    this.unavailableCoupons = coupons.filter((coupon: Coupon) => this.getCouponStoreId(coupon) === 0)
      .map((coupon: Coupon): UnavailableCheckoutCoupon => {
        return { coupon: coupon, reason: this.couponUnavailableReason(coupon) }
      })
    const bestCoupon: Coupon | null = available.length > 0 ? available[0] : null
    this.bestCouponId = bestCoupon === null ? 0 : bestCoupon.id
    const maxSaving: number = bestCoupon === null ? 0 : bestCoupon.amount
    this.couponSummary = `有 ${available.length} 张可用，预估最多省 ¥${maxSaving.toFixed(2)}`

    let currentCoupon: Coupon | null = null
    if (this.selectedCoupon !== null) {
      const selectedCouponId: number = this.selectedCoupon.id
      currentCoupon = available.find((coupon: Coupon) => coupon.id === selectedCouponId) ?? null
    }
    if (this.couponChoiceMode === 'COUPON' && this.selectedCoupon !== null && currentCoupon === null) {
      // 缓存券已失效或不适用于当前店铺时，恢复为自动推荐；只有用户明确“不使用”才保持空选。
      this.couponChoiceMode = 'AUTO'
    }
    if (this.couponChoiceMode === 'AUTO') {
      currentCoupon = bestCoupon
    } else if (this.couponChoiceMode === 'NONE') {
      currentCoupon = null
    }
    this.selectedCoupon = currentCoupon
    // 自动优选仅属于当前结算对象，不伪装成用户的显式选择带到下次结算。
    AppStorage.setOrCreate<Coupon | null>('selectedCoupon', this.couponChoiceMode === 'AUTO' ? null : currentCoupon)
  }

  // ============ 优惠券选择 ============
  private selectCoupon(coupon: Coupon | null): void {
    if (this.submitting || this.submissionUncertain || !this.isCheckoutCurrent(this.requestVersion)) { return }
    if (coupon !== null && this.getCouponStoreId(coupon) === 0) {
      promptAction.showToast({ message: this.couponUnavailableReason(coupon), duration: 2500 })
      this.refreshCouponOptions()
      return
    }
    this.couponChoiceMode = coupon === null ? 'NONE' : 'COUPON'
    this.selectedCoupon = coupon
    this.retryNeedsReview = false
    AppStorage.setOrCreate<Coupon | null>('selectedCoupon', coupon)
    this.showCouponDialog = false
  }

  private couponRowBg(coupon: Coupon | null): ResourceColor {
    if (coupon !== null) {
      return this.selectedCoupon !== null && this.selectedCoupon.id === coupon.id ? COLORS.TAG_BG : COLORS.BG_PRIMARY
    }
    return this.couponChoiceMode === 'NONE' ? COLORS.TAG_BG : COLORS.BG_PRIMARY
  }

  // ============ 提交订单 ============
  private submitOrder(): void {
    if (!this.isCheckoutCurrent(this.requestVersion)) {
      this.clearCheckoutSession()
      return
    }
    if (this.submitting) {
      promptAction.showToast({ message: '订单正在提交，请稍候', duration: 1500 })
      return
    }
    if (this.submissionUncertain && this.pendingSubmission !== null) {
      this.submitting = true
      this.showOrderFailureDialog = false
      this.requestVersion += 1
      this.doSubmitOrder(this.requestVersion)
      return
    }
    const previousCouponId: number = this.selectedCoupon?.id ?? 0
    const previousPayAmount: number = this.getPayAmount()
    // 提交前再校验一次缓存券的有效期与当前单店门槛；变化时必须让用户重新核对。
    this.refreshCouponOptions()
    const currentCouponId: number = this.selectedCoupon?.id ?? 0
    const currentPayAmount: number = this.getPayAmount()
    if (previousCouponId !== currentCouponId || Math.abs(previousPayAmount - currentPayAmount) >= 0.01) {
      const message: string = currentPayAmount > previousPayAmount + 0.009
        ? `优惠条件已变化，应付从 ¥${previousPayAmount.toFixed(2)} 调整为 ¥${currentPayAmount.toFixed(2)}，请核对后再次提交`
        : `优惠方案已更新，应付 ¥${currentPayAmount.toFixed(2)}，请核对后再次提交`
      promptAction.showToast({ message: message, duration: 3000 })
      return
    }
    // 起送价以服务端下单校验为唯一权威：多店结算时服务端按店逐个判断，
    // 前端「所有店合计 vs 最大起送价」的合计口径与之不一致，这里不再前置拦截，
    // 避免出现「页面显示金额够、提交却被拒」的自相矛盾提示
    if (this.currentAddress === null) {
      promptAction.showToast({ message: '请先添加收货地址' })
      return
    }
    if (this.currentAddress.id <= 0) {
      promptAction.showToast({ message: '该定位地址尚未保存，请先在地址管理中保存' })
      return
    }
    this.submitting = true
    this.showCouponDialog = false
    this.retryNeedsReview = false
    logInfo('Checkout', `开始统一提交订单 店铺数=${this.checkoutStoreIds.length} 商品数=${this.storeItems.length} 应付=${this.getPayAmount()} 优惠=${this.getDiscountAmount()}`)
    // 服务端创建待付款订单并占用库存、优惠券，支付成功后才扣款。
    this.requestVersion += 1
    this.doSubmitOrder(this.requestVersion)
  }

  // 调后端创建订单并跳转
  private async doSubmitOrder(requestVersion: number): Promise<void> {
    const addressId: number = this.currentAddress?.id ?? 0
    const remark: string = this.remark
    const storeIds: number[] = this.checkoutStoreIds.slice()
    const submitItems: CartItem[] = this.storeItems.map((item: CartItem): CartItem => {
      return { goods: { id: item.goods.id, name: item.goods.name, description: item.goods.description,
        price: item.goods.price, image: item.goods.image, categoryId: item.goods.categoryId,
        sales: item.goods.sales, rating: item.goods.rating },
        quantity: item.quantity, storeId: item.storeId, storeName: item.storeName,
        specId: item.specId ?? 0, specName: item.specName ?? '', price: item.price ?? item.goods.price,
        stock: item.stock }
    })
    const submittedCouponId: number = this.selectedCoupon?.id ?? 0
    const submittedCouponAmount: number = this.selectedCoupon?.amount ?? 0
    let firstOrder: Order | null = null
    let couponUsed: boolean = false
    const checkoutGoodsIds: number[] = []
    for (let i = 0; i < submitItems.length; i++) {
      checkoutGoodsIds.push(submitItems[i].goods.id)
    }
    // 服务端活动价（如限时秒杀）可能低于本地预估，累计差额用于明确告知用户
    let activitySaved: number = 0
    const stores: StoreItem[] = getAllStoresList()
    const couponStoreId: number = this.selectedCoupon === null ? 0 : this.getCouponStoreId(this.selectedCoupon)
    try {
      for (let i = 0; i < storeIds.length; i++) {
        if (!this.isCheckoutCurrent(requestVersion)) { return }
        const storeId: number = storeIds[i]
        const items: CartItem[] = submitItems.filter((item: CartItem) => item.storeId === storeId)
        const groupTotal: number = this.getStoreGoodsTotalPrice(storeId)
        const couponCanApply: boolean = submittedCouponId > 0
          && !couponUsed
          && couponStoreId === storeId
        const couponId: number = couponCanApply ? submittedCouponId : 0
        const store: StoreItem | undefined = stores.find((item: StoreItem) => item.id === storeId)
        const snapshot: PendingCheckoutSubmission = this.pendingSubmission ?? {
          storeId: storeId, items: items, addressId: addressId, couponId: couponId, remark: remark,
          checkoutGoodsIds: checkoutGoodsIds.slice(), key: `${this.submitKey}-${storeId}`,
          expectedPay: checkoutCents(groupTotal + (store?.deliveryFee ?? 0)
            - (couponId > 0 ? submittedCouponAmount : 0)) / 100
        }
        if (snapshot.storeId !== storeId) { throw new Error('待核对订单与当前店铺不一致') }
        this.pendingSubmission = snapshot
        const feedback: OrderCreateFeedback = { failureConfirmed: false, message: '' }
        const serverOrder: Order | null = await createOrderRemote(snapshot.storeId, snapshot.items,
          snapshot.addressId, snapshot.couponId, snapshot.remark, snapshot.checkoutGoodsIds, '', snapshot.key,
          'DELIVERY', [], feedback)
        if (!this.isCheckoutCurrent(requestVersion)) { return }
        if (serverOrder === null) {
          const errorMessage: string = feedback.message || getLastRemoteErrorMessage()
          if (!feedback.failureConfirmed) {
            this.submissionUncertain = true
            this.orderFailureMessage = `${this.createdOrderCount > 0 ? `已核对${this.createdOrderCount}笔订单；` : ''}`
              + `当前店铺提交结果尚未确认。${errorMessage === '' ? '' : `${errorMessage}。`}`
              + '地址、备注和优惠已锁定，请按原信息核对提交结果，系统会返回原订单，避免重复下单。'
            this.showOrderFailureDialog = true
            return
          }
          this.pendingSubmission = null
          this.submissionUncertain = false
          let cartSynced: boolean = true
          if (this.createdOrderCount > 0) {
            cartSynced = await syncCartRemote(false)
            if (!this.isCheckoutCurrent(requestVersion)) { return }
          }
          const couponNeedsRefresh: boolean = snapshot.couponId > 0 || couponUsed
          if (couponNeedsRefresh) {
            const rejectedId: number = snapshot.couponId > 0 ? snapshot.couponId : submittedCouponId
            this.rejectedCouponId = rejectedId
            if (this.couponChoiceMode !== 'NONE') {
              this.couponChoiceMode = 'AUTO'
            }
            this.selectedCoupon = null
            AppStorage.setOrCreate<Coupon | null>('selectedCoupon', null)
            await syncCouponsRemote(false)
            if (!this.isCheckoutCurrent(requestVersion)) { return }
          }
          this.submitting = false
          this.refreshCouponOptions()
          this.retryNeedsReview = this.createdOrderCount > 0 && couponNeedsRefresh
          const reason: string = errorMessage === ''
            ? '请检查起送价、账户余额、收货地址或网络连接'
            : errorMessage
          let failureMessage: string = this.createdOrderCount > 0
            ? `已确认${this.createdOrderCount}笔订单，可在“我的订单”中核对状态；当前店铺“${this.getStoreName(storeId)}”提交失败：${reason}`
            : `提交订单失败：${reason}`
          if (!cartSynced) {
            failureMessage += '；已创建订单的购物车状态待同步，请勿重复结算'
          }
          this.orderFailureMessage = failureMessage
          this.showOrderFailureDialog = true
          return
        }
        // 成交金额以服务端为准（秒杀等在服务端生效），差额主动提示，避免用户以为结算页金额算错
        const expectedPay: number = snapshot.expectedPay
        this.pendingSubmission = null
        this.submissionUncertain = false
        if (serverOrder.payAmount < expectedPay - 0.01) {
          activitySaved += expectedPay - serverOrder.payAmount
        }
        if (firstOrder === null) {
          firstOrder = serverOrder
        }
        if (serverOrder.status !== 0) {
          this.reconciledOrderStatus = getOrderStatusText(serverOrder.status, serverOrder.escrowStatus)
        }
        this.createdOrderCount += 1
        // 逐店记录已确认结果。页面中断后，剩余店铺仍使用原 key 对账，已成功店铺不再提交或计数。
        const remainingStoreIds: number[] = storeIds.slice(i + 1)
        this.checkoutStoreIds = remainingStoreIds
        this.storeItems = submitItems.filter((item: CartItem) => remainingStoreIds.indexOf(item.storeId) >= 0)
        this.checkoutStoreId = remainingStoreIds.length === 1 ? remainingStoreIds[0] : 0
        this.storeInfo = remainingStoreIds.length > 0
          ? stores.find((store: StoreItem) => store.id === remainingStoreIds[0]) ?? null : null
        if (snapshot.couponId > 0) {
          couponUsed = true
        }
      }
      if (firstOrder === null) {
        this.submitting = false
        this.orderFailureMessage = '购物车没有可结算的商品'
        this.showOrderFailureDialog = true
        return
      }

      // 创建订单的事务已按本次商品数量更新购物车；这里只读取服务端权威状态，
      // 避免响应等待期间新加购的同菜品、同规格被客户端整行删除。
      const cartSynced: boolean = await syncCartRemote(false)
      if (!this.isCheckoutCurrent(requestVersion)) { return }

      // 后端已处理优惠券状态，重新同步真实优惠券列表
      if (submittedCouponId > 0 || couponUsed) {
        await syncCouponsRemote(false)
        if (!this.isCheckoutCurrent(requestVersion)) { return }
      }

      // 存入 currentOrder 供订单详情页读取
      AppStorage.setOrCreate<number>('currentOrderId', firstOrder.id)
      AppStorage.setOrCreate<Order>('currentOrder', firstOrder)
      // 重置已选优惠券
      AppStorage.setOrCreate<Coupon | null>('selectedCoupon', null)
      this.selectedCoupon = null
      this.checkoutStoreId = 0
      this.checkoutStoreIds = []
      this.storeItems = []
      this.storeInfo = null
      this.submitting = false
      const submittedCount: number = this.createdOrderCount
      const cartMessage: string = cartSynced ? '' : '；购物车状态待同步，请勿重复结算'
      promptAction.showToast({
        message: this.reconciledOrderStatus !== ''
          ? (submittedCount > 1
            ? `已核对到${submittedCount}笔订单，其中原订单当前状态：${this.reconciledOrderStatus}，请查看订单列表${cartMessage}`
            : `已核对到原订单，当前状态：${this.reconciledOrderStatus}，请查看详情${cartMessage}`)
          : submittedCount > 1
          ? (activitySaved > 0.01
            ? `已提交${submittedCount}笔订单，比预估少付 ¥${activitySaved.toFixed(2)}，请分别完成支付${cartMessage}`
            : `已提交${submittedCount}笔订单，请分别完成支付${cartMessage}`)
          : (activitySaved > 0.01
            ? `订单提交成功，已按活动价结算，比预估少付 ¥${activitySaved.toFixed(2)}，请在 15 分钟内完成支付${cartMessage}`
            : `订单提交成功，请在 15 分钟内完成支付${cartMessage}`),
        duration: 3000
      })
      if (submittedCount > 1) {
        AppStorage.setOrCreate<number>('orderFilterStatus', this.reconciledOrderStatus === '' ? 0 : -1)
        router.replaceUrl({ url: 'pages/OrderListPage' })
      } else {
        router.replaceUrl({ url: 'pages/OrderDetailPage' })
      }
    } catch (_) {
      if (!this.isCheckoutCurrent(requestVersion)) { return }
      this.submissionUncertain = this.pendingSubmission !== null
      this.orderFailureMessage = this.createdOrderCount > 0
        ? `已核对${this.createdOrderCount}笔订单，请到“我的订单”查看；剩余店铺可使用本页重试，备注和地址已保留`
        : '提交结果暂未确认，请检查网络后在本页重试，系统会核对原订单；备注和地址已保留'
      this.showOrderFailureDialog = true
    } finally {
      if (this.isCheckoutCurrent(requestVersion)) { this.submitting = false }
    }
  }

  build() {
    Stack() {
      Column() {
        this.NavBar()

        if (this.storeItems.length === 0) {
          this.EmptyState()
        } else {
          Scroll() {
            Column({ space: SPACING.SM }) {
              if (this.submissionUncertain) {
                Text('上次提交结果尚未确认，地址、备注和优惠已锁定。请按原信息核对提交结果。')
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY)
                  .width('100%').padding(SPACING.MD)
                  .id('checkout-submission-uncertain')
              }
              this.AddressCard()
              this.StoreAndItemsCard()
              this.CouponCard()
              this.DeliveryTimeCard()
              this.AmountDetailCard()
              this.RemarkCard()
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XL })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          this.SubmitBar()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 提交订单加载遮罩
      if (this.submitting) {
        Column() {
          LoadingIndicator({ text: '正在提交订单…' })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.3)')
      }

      if (this.showOrderFailureDialog) {
        this.OrderFailureDialog()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showCouponDialog, this.CouponDialog(), {
      height: SheetSize.MEDIUM,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      title: { title: '选择优惠券' },
      showClose: true,
      dragBar: true,
      backgroundColor: AppTheme.CARD,
      radius: { topLeft: AppTheme.SHEET_RADIUS, topRight: AppTheme.SHEET_RADIUS }
    })
  }

  @Builder
  NavBar() {
    PageHeader({ title: '确认订单', backId: 'checkout-back', onBack: () => {
      if (!this.onBackPress()) { router.back() }
    } })
  }

  @Builder
  EmptyState() {
    Column() {
      Image($r('app.media.home_nav_cart')).width(60).height(60).objectFit(ImageFit.Contain)
      Text(this.sessionChanged ? '登录状态已变化，请返回购物车重新结算'
        : this.createdOrderCount > 0 ? `已核对到${this.createdOrderCount}笔订单` : '暂无结算商品')
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ top: SPACING.MD })
        .textAlign(TextAlign.Center)
      if (!this.sessionChanged && this.createdOrderCount > 0) {
        Button('查看订单')
          .attributeModifier(new AppButtonStyle())
          .height(44)
          .margin({ top: SPACING.MD })
          .id('checkout-created-orders')
          .onClick(() => {
            if (!this.isCheckoutCurrent(this.requestVersion)) { return }
            AppStorage.setOrCreate<number>('orderFilterStatus', this.reconciledOrderStatus === '' ? 0 : -1)
            router.replaceUrl({ url: 'pages/OrderListPage' })
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  AddressCard() {
    Row() {
Image($r('app.media.home_location')).width(FONT_SIZE.XL).height(FONT_SIZE.XL).objectFit(ImageFit.Contain)
      if (this.currentAddress !== null) {
        Column({ space: SPACING.XS }) {
          Row() {
            Text(this.currentAddress.name)
              .fontSize(FONT_SIZE.LG)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Text(this.currentAddress.phone)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .margin({ left: SPACING.MD })
          }
          Text(`${this.currentAddress.address} ${this.currentAddress.detail}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .margin({ left: SPACING.MD })
        .alignItems(HorizontalAlign.Start)
      } else {
        Text('请添加收货地址')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
          .layoutWeight(1)
          .margin({ left: SPACING.MD })
      }
      Text('›')
        .fontSize(FONT_SIZE.XL)
        .fontColor(COLORS.TEXT_HINT)
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
    .alignItems(VerticalAlign.Center)
    .enabled(!this.submitting && !this.submissionUncertain)
    .onClick(() => { this.openAddressSelector() })
  }

  @Builder
  StoreAndItemsCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Image($r('app.media.login_store')).width(FONT_SIZE.LG).height(FONT_SIZE.LG).objectFit(ImageFit.Contain)
        Text(this.checkoutStoreId > 0 && this.storeInfo !== null ? this.storeInfo.name : '\u5168\u90e8\u5e97\u94fa\u5546\u54c1')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      ForEach(this.storeItems, (item: CartItem) => {
        Row() {
          Column({ space: 2 }) {
            Text(this.getCartItemStoreName(item))
              .fontSize(FONT_SIZE.XS)
              .fontColor(COLORS.PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(item.goods.name)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            // 多规格：结算页展示所选规格，避免同菜品多规格被误认为重复行
            if ((item.specName ?? '') !== '') {
              Text(`规格：${item.specName}`)
                .fontSize(FONT_SIZE.XS)
                .fontColor(COLORS.TEXT_HINT)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
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
        .padding({ top: SPACING.XS, bottom: SPACING.XS })
      }, (item: CartItem) => `${item.goods.id}_${item.specId ?? 0}`)
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  CouponCard() {
    Row() {
      Image($r('app.media.home_coupon')).width(FONT_SIZE.MD).height(FONT_SIZE.MD).objectFit(ImageFit.Contain)
      Column({ space: 2 }) {
        Text('优惠券')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text(this.couponSummary)
          .id('checkout-coupon-summary')
          .fontSize(FONT_SIZE.XS)
          .fontColor(COLORS.TEXT_HINT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
        .layoutWeight(1)
        .margin({ left: SPACING.SM })
        .alignItems(HorizontalAlign.Start)
      if (this.getDiscountAmount() > 0 && this.selectedCoupon !== null) {
        // 券 amount 缺失时 toFixed 会渲染成 ¥NaN；与项目其余兜底口径统一
        Text(`-¥${(Number.isFinite(this.selectedCoupon.amount) ? this.selectedCoupon.amount : 0).toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
      } else {
        Text(this.couponChoiceMode === 'NONE'
          ? '不使用'
          : (this.availableCoupons.length === 0 ? '暂无可用' : '请选择'))
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
      }
      Text(' ›')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ left: SPACING.XS })
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
    .alignItems(VerticalAlign.Center)
    .enabled(!this.submitting && !this.submissionUncertain)
    .onClick(() => {
      if (!this.submitting && !this.submissionUncertain && this.isCheckoutCurrent(this.requestVersion)) {
        this.showCouponDialog = true
      }
    })
  }

  @Builder
  AmountDetailCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('商品总价')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(`¥${this.getGoodsTotalPrice().toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')

      Row() {
        Text('配送费')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(`¥${this.getDeliveryFee().toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')

      if (this.getDiscountAmount() > 0) {
        Row() {
          Text('优惠')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .layoutWeight(1)
          Text(`-¥${this.getDiscountAmount().toFixed(2)}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
        }
        .width('100%')
      }
      Text('以上为预估金额。店铺活动与优惠券叠加后可能需要换券，提交后请核对订单实际金额再付款。')
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        .id('checkout-estimate-policy')
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  DeliveryTimeCard() {
    Column({ space: SPACING.SM }) {
      Text('送达时间')
        .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
      Text('立即送达')
        .id('checkout-delivery-immediate')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRIMARY)
        .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.XS, bottom: SPACING.XS })
        .borderRadius(BORDER_RADIUS.ROUND)
        .alignSelf(ItemAlign.Start)
      Text('当前仅支持立即配送')
        .id('checkout-delivery-policy')
        .fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.TEXT_HINT)
        .width('100%')
      Text('送达方式')
        .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
      Text('外卖配送')
        .fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRIMARY)
        .padding({ left: SPACING.SM, right: SPACING.SM, top: 4, bottom: 4 })
        .borderRadius(BORDER_RADIUS.SM)
        .alignSelf(ItemAlign.Start)
    }
      .attributeModifier(new AppCardStyle())
    .width('100%').padding(SPACING.LG)
  }

  @Builder
  RemarkCard() {
    Column({ space: SPACING.SM }) {
      Text('订单备注')
        .fontSize(FONT_SIZE.MD)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
      TextArea({ placeholder: '例如：少辣、不要香菜（选填，最多50字）', text: this.remark })
        .attributeModifier(new AppTextAreaStyle())
        .width('100%')
        .height(80)
        .maxLength(50)
        .enabled(!this.submitting && !this.submissionUncertain)
        .id('checkout-remark')
        .onChange((value: string) => {
          if (!this.submitting && !this.submissionUncertain) { this.remark = value }
        })
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SubmitBar() {
    Row() {
      Row() {
        Text('预估应付')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(`¥${this.getPayAmount().toFixed(2)}`)
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.PRICE_RED)
          .fontWeight(FontWeight.Bold)
          .margin({ left: SPACING.XS })
          // 设备端 UiTest 用：断言结算应付金额（组件匹配器比坐标点击可靠）
          .id('checkout-pay-amount')
      }
      .layoutWeight(1)

      Button(this.submitting ? '提交中…' : this.submissionUncertain ? '核对上次提交结果' : '提交订单')
        .attributeModifier(new AppButtonStyle())
        .height(44)
        .fontSize(FONT_SIZE.LG).fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .id('checkout-submit')
        .enabled(!this.submitting && !this.sessionChanged)
        .onClick(() => { this.submitOrder() })
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })
    .backgroundColor(COLORS.BG_WHITE)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  CouponDialog() {
      Column() {
          // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
          List({ space: SPACING.SM }) {
            ListItem() {
              Text('按当前商品与配送费预估，最终以服务端计价为准')
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            }
            ListItem() {
              this.CouponOption(null)
            }
            if (this.availableCoupons.length === 0) {
              ListItem() {
                Text('当前暂无可用优惠券')
                  .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY)
              }
            }
            ForEach(this.availableCoupons, (coupon: Coupon) => {
              ListItem() {
                this.CouponOption(coupon)
              }
            }, (coupon: Coupon) => `${coupon.id}`)
            if (this.unavailableCoupons.length > 0) {
              ListItem() {
                Text('本次不可用')
                  .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(COLORS.TEXT_PRIMARY)
                  .padding({ top: SPACING.MD, bottom: SPACING.XS })
              }
              ForEach(this.unavailableCoupons, (item: UnavailableCheckoutCoupon) => {
                ListItem() { this.UnavailableCouponOption(item) }
              }, (item: UnavailableCheckoutCoupon) => `unavailable-${item.coupon.id}-${item.reason}`)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .padding(SPACING.LG)
  }

  @Builder
  OrderFailureDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.55)')
        .onClick(() => { this.showOrderFailureDialog = false })

      Column({ space: SPACING.MD }) {
        Text(this.submissionUncertain ? '提交结果待核对' : this.createdOrderCount > 0 ? '部分订单已确认' : '提交订单失败')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)

        Text('失败原因')
          .width('100%')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
          .textAlign(TextAlign.Start)

        Scroll() {
          Text(this.orderFailureMessage)
            .width('100%')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .height(72)
        .scrollBar(BarState.Off)

        if (this.createdOrderCount > 0) {
          Button('查看订单')
            .attributeModifier(new AppButtonStyle())
            .width('100%')
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .id('checkout-partial-orders')
            .onClick(() => {
              this.showOrderFailureDialog = false
              AppStorage.setOrCreate<number>('orderFilterStatus', this.reconciledOrderStatus === '' ? 0 : -1)
              router.pushUrl({ url: 'pages/OrderListPage' })
            })
          Button(this.submissionUncertain ? '按原信息核对提交结果' : '重试剩余店铺')
            .attributeModifier(new AppButtonStyle())
            .width('100%')
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
            .backgroundColor(COLORS.TAG_BG)
            .borderRadius(BORDER_RADIUS.ROUND)
            .id('checkout-partial-retry')
            .onClick(() => {
              this.showOrderFailureDialog = false
              if (this.retryNeedsReview) {
                this.retryNeedsReview = false
                promptAction.showToast({
                  message: `优惠方案已更新，应付 ¥${this.getPayAmount().toFixed(2)}，请核对后再次提交`,
                  duration: 3000
                })
                return
              }
              this.submitOrder()
            })
        } else {
          Button(this.submissionUncertain ? '按原信息核对提交结果' : '知道了')
            .attributeModifier(new AppButtonStyle())
            .width('100%')
            .height(44)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => {
              this.showOrderFailureDialog = false
              if (this.submissionUncertain) { this.submitOrder() }
            })
        }
      }
        .attributeModifier(new AppCardStyle())
      .width('84%').constraintSize({ maxWidth: 460 })
      .padding(SPACING.XL)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  @Builder
  CouponOption(coupon: Coupon | null) {
    Row() {
      Column() {
        if (coupon !== null) {
          Text(`¥${coupon.amount.toFixed(2)}`)
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.ON_PRIMARY)
        } else {
          Text('不使用')
            .fontSize(FONT_SIZE.SM)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.ON_PRIMARY)
        }
      }
      .width(80)
      .height(80)
      .backgroundColor(COLORS.PRIMARY)
      .borderRadius(BORDER_RADIUS.MD)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: SPACING.XS }) {
        if (coupon !== null) {
          Row({ space: SPACING.XS }) {
            Text(coupon.condition)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_PRIMARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (coupon.id === this.bestCouponId) {
              Text('预估最省')
                .fontSize(FONT_SIZE.XS)
                .fontColor(COLORS.PRIMARY)
                .backgroundColor(COLORS.TAG_BG)
                .borderRadius(BORDER_RADIUS.SM)
                .padding({ left: SPACING.XS, right: SPACING.XS, top: 2, bottom: 2 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Text(`商品满 ¥${coupon.minOrder.toFixed(2)} 可用`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        } else {
          Text('不使用优惠券')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
      }
      .layoutWeight(1)
      .margin({ left: SPACING.MD })
      .alignItems(HorizontalAlign.Start)

      if (coupon !== null && this.selectedCoupon !== null && this.selectedCoupon.id === coupon.id) {
        Text('✓')
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.PRIMARY)
      } else if (coupon === null && this.couponChoiceMode === 'NONE') {
        Text('✓')
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.PRIMARY)
      }
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(this.couponRowBg(coupon))
    .borderRadius(BORDER_RADIUS.MD)
    .alignItems(VerticalAlign.Center)
    .enabled(!this.submitting && !this.submissionUncertain)
    .onClick(() => { this.selectCoupon(coupon) })
  }

  @Builder
  UnavailableCouponOption(item: UnavailableCheckoutCoupon) {
    Column({ space: SPACING.XS }) {
      Text(item.coupon.condition)
        .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
      Text(item.reason)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        .id(`checkout-coupon-unavailable-${item.coupon.id}`)
    }
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .alignItems(HorizontalAlign.Start)
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_PRIMARY)
    .borderRadius(BORDER_RADIUS.MD)
    .accessibilityDescription(`不可用，${item.coupon.condition}，${item.reason}`)
  }
}
