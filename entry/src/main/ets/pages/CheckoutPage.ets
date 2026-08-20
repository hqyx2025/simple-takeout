/**
 * 结算页
 * 展示收货地址、商品明细、金额计算、优惠券选择、备注输入
 * 提交订单后生成订单、清空购物车、标记优惠券已用
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { CartItem, Order, Address, Coupon, StoreItem } from '../model/Models'
import { createOrderRemote, deleteCartItemsRemote, syncCartRemote, getAllStoresList, syncCouponsRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { LoadingIndicator } from '../components/LoadingIndicator'
import { logInfo } from '../service/AppLogger'
import { calculatePayAmount } from '../service/OrderCalculations'
import { webview } from '@kit.ArkWeb'

@Entry
@Component
export struct CheckoutPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State checkoutStoreId: number = 0
  @State checkoutStoreIds: number[] = []
  @State storeItems: CartItem[] = []
  @State storeInfo: StoreItem | null = null
  @State currentAddress: Address | null = null
  @State selectedCoupon: Coupon | null = null
  @State remark: string = ''
  @State showCouponDialog: boolean = false
  @State submitting: boolean = false
  @State showOrderFailureDialog: boolean = false
  @State orderFailureMessage: string = ''
  private orderFailureWebController: webview.WebviewController = new webview.WebviewController()

  aboutToAppear() {
    logInfo('Page', '进入结算页 CheckoutPage')
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录后提交订单', duration: 1800 })
      router.back()
      return
    }
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
    this.selectedCoupon = AppStorage.get<Coupon | null>('selectedCoupon') ?? null
  }

  onPageShow(): void {
    // 从地址管理页返回后，立即刷新本次结算使用的地址。
    this.currentAddress = AppStorage.get<Address>('currentAddress') ?? null
  }

  private openAddressSelector(): void {
    AppStorage.setOrCreate<boolean>('addressSelectionMode', true)
    router.pushUrl({ url: 'pages/AddressListPage' })
  }

  // ============ 金额计算 ============
  private getGoodsTotalPrice(): number {
    let total: number = 0
    for (let i = 0; i < this.storeItems.length; i++) {
      total += this.storeItems[i].goods.price * this.storeItems[i].quantity
    }
    return total
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
    return total
  }

  private getStoreGoodsTotalPrice(storeId: number): number {
    let total: number = 0
    const items: CartItem[] = this.storeItems.filter((item: CartItem) => item.storeId === storeId)
    for (let i = 0; i < items.length; i++) {
      total += items[i].goods.price * items[i].quantity
    }
    return total
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

  private getDiscountAmount(): number {
    if (this.selectedCoupon !== null) {
      return this.selectedCoupon.amount
    }
    return 0
  }

  private getPayAmount(): number {
    return calculatePayAmount(this.getGoodsTotalPrice(), this.getDeliveryFee(), this.getDiscountAmount())
  }

  // ============ 优惠券筛选 ============
  private getAvailableCoupons(): Coupon[] {
    const coupons: Coupon[] = AppStorage.get<Coupon[]>('couponList') || []
    const total: number = this.getGoodsTotalPrice()
    return coupons.filter((c: Coupon) => !c.used && c.minOrder <= total)
  }

  // ============ 时间格式化 YYYY-MM-DD HH:mm:ss ============
  private formatCurrentTime(): string {
    const date: Date = new Date()
    const y: number = date.getFullYear()
    const m: string = String(date.getMonth() + 1).padStart(2, '0')
    const d: string = String(date.getDate()).padStart(2, '0')
    const h: string = String(date.getHours()).padStart(2, '0')
    const min: string = String(date.getMinutes()).padStart(2, '0')
    const s: string = String(date.getSeconds()).padStart(2, '0')
    return `${y}-${m}-${d} ${h}:${min}:${s}`
  }

  // ============ 优惠券选择 ============
  private selectCoupon(coupon: Coupon | null): void {
    this.selectedCoupon = coupon
    AppStorage.setOrCreate<Coupon | null>('selectedCoupon', coupon)
    this.showCouponDialog = false
  }

  // ============ 提交订单 ============
  private submitOrder(): void {
    if (this.submitting) {
      promptAction.showToast({ message: '订单正在提交，请稍候', duration: 1500 })
      return
    }
    const checkoutTotal: number = this.getGoodsTotalPrice()
    const checkoutMinOrder: number = this.getCheckoutMinOrder()
    if (checkoutTotal < checkoutMinOrder) {
      const shortage: number = checkoutMinOrder - checkoutTotal
      promptAction.showToast({
        message: `未达到本次订单起送价，还差¥${shortage.toFixed(2)}`,
        duration: 2200
      })
      return
    }
    if (this.currentAddress === null) {
      promptAction.showToast({ message: '请先添加收货地址' })
      return
    }
    if (this.currentAddress.id <= 0) {
      promptAction.showToast({ message: '该定位地址尚未保存，请先在地址管理中保存' })
      return
    }
    this.submitting = true
    logInfo('Checkout', `开始统一提交订单 店铺数=${this.checkoutStoreIds.length} 商品数=${this.storeItems.length} 应付=${this.getPayAmount()} 优惠=${this.getDiscountAmount()}`)
    // 调用后端下单（余额扣减+优惠券抵扣由服务端完成）
    this.doSubmitOrder()
  }

  // 调后端创建订单并跳转
  private async doSubmitOrder(): Promise<void> {
    const address: Address = this.currentAddress as Address
    let firstOrder: Order | null = null
    let couponUsed: boolean = false
    const checkoutGoodsIds: number[] = []
    for (let i = 0; i < this.storeItems.length; i++) {
      checkoutGoodsIds.push(this.storeItems[i].goods.id)
    }
    const successfulGoodsIds: number[] = []
    for (let i = 0; i < this.checkoutStoreIds.length; i++) {
      const storeId: number = this.checkoutStoreIds[i]
      const items: CartItem[] = this.getStoreItems(storeId)
      const groupTotal: number = this.getStoreGoodsTotalPrice(storeId)
      const couponCanApply: boolean = this.selectedCoupon !== null
        && !couponUsed
        && (this.selectedCoupon.storeId === undefined || this.selectedCoupon.storeId === 0 || this.selectedCoupon.storeId === storeId)
        && groupTotal >= this.selectedCoupon.minOrder
      const couponId: number = couponCanApply && this.selectedCoupon !== null ? this.selectedCoupon.id : 0
      const serverOrder: Order | null = await createOrderRemote(storeId, items, address.id, couponId, this.remark, checkoutGoodsIds)
      if (serverOrder === null) {
        if (successfulGoodsIds.length > 0) {
          const successfulCartCleared: boolean = await deleteCartItemsRemote(successfulGoodsIds)
          if (!successfulCartCleared) {
            await syncCartRemote()
          }
        }
        this.submitting = false
        const errorMessage: string = getLastRemoteErrorMessage()
        const failureMessage: string = errorMessage === ''
          ? '提交订单失败，请检查起送价、账户余额、收货地址或网络连接'
          : `提交订单失败：${errorMessage}`
        this.orderFailureMessage = failureMessage
        this.showOrderFailureDialog = true
        return
      }
      if (firstOrder === null) {
        firstOrder = serverOrder
      }
      if (couponId > 0) {
        couponUsed = true
      }
      for (let j = 0; j < items.length; j++) {
        successfulGoodsIds.push(items[j].goods.id)
      }
    }
    if (firstOrder === null) {
      this.submitting = false
      this.orderFailureMessage = '购物车没有可结算的商品'
      this.showOrderFailureDialog = true
      return
    }

    const cartCleared: boolean = await deleteCartItemsRemote(checkoutGoodsIds)
    if (!cartCleared) {
      await syncCartRemote()
    }

    // 后端已处理优惠券状态，重新同步真实优惠券列表
    if (this.selectedCoupon !== null) {
      await syncCouponsRemote()
    }

    // 存入 currentOrder 供订单详情页读取
    AppStorage.setOrCreate<number>('currentOrderId', firstOrder.id)
    AppStorage.setOrCreate<Order>('currentOrder', firstOrder)
    // 重置已选优惠券
    AppStorage.setOrCreate<Coupon | null>('selectedCoupon', null)
    this.submitting = false
    promptAction.showToast({ message: this.checkoutStoreIds.length > 1 ? `已提交${this.checkoutStoreIds.length}笔订单` : '订单提交成功！' })
    router.pushUrl({ url: 'pages/OrderDetailPage' })
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
              this.AddressCard()
              this.StoreAndItemsCard()
              this.CouponCard()
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

      if (this.showCouponDialog) {
        this.CouponDialog()
      }

      // 提交订单加载遮罩（模拟支付中）
      if (this.submitting) {
        Column() {
          LoadingIndicator({ text: '支付处理中...' })
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
  }

  @Builder
  NavBar() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor(COLORS.TEXT_PRIMARY)
        .onClick(() => { router.back() })
      Text('确认订单')
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(' ')
        .fontSize(28)
        .width(28)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .backgroundColor(COLORS.BG_WHITE)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  EmptyState() {
    Column() {
      Text('🛒')
        .fontSize(60)
      Text('暂无结算商品')
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ top: SPACING.MD })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  AddressCard() {
    Row() {
      Text('📍')
        .fontSize(FONT_SIZE.XL)
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
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.openAddressSelector() })
  }

  @Builder
  StoreAndItemsCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('🏪')
          .fontSize(FONT_SIZE.LG)
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
          }
            .layoutWeight(1)
          Text(`x${item.quantity}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ right: SPACING.MD })
          Text(`¥${(item.goods.price * item.quantity).toFixed(2)}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width('100%')
        .padding({ top: SPACING.XS, bottom: SPACING.XS })
      }, (item: CartItem) => `${item.goods.id}`)
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  CouponCard() {
    Row() {
      Text('🎫')
        .fontSize(FONT_SIZE.LG)
      Text('优惠券')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_PRIMARY)
        .layoutWeight(1)
        .margin({ left: SPACING.SM })
      if (this.selectedCoupon !== null) {
        Text(`-¥${this.selectedCoupon.amount.toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
      } else {
        Text('请选择')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
      }
      Text(' ›')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ left: SPACING.XS })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.showCouponDialog = true })
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
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  RemarkCard() {
    Column({ space: SPACING.SM }) {
      Text('订单备注')
        .fontSize(FONT_SIZE.MD)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
      TextArea({ placeholder: '选填，请输入备注信息（最多50字）' })
        .width('100%')
        .height(80)
        .fontSize(FONT_SIZE.MD)
        .maxLength(50)
        .borderRadius(BORDER_RADIUS.MD)
        .backgroundColor(COLORS.BG_PRIMARY)
        .onChange((value: string) => {
          this.remark = value
        })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SubmitBar() {
    Row() {
      Row() {
        Text('实付')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(`¥${this.getPayAmount().toFixed(2)}`)
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.PRICE_RED)
          .fontWeight(FontWeight.Bold)
          .margin({ left: SPACING.XS })
      }
      .layoutWeight(1)

      Button('提交订单')
        .height(44)
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .id('checkout-submit')
        .onClick(() => { this.submitOrder() })
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })
    .backgroundColor(COLORS.BG_WHITE)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  CouponDialog() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.TEXT_PRIMARY)
        .opacity(0.4)
        .onClick(() => { this.showCouponDialog = false })

      Column() {
        Row() {
          Text('选择优惠券')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
          Text('✕')
            .fontSize(FONT_SIZE.LG)
            .fontColor(COLORS.TEXT_HINT)
            .onClick(() => { this.showCouponDialog = false })
        }
        .width('100%')
        .padding({ bottom: SPACING.MD })

        if (this.getAvailableCoupons().length === 0) {
          Column() {
            Text('暂无可用优惠券')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_HINT)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: SPACING.SM }) {
              this.CouponOption(null)
              ForEach(this.getAvailableCoupons(), (coupon: Coupon) => {
                this.CouponOption(coupon)
              }, (coupon: Coupon) => `${coupon.id}`)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('50%')
      .padding(SPACING.LG)
      .backgroundColor(COLORS.BG_WHITE)
      .borderRadius(BORDER_RADIUS.XL)
    }
    .width('100%')
    .height('100%')
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
        Text('提交订单失败')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)

        Web({ src: $rawfile('order_failure_lottie.html'), controller: this.orderFailureWebController })
          .width(120)
          .height(120)
          .backgroundColor(COLORS.BG_WHITE)

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

        Button('知道了')
          .width('100%')
          .height(44)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .onClick(() => { this.showOrderFailureDialog = false })
      }
      .width('84%')
      .padding(SPACING.XL)
      .backgroundColor(COLORS.BG_WHITE)
      .borderRadius(BORDER_RADIUS.XL)
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
          Text(`¥${coupon.amount.toFixed(0)}`)
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_WHITE)
        } else {
          Text('不使用')
            .fontSize(FONT_SIZE.SM)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_WHITE)
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
          Text(coupon.condition)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text(`满${coupon.minOrder}元可用`)
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
      } else if (coupon === null && this.selectedCoupon === null) {
        Text('✓')
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.PRIMARY)
      }
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_PRIMARY)
    .borderRadius(BORDER_RADIUS.MD)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.selectCoupon(coupon) })
  }
}
