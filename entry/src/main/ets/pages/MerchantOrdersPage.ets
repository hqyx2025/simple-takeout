import { AppButtonStyle, AppCardStyle, AppFilterStyle, AppTextAreaStyle } from '../common/theme/AppTheme'
/**
 * 商户订单管理页
 * 按状态Tab分类展示商户所有店铺订单
 * 支持接单(1→2)、出餐(2→3)、确认送达(3→4)状态流转
 */
import { AppMotion } from '../common/theme/AppMotion'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Order, OrderPageData, CartItem, User, UserRole } from '../model/Models'
import { fetchMerchantOrdersPageApi, MerchantRejectOrderRequest, rejectMerchantOrderApi } from '../service/ApiService'
import { getCurrentUser, merchantActionRemote } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { PageHeader } from '../components/PageHeader'

// 状态Tab项（使用 class + static create 避免 arkts-no-untyped-obj-literals）
class OrderStatusTab {
  status: number = -1
  name: string = ''
  static create(status: number, name: string): OrderStatusTab {
    const tab = new OrderStatusTab()
    tab.status = status
    tab.name = name
    return tab
  }
}

class MerchantRejectReasonOption {
  code: string = ''
  label: string = ''
  description: string = ''

  static create(code: string, label: string, description: string): MerchantRejectReasonOption {
    const option = new MerchantRejectReasonOption()
    option.code = code
    option.label = label
    option.description = description
    return option
  }
}

@Entry
@Component
export struct MerchantOrdersPage {
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

  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State currentStatus: number = -1
  @State allOrders: Order[] = []
  @State currentPage: number = 1
  @State totalOrders: number = 0
  @State hasMoreOrders: boolean = false
  @State loading: boolean = false
  private rejectDialog: CustomDialogController | undefined = undefined
  // 列表重建触发器：syncMerchantOrdersFromServer 是**原地修改**同一批 Order 对象，
  // 只重新赋值数组时 ArkUI 按 id 复用旧列表项、不会重绘，于是「点了接单界面仍显示待接单」
  // 行 key 使用订单业务主键，状态更新通过新数组触发行刷新。
  @State merchantId: number = 0
  private statusTabs: OrderStatusTab[] = [
    OrderStatusTab.create(-1, '全部'),
    OrderStatusTab.create(1, '待接单'),
    OrderStatusTab.create(2, '制作中'),
    OrderStatusTab.create(3, '配送中'),
    OrderStatusTab.create(4, '已完成')
  ]

  aboutToAppear() {
    logInfo('Page', '进入商户订单管理页 MerchantOrdersPage')
    const user: User | undefined = getCurrentUser()
    if (this.loggedIn && user !== undefined && user !== null && user.role === UserRole.MERCHANT) {
      this.merchantId = user.id
      this.loadOrders()
    } else {
      promptAction.showToast({ message: '请使用商户账号登录后查看订单', duration: 1800 })
      router.back()
    }
  }

  private async loadOrders(page: number = 1, append: boolean = false): Promise<void> {
    if (this.loading || this.merchantId <= 0) {
      return
    }
    this.loading = true
    const status: number | undefined = this.currentStatus < 0 ? undefined : this.currentStatus
    const result: OrderPageData = await fetchMerchantOrdersPageApi(status, page)
    this.allOrders = append ? this.allOrders.concat(result.list) : result.list
    this.currentPage = result.page
    this.totalOrders = result.total
    this.hasMoreOrders = result.hasMore
    this.loading = false
  }

  private getFilteredOrders(): Order[] {
    return this.allOrders
  }

  private async loadMoreOrders(): Promise<void> {
    if (!this.loading && this.hasMoreOrders) {
      await this.loadOrders(this.currentPage + 1, true)
    }
  }

  private selectStatus(status: number): void {
    if (this.loading) {
      return
    }
    this.currentStatus = status
    this.loadOrders()
  }

  private async handleAccept(order: Order): Promise<void> {
    const ok: boolean = await merchantActionRemote(order.id, 'accept')
    if (!ok) {
      promptAction.showToast({ message: '接单失败，请检查登录状态或订单状态', duration: 2200 })
      return
    }
    logInfo('Merchant', `点击接单 orderId=${order.id} 店铺=${order.storeName}`)
    promptAction.showToast({ message: '已接单' })
    this.loadOrders()
  }

  private openRejectDialog(order: Order): void {
    if (order.status !== 1) {
      promptAction.showToast({ message: '订单状态已变化，请刷新后再处理', duration: 2200 })
      return
    }
    if (this.rejectDialog !== undefined) {
      try { this.rejectDialog.close() } catch (_) {}
    }
    this.rejectDialog = new CustomDialogController({
      autoCancel: false,
      alignment: DialogAlignment.Center,
      customStyle: true,
      builder: MerchantRejectOrderDialog({
        orderId: order.id,
        orderNo: order.orderNo ?? order.id.toString(),
        storeName: order.storeName,
        items: order.items,
        onSubmit: async (request: MerchantRejectOrderRequest): Promise<boolean> => {
          const ok: boolean = await rejectMerchantOrderApi(order.id, request)
          if (ok) {
            logInfo('Merchant', `无法接单 orderId=${order.id} reason=${request.reasonCode}`)
            promptAction.showToast({ message: '已通知用户，款项已按原支付渠道退回', duration: 2600 })
            await this.loadOrders()
          }
          return ok
        },
        onClose: (): void => { this.rejectDialog = undefined }
      })
    })
    this.rejectDialog.open()
  }

  /** 出餐完成：写 ready_time 并进入骑手待取餐池（数字状态仍为 2），订单由骑手接单后配送。 */
  private async handleReady(order: Order): Promise<void> {
    const ok: boolean = await merchantActionRemote(order.id, 'ready')
    if (!ok) {
      promptAction.showToast({ message: '出餐操作失败，请检查登录状态或订单状态', duration: 2200 })
      return
    }
    logInfo('Merchant', `点击出餐 orderId=${order.id} 店铺=${order.storeName}`)
    promptAction.showToast({ message: '已出餐，等待骑手接单', duration: 2200 })
    this.loadOrders()
  }

  private async handleComplete(order: Order): Promise<void> {
    const ok: boolean = await merchantActionRemote(order.id, 'complete')
    if (!ok) {
      promptAction.showToast({ message: '确认送达失败，请检查登录状态或订单状态', duration: 2200 })
      return
    }
    logInfo('Merchant', `点击确认送达 orderId=${order.id} 店铺=${order.storeName}`)
    promptAction.showToast({ message: '已确认送达' })
    this.loadOrders()
  }

  build() {
    Column() {
      // 顶部导航栏：标题 + 返回按钮
      PageHeader({
        title: '订单管理',
        backId: 'merchant-orders-back',
        headerBgColor: COLORS.BG_PRIMARY,
        actionColor: MODULE_COLOR.MERCHANT,
        onBack: () => { router.back() }
      })

      // 状态Tab栏（横向滚动）
      Scroll() {
        Row({ space: SPACING.SM }) {
          ForEach(this.statusTabs, (tab: OrderStatusTab) => {
            this.FilterTab(tab)
          }, (tab: OrderStatusTab) => tab.status.toString())
        }
        .padding({ left: SPACING.LG, right: SPACING.LG })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(60)
      .backgroundColor(COLORS.BG_WHITE)

      // 订单列表 / 空状态
      if (this.loading && this.getFilteredOrders().length === 0) {
        Column() {
          Text('正在加载订单…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.getFilteredOrders().length === 0) {
        Column() {
          Image($r('app.media.ui_inbox')).width(32).height(32).objectFit(ImageFit.Contain).margin({ top: 40 })
          Text('暂无订单')
            .fontSize(FONT_SIZE.LG)
            .fontColor(COLORS.TEXT_HINT)
            .margin({ top: SPACING.MD })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: SPACING.MD }) {
          ForEach(this.getFilteredOrders(), (order: Order) => {
            ListItem() {
              this.OrderCard(order)
            }
          }, (order: Order) => `${order.id}`)
          ListItem() {
            Row({ space: SPACING.SM }) {
              Text(`已显示 ${this.allOrders.length} / ${this.totalOrders}`)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
              if (this.hasMoreOrders) {
                Button(this.loading ? '加载中' : '加载更多')
                  .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
                  .enabled(!this.loading).id('merchant-order-load-more')
                  .onClick(() => { this.loadMoreOrders() })
              }
            }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.MD })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  FilterTab(tab: OrderStatusTab) {
    Button(tab.name)
      .attributeModifier(new AppFilterStyle(this.currentStatus === tab.status))
      .animation(AppMotion.pressAnimation())
      .accessibilitySelected(this.currentStatus === tab.status)
      .onClick(() => { this.selectStatus(tab.status) })
  }

  @Builder
  OrderCard(order: Order) {
    Column({ space: SPACING.SM }) {
      // 店铺名 + 订单状态
      Row() {
        Image($r('app.media.login_store')).objectFit(ImageFit.Contain)
          .width(28)
          .height(28)
.backgroundColor(accentBg(accentIndexFromText(order.storeName)))
          .backgroundColor(accentBg(accentIndexFromText(order.storeName)))
          .borderRadius(BORDER_RADIUS.SM)
        Text(order.storeName)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
        Text(getOrderStatusText(order.status, order.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.MD)
          .fontColor(accentFg(order.status))
          .backgroundColor(accentBg(order.status))
          .padding({ left: SPACING.SM, right: SPACING.SM, top: 2, bottom: 2 })
          .borderRadius(BORDER_RADIUS.ROUND)
          .id(`merchant-order-status-${order.id}`)
      }
      .width('100%')

      // 下单时间
      Row() {
        Text('下单时间')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(order.createTime)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
      }
      .width('100%')

      // 商品列表（商品名x数量）
      Column({ space: SPACING.XS }) {
        ForEach(order.items, (item: CartItem) => {
          Row() {
            Column({ space: 2 }) {
              Text(item.goods.name)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_PRIMARY)
                .width('100%')
              if ((item.specName ?? '').trim() !== '') {
                Text(`规格：${item.specName}`)
                  .fontSize(FONT_SIZE.XS)
                  .fontColor(COLORS.TEXT_HINT)
                  .width('100%')
              }
            }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            Text(`x${item.quantity}`)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
          }
          .width('100%')
        }, (item: CartItem, index: number) => `${index}_${item.goods.id}_${item.specId ?? 0}`)
      }
      .width('100%')
      .padding({ top: SPACING.XS, bottom: SPACING.XS })

      Column({ space: SPACING.XS }) {
        Text(`配送方式：${order.deliveryType === 'PICKUP' ? '到店自取' : '外卖配送'}`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
        Text((order.expectTime ?? '').trim() === '' ? '送达时间：立即送达' : `预约送达：${order.expectTime}`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
        Text(`订单备注：${(order.remark ?? '').trim() === '' ? '无' : order.remark}`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Divider().color(COLORS.DIVIDER)

      // 实付金额 + 操作按钮
      Row() {
        Text('实付')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(`¥${order.payAmount.toFixed(2)}`)
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.PRICE_RED)
          .fontWeight(FontWeight.Bold)
          .margin({ left: SPACING.XS })
          .layoutWeight(1)
        this.OrderAction(order)
      }
      .width('100%')
      if (order.status === 1) {
        Button('无法接单')
          .attributeModifier(new AppButtonStyle()).width('100%').height(44)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: COLORS.ERROR })
          .borderRadius(BORDER_RADIUS.ROUND)
          .id(`merchant-reject-${order.id}`)
          .onClick(() => { this.openRejectDialog(order) })
      }
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
    .id(`merchant-order-card-${order.id}`)
  }

  @Builder
  OrderAction(order: Order) {
    if (order.status === 1) {
      Button('接单')
        .attributeModifier(new AppButtonStyle()).height(44)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(MODULE_COLOR.MERCHANT)
        .borderRadius(BORDER_RADIUS.ROUND)
        .id(`merchant-action-${order.id}`)
        .onClick(() => { this.handleAccept(order) })
    } else if (order.status === 2) {
      Column({ space: SPACING.XS }) {
        if ((order.riderName ?? '') !== '') {
          Text(`骑手 ${order.riderName} 已接单，等待取餐`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(MODULE_COLOR.MERCHANT)
        } else if ((order.readyTime ?? '') !== '') {
          Text('已出餐，等待骑手接单')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.SUCCESS)
            .id(`merchant-ready-${order.id}`)
        } else {
          Button('出餐完成')
            .attributeModifier(new AppButtonStyle()).height(44)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(MODULE_COLOR.MERCHANT)
            .borderRadius(BORDER_RADIUS.ROUND)
            .id(`merchant-action-${order.id}`)
            .onClick(() => { this.handleReady(order) })
        }
        Text('制作中如有异常，请联系平台处理')
          .fontSize(FONT_SIZE.XS)
          .fontColor(COLORS.TEXT_HINT)
      }
      .alignItems(HorizontalAlign.End)
    } else if (order.status === 3) {
      if ((order.riderName ?? '') !== '') {
        // 骑手配送中：由骑手送达，商户不需要也不能确认送达
        Text(`骑手 ${order.riderName} 配送中`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(MODULE_COLOR.MERCHANT)
      } else {
        // 未分配骑手的订单仍保留商户自行确认送达（兼容无骑手时的自配送）
        Button('确认送达')
          .attributeModifier(new AppButtonStyle()).height(40)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.ON_PRIMARY)
          .backgroundColor(MODULE_COLOR.MERCHANT)
          .borderRadius(BORDER_RADIUS.ROUND)
          .id(`merchant-action-${order.id}`)
          .onClick(() => { this.handleComplete(order) })
      }
    } else if (order.status === 4) {
      // 已送达待确认收货 / 已结算完成（与大纲 6.4 口径一致）
      Text(getOrderStatusText(order.status, order.escrowStatus ?? 0))
        .fontSize(FONT_SIZE.SM)
        .fontColor(order.escrowStatus === 1 ? COLORS.TEXT_HINT : COLORS.WARNING)
    } else if (order.status === 5) {
      Text((order.cancelSource ?? '') === 'MERCHANT' ? '商家未能接单' : '已取消')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
    }
  }
}

@CustomDialog
struct MerchantRejectOrderDialog {
  controller?: CustomDialogController
  orderId: number = 0
  orderNo: string = ''
  storeName: string = ''
  items: CartItem[] = []
  onSubmit: (request: MerchantRejectOrderRequest) => Promise<boolean> =
    (_request: MerchantRejectOrderRequest): Promise<boolean> => Promise.resolve(false)
  onClose: () => void = () => {}
  @State reasonCode: string = ''
  @State note: string = ''
  @State selectedItemKey: string = ''
  @State submitting: boolean = false
  @State errorText: string = ''
  private reasonOptions: MerchantRejectReasonOption[] = [
    MerchantRejectReasonOption.create('ITEM_UNAVAILABLE', '餐品缺货', '选择本单中无法供应的餐品'),
    MerchantRejectReasonOption.create('STORE_OVER_CAPACITY', '订单已满', '当前产能无法按时完成本单'),
    MerchantRejectReasonOption.create('STORE_TEMPORARILY_CLOSED', '门店临时歇业', '门店突发情况，暂时无法营业'),
    MerchantRejectReasonOption.create('OTHER', '其他原因', '可在下方补充具体说明')
  ]

  aboutToDisappear(): void {
    this.note = ''
    this.onClose()
  }

  private itemKey(item: CartItem): string {
    return `${item.goods.id}:${item.specId ?? 0}`
  }

  private selectedItem(): CartItem | undefined {
    return this.items.find((item: CartItem) => this.itemKey(item) === this.selectedItemKey)
  }

  private canSubmit(): boolean {
    return !this.submitting && this.reasonCode !== '' &&
      (this.reasonCode !== 'ITEM_UNAVAILABLE' || this.selectedItem() !== undefined)
  }

  private close(): void {
    if (this.submitting) {
      return
    }
    if (this.controller !== undefined) {
      this.controller.close()
    }
  }

  private async submit(): Promise<void> {
    if (!this.canSubmit()) {
      promptAction.showToast({
        message: this.reasonCode === 'ITEM_UNAVAILABLE' ? '请选择缺货餐品' : '请选择无法接单原因',
        duration: 1800
      })
      return
    }
    const request: MerchantRejectOrderRequest = { reasonCode: this.reasonCode }
    const trimmedNote: string = this.note.trim()
    if (trimmedNote !== '') {
      request.note = trimmedNote
    }
    if (this.reasonCode === 'ITEM_UNAVAILABLE') {
      const item: CartItem | undefined = this.selectedItem()
      if (item === undefined) {
        return
      }
      request.goodsId = item.goods.id
      request.specId = item.specId ?? 0
    }
    this.submitting = true
    this.errorText = ''
    try {
      const ok: boolean = await this.onSubmit(request)
      if (ok) {
        if (this.controller !== undefined) {
          this.controller.close()
        }
      } else {
        this.errorText = '提交失败，订单状态可能已变化，请核对后重试'
      }
    } catch (_) {
      this.errorText = '网络请求未完成，请稍后重试'
    } finally {
      this.submitting = false
    }
  }

  build() {
    Column({ space: SPACING.MD }) {
      Column({ space: SPACING.XS }) {
        Text('无法接单')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .width('100%')
        Text(`订单 ${this.orderNo === '' ? this.orderId : this.orderNo} · ${this.storeName}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        Text('请按实际情况选择原因。提交后用户会看到原因，订单款项由服务端按规则处理。')
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
      }
      Scroll() {
        Column({ space: SPACING.SM }) {
          Text('无法接单原因')
            .fontSize(FONT_SIZE.SM).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).width('100%')
          ForEach(this.reasonOptions, (option: MerchantRejectReasonOption) => {
            this.ReasonOption(option)
          }, (option: MerchantRejectReasonOption) => option.code)

          if (this.reasonCode === 'ITEM_UNAVAILABLE') {
            Text('缺货餐品')
              .fontSize(FONT_SIZE.SM).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              .width('100%').margin({ top: SPACING.SM })
            ForEach(this.items, (item: CartItem) => {
              this.ItemOption(item)
            }, (item: CartItem, index: number) => `${index}_${this.itemKey(item)}`)
          }

          Text('补充说明（选填）')
            .fontSize(FONT_SIZE.SM).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            .width('100%').margin({ top: SPACING.SM })
          TextArea({ text: this.note, placeholder: '例如：原料临时售罄，预计晚餐时段恢复' })
            .attributeModifier(new AppTextAreaStyle()).width('100%').height(92).maxLength(100)
            .enabled(!this.submitting)
            .id('merchant-reject-note')
            .onChange((value: string) => { this.note = value })
        }
        .width('100%')
      }
      .layoutWeight(1).scrollBar(BarState.Auto)

      if (this.errorText !== '') {
        Text(this.errorText).fontSize(FONT_SIZE.XS).fontColor(COLORS.ERROR).width('100%')
      }

      Row({ space: SPACING.MD }) {
        Button('暂不处理')
          .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44)
          .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
          .enabled(!this.submitting).onClick(() => { this.close() })
        Button(this.submitting ? '提交中…' : '确认无法接单')
          .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44)
          .fontColor(COLORS.ON_PRIMARY).backgroundColor(COLORS.ERROR)
          .enabled(this.canSubmit()).id('merchant-reject-submit')
          .onClick(() => { this.submit() })
      }
      .width('100%')
    }
    .attributeModifier(new AppCardStyle())
    .width('92%').height('82%').constraintSize({ maxWidth: 520, maxHeight: 720 })
    .padding(SPACING.XL)
  }

  @Builder
  ReasonOption(option: MerchantRejectReasonOption) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SPACING.SM }) {
        Radio({ value: option.code, group: 'merchant-reject-reason' })
          .checked(this.reasonCode === option.code)
          .enabled(!this.submitting)
          .onChange((checked: boolean) => {
            if (checked) {
              this.reasonCode = option.code
              this.errorText = ''
            }
          })
        Column({ space: 2 }) {
          Text(option.label).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).width('100%')
          Text(option.description).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%').height(56).padding({ left: SPACING.MD, right: SPACING.MD })
    .backgroundColor(this.reasonCode === option.code ? MODULE_BG.MERCHANT : COLORS.BG_PRIMARY)
    .border({ width: 1, color: this.reasonCode === option.code ? MODULE_COLOR.MERCHANT : COLORS.DIVIDER })
    .borderRadius(BORDER_RADIUS.MD).enabled(!this.submitting)
    .onClick(() => {
      this.reasonCode = option.code
      this.errorText = ''
    })
  }

  @Builder
  ItemOption(item: CartItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SPACING.SM }) {
        Radio({ value: this.itemKey(item), group: 'merchant-reject-item' })
          .checked(this.selectedItemKey === this.itemKey(item))
          .enabled(!this.submitting)
          .onChange((checked: boolean) => {
            if (checked) {
              this.selectedItemKey = this.itemKey(item)
              this.errorText = ''
            }
          })
        Text((item.specName ?? '') === '' ? `${item.goods.name} ×${item.quantity}` :
          `${item.goods.name}（${item.specName}）×${item.quantity}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .width('100%').height(52).padding({ left: SPACING.MD, right: SPACING.MD })
    .backgroundColor(this.selectedItemKey === this.itemKey(item) ? MODULE_BG.MERCHANT : COLORS.BG_PRIMARY)
    .border({ width: 1,
      color: this.selectedItemKey === this.itemKey(item) ? MODULE_COLOR.MERCHANT : COLORS.DIVIDER })
    .borderRadius(BORDER_RADIUS.MD).enabled(!this.submitting)
    .onClick(() => {
      this.selectedItemKey = this.itemKey(item)
      this.errorText = ''
    })
  }
}
