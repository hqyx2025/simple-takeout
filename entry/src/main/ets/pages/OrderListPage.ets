import { AppButtonStyle, AppCardStyle, AppFilterStyle, AppRefreshStyle } from '../common/theme/AppTheme'
/**
 * 我的订单页（独立路由页）。
 *
 * 历史上订单是首页底部 Tab 之一，现在底部只保留「首页 / AI 助手 / 我的」三个标签，
 * 订单改为从「我的」页的订单入口进入本页。
 */
import { AppMotion } from '../common/theme/AppMotion'
import { CartItem, Order, OrderPageData, createEmptyUser, User, UserRole } from '../model/Models'
import { getAuthSessionEpoch } from '../service/HttpClient'
import { fetchUserOrdersPageApi } from '../service/ApiService'
import { confirmOrderRemote, cancelOrderRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor, MODULE_COLOR, MODULE_BG } from '../common/Constants'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { canOrderAction } from '../service/OrderStatus'
import { logInfo } from '../service/AppLogger'

/** 订单筛选 Tab 数据（避免 arkts-no-untyped-obj-literals）。 */
class OrderTabItem {
  title: string = ''
  status: number = -1

  static create(title: string, status: number): OrderTabItem {
    const item: OrderTabItem = new OrderTabItem()
    item.title = title
    item.status = status
    return item
  }
}

/** 订单列表懒加载数据源（实现 IDataSource）。 */
class OrderDataSource implements IDataSource {
  private list: Order[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.list.length
  }

  getData(index: number): Order {
    return this.list[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener)
  }

  setData(data: Order[]): void {
    this.list = data
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded())
  }
}

@Entry
@Component
struct OrderListPage {
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

  // 注意：数据源必须在 @StorageLink+@Watch 字段之前声明，
  // 避免 @StorageLink 首次绑定时触发 @Watch 回调访问到未初始化的数据源
  private orderDataSource: OrderDataSource = new OrderDataSource()
  @StorageLink('orderList') @Watch('onOrderListChange') orderList: Order[] = []
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @StorageLink('orderFilterStatus') @Watch('onOrderFilterRequest') requestedStatus: number = -1
  @State @Watch('onFilterChange') currentStatus: number = -1
  @State pageOrders: Order[] = []
  @StorageLink('user') @Watch('onOrdersOwnerChange') ordersOwner: User = createEmptyUser()
  @State ordersError: boolean = false
  private ordersRequestVersion: number = 0
  private pageActive: boolean = true
  private retryPage: number = 1
  private retryAppend: boolean = false
  @State currentPage: number = 1
  @State totalOrders: number = 0
  @State hasMoreOrders: boolean = false
  @State isRefreshing: boolean = false
  @State filteredCount: number = 0
  @State expandedOrderIds: number[] = []
  @State showConfirmDialog: boolean = false
  private confirmingOrderId: number = 0
  private ordersLoading: boolean = false

  aboutToAppear() {
    logInfo('Page', '进入我的订单页 OrderListPage')
    this.currentStatus = this.requestedStatus
    this.refreshDataSource()
    if (!this.loggedIn) {
      this.orderList = []
      this.pageOrders = []
      this.totalOrders = 0
      this.hasMoreOrders = false
      this.refreshDataSource()
      return
    }
    // 从后端拉取最新订单（真实后端模式）
    this.refreshOrders()
  }

  onLoginStateChange(): void {
    this.ordersRequestVersion += 1
    this.ordersLoading = false
    this.isRefreshing = false
    if (!this.loggedIn) {
      this.orderList = []
      this.pageOrders = []
      this.totalOrders = 0
      this.hasMoreOrders = false
      this.refreshDataSource()
      return
    }
    this.refreshOrders()
  }

  onOrderFilterRequest(): void {
    if (this.requestedStatus >= -1 && this.requestedStatus <= 6) {
      this.selectStatus(this.requestedStatus)
    }
  }

  private selectStatus(status: number): void {
    this.currentStatus = status
  }

  // 拉取后端用户订单并刷新列表
  private canApplyOrders(epoch: number, owner: number, version: number): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.pageActive && this.loggedIn && epoch === getAuthSessionEpoch()
      && user?.id === owner && user?.role === UserRole.CUSTOMER && version === this.ordersRequestVersion
  }

  onPageShow(): void {
    this.pageActive = true
    this.refreshOrders()
  }

  onPageHide(): void {
    this.pageActive = false
    this.ordersRequestVersion += 1
    this.ordersLoading = false
    this.isRefreshing = false
  }

  aboutToDisappear(): void { this.onPageHide() }

  onOrdersOwnerChange(): void {
    this.ordersRequestVersion += 1
    this.ordersLoading = false
    this.pageOrders = []
    this.totalOrders = 0
    this.hasMoreOrders = false
    this.ordersError = false
    this.refreshDataSource()
    if (this.pageActive) { this.refreshOrders() }
  }

  private async refreshOrders(page: number = 1, append: boolean = false): Promise<void> {
    if (!this.pageActive || (this.ordersLoading && append)) { return }
    const user: User | undefined = AppStorage.get<User>('user')
    if (!this.loggedIn || user === undefined || user.id <= 0 || user.role !== UserRole.CUSTOMER) { return }
    const epoch: number = getAuthSessionEpoch()
    const owner: number = user.id
    const version: number = ++this.ordersRequestVersion
    this.ordersLoading = true
    this.isRefreshing = true
    this.ordersError = false
    this.retryPage = page
    this.retryAppend = append
    try {
      const status: number | undefined = this.currentStatus < 0 ? undefined : this.currentStatus
      const result: OrderPageData | null = await fetchUserOrdersPageApi(status, page, 30, false)
      if (!this.canApplyOrders(epoch, owner, version)) { return }
      if (result === null) { this.ordersError = true; return }
      this.pageOrders = append ? this.pageOrders.concat(result.list) : result.list
      this.currentPage = result.page
      this.totalOrders = result.total
      this.hasMoreOrders = result.hasMore
      this.refreshDataSource()
    } catch (_) {
      if (this.canApplyOrders(epoch, owner, version)) { this.ordersError = true }
    } finally {
      if (this.canApplyOrders(epoch, owner, version)) {
        this.ordersLoading = false
        this.isRefreshing = false
      }
    }
  }

  onOrderListChange(): void {
    // 防御：@StorageLink 首次绑定也可能触发本回调，数据源未就绪时直接返回
    if (this.orderDataSource === undefined || this.orderDataSource === null) {
      return
    }
    this.refreshDataSource()
  }

  onFilterChange(): void {
    if (this.orderDataSource !== undefined && this.orderDataSource !== null && this.loggedIn) {
      this.refreshOrders()
    }
  }

  private async loadMoreOrders(): Promise<void> {
    if (this.ordersLoading || !this.hasMoreOrders) {
      return
    }
    await this.refreshOrders(this.currentPage + 1, true)
  }

  private refreshDataSource(): void {
    // Only the current server page belongs in the lazily rendered data source.
    const list: Order[] = this.loggedIn && Array.isArray(this.pageOrders) ? this.pageOrders : []
    this.orderDataSource.setData(list)
    this.filteredCount = list.length
  }

  private activeCustomerOrder(orderId: number, action: string): Order | undefined {
    if (!this.pageActive || !this.loggedIn || this.ordersOwner.role !== UserRole.CUSTOMER) { return undefined }
    const user: User | undefined = AppStorage.get<User>('user')
    if (user?.id !== this.ordersOwner.id || user?.role !== UserRole.CUSTOMER) { return undefined }
    const current: Order | undefined = this.pageOrders.find((order: Order) => order.id === orderId)
    if (current === undefined) { return undefined }
    const legacy: boolean = action === 'CONFIRM' ? current.status === 4 && (current.escrowStatus ?? 0) === 0 : current.status === 0
    return canOrderAction(current, action, legacy) ? current : undefined
  }

  /** 待付款订单先进入详情选择渠道，避免列表按钮隐式使用余额支付。 */
  private payPendingOrder(order: Order): void {
    const current: Order | undefined = this.activeCustomerOrder(order.id, 'PAY')
    if (current === undefined) { return }
    AppStorage.setOrCreate<Order>('currentOrder', current)
    AppStorage.setOrCreate<number>('currentOrderId', order.id)
    router.pushUrl({ url: 'pages/OrderDetailPage' })
  }

  /** 取消待付款订单：平台尚未扣款，仅释放库存与优惠券。 */
  private async cancelPendingOrder(order: Order): Promise<void> {
    if (this.activeCustomerOrder(order.id, 'CANCEL') === undefined) { return }
    const epoch: number = getAuthSessionEpoch()
    const owner: number = this.ordersOwner.id
    const version: number = this.ordersRequestVersion
    const ok: boolean = await cancelOrderRemote(order.id)
    if (!this.canApplyOrders(epoch, owner, version)) { return }
    await this.refreshOrders()
    if (ok) {
      promptAction.showToast({ message: '订单已取消，平台未扣款；库存与优惠券已释放', duration: 2400 })
    } else {
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: errorMessage === '' ? '取消订单失败，请稍后重试' : errorMessage, duration: 3000 })
    }
  }

  private async confirmSelectedOrder(): Promise<void> {
    const orderId: number = this.confirmingOrderId
    this.showConfirmDialog = false
    this.confirmingOrderId = 0
    if (orderId <= 0 || this.activeCustomerOrder(orderId, 'CONFIRM') === undefined) { return }
    const epoch: number = getAuthSessionEpoch()
    const owner: number = this.ordersOwner.id
    const version: number = this.ordersRequestVersion
    const ok: boolean = await confirmOrderRemote(orderId)
    if (!this.canApplyOrders(epoch, owner, version)) { return }
    await this.refreshOrders()
    if (ok) {
      promptAction.showToast({ message: '已确认收到，订单已完成', duration: 1800 })
    } else {
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: errorMessage === '' ? '确认收货失败，请稍后重试' : errorMessage, duration: 2200 })
    }
  }

  build() {
    Stack() {
      Column() {
        // 导航栏：独立路由页必须自带返回
        PageHeader({ title: '我的订单', backId: 'order-list-back', onBack: () => { router.back() } })

        Scroll() {
          Row({ space: SPACING.SM }) {
            ForEach([
              OrderTabItem.create('全部', -1),
              OrderTabItem.create('待付款', 0),
              OrderTabItem.create('待接单', 1),
              OrderTabItem.create('配送中', 3),
              OrderTabItem.create('已完成', 4),
            ], (item: OrderTabItem) => {
              this.FilterTab(item)
            }, (item: OrderTabItem) => item.title)
          }
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .width('100%').backgroundColor(COLORS.BG_WHITE)

        if (!this.loggedIn) {
          EmptyState({ icon: $r('app.media.login_lock'), title: '暂无登录', description: '请登录后查看订单' })
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List({ space: SPACING.SM }) {
              if (this.ordersError) {
                ListItem() {
                  Button('订单加载失败，点击重试（保留上次数据）')
                    .attributeModifier(new AppButtonStyle()).enabled(!this.ordersLoading)
                    .id('customer-order-retry')
                    .onClick(() => { this.refreshOrders(this.retryPage, this.retryAppend) })
                }
              }
              if (this.filteredCount === 0 && !this.isRefreshing && !this.ordersError) {
                ListItem() {
                  EmptyState({ icon: $r('app.media.ui_gift'), title: '暂无订单',
                    description: this.currentStatus === -1 ? '快去点一份美味吧' : '当前分类暂无订单，可下拉刷新' })
                    .height(300)
                }
              }
              LazyForEach(this.orderDataSource, (order: Order) => {
                ListItem() {
                  this.OrderCard(order)
                }
              }, (item: Order) => item.id.toString())
              ListItem() {
                Row({ space: SPACING.SM }) {
                  Text(`已显示 ${this.pageOrders.length} / ${this.totalOrders}`)
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
                  if (this.hasMoreOrders) {
                    Button(this.ordersLoading ? '加载中' : '加载更多')
                      .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
                      .enabled(!this.ordersLoading).id('customer-order-load-more')
                      .onClick(() => { this.loadMoreOrders() })
                  }
                }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.MD })
              }
            }
            .height('100%')
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
            .scrollBar(BarState.Off).divider({ strokeWidth: 0 })
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .cachedCount(5)
          }
          .layoutWeight(1)
          .attributeModifier(new AppRefreshStyle())
          .onRefreshing(() => { this.refreshOrders() })
        }
      }
      .width('100%').height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      if (this.showConfirmDialog) {
        ConfirmDialog({
          title: '确认收到餐品？',
          content: '确认后订单款项将结算；送达48小时内仍可申请售后退款',
          confirmText: '确认收到',
          cancelText: '暂不确认',
          onConfirm: () => { this.confirmSelectedOrder() },
          onCancel: () => {
            this.showConfirmDialog = false
            this.confirmingOrderId = 0
          }
        })
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  FilterTab(item: OrderTabItem) {
    Button(item.title)
      .attributeModifier(new AppFilterStyle(this.currentStatus === item.status))
      .animation(AppMotion.pressAnimation())
      .accessibilitySelected(this.currentStatus === item.status)
      .enabled(!this.ordersLoading)
      .id(`order-filter-${item.status}`)
      .onClick(() => { this.selectStatus(item.status) })
  }

  @Builder
  OrderCard(order: Order) {
    Column({ space: SPACING.SM }) {
      Row() {
        Text(order.storeName)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        Text((order.cancelSource ?? '') === 'MERCHANT'
          ? '商家未能接单' : getOrderStatusText(order.status, order.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.MD).fontColor(getOrderStatusColor(order.status, order.escrowStatus ?? 0)).fontWeight(FontWeight.Bold)
      }
      Text(`订单号：${order.orderNo ?? order.id}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if ((order.cancelSource ?? '') === 'MERCHANT') {
        Column({ space: 2 }) {
          Text(`原因：${(order.cancelReason ?? '').trim() === '' ? '商家无法承接本次订单' : order.cancelReason}`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        }
        .width('100%').padding(SPACING.SM).backgroundColor(MODULE_BG.ORDER).borderRadius(BORDER_RADIUS.MD)
      }
      ForEach(this.expandedOrderIds.indexOf(order.id) >= 0 ? (order.items ?? []) : (order.items ?? []).slice(0, 2), (item: CartItem) => {
        Row() {
          // 多规格：订单行附带下单时锁定的规格快照
          Text((item.specName ?? '') !== '' ? `${item.goods.name}（${item.specName}）` : item.goods.name)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).layoutWeight(1)
          Text(`x${item.quantity}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.width('100%')
      }, (item: CartItem, index: number) => `${index}_${item.goods.id}_${item.specId ?? 0}`)
      if ((order.items ?? []).length > 2) {
        Button(this.expandedOrderIds.indexOf(order.id) >= 0 ? '收起商品 ∧' : `展开其余 ${(order.items ?? []).length - 2} 件商品 ∨`)
          .attributeModifier(new AppButtonStyle()).height(40).width('100%')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
          .id(`order-expand-${order.id}`)
          .onClick(() => {
            this.getUIContext().animateTo({ duration: AppMotion.duration(220), curve: Curve.EaseOut }, () => {
              this.expandedOrderIds = this.expandedOrderIds.indexOf(order.id) >= 0
                ? this.expandedOrderIds.filter((id: number) => id !== order.id) : this.expandedOrderIds.concat(order.id)
            })
          })
      }
      Row() {
        Text(`共${(order.items || []).reduce((s, i) => s + i.quantity, 0)}件 实付`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(`¥${order.payAmount.toFixed(2)}`)
          .fontSize(FONT_SIZE.LG).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
      }.width('100%')
      Flex({ justifyContent: FlexAlign.End, wrap: FlexWrap.Wrap }) {
        if (order.status === 0) {
          // 待付款：可取消（释放库存与优惠券）或立即支付
          Button('取消订单')
            .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY).borderRadius(BORDER_RADIUS.ROUND)
            .margin({ right: SPACING.SM }).enabled(canOrderAction(order, 'CANCEL', true))
            .onClick(() => { this.cancelPendingOrder(order) })
          Button('立即支付')
            .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.SM).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(MODULE_COLOR.ORDER).borderRadius(BORDER_RADIUS.ROUND)
            .enabled(canOrderAction(order, 'PAY', true))
            .onClick(() => { this.payPendingOrder(order) })
        } else if (canOrderAction(order, 'CONFIRM', order.status === 4 && (order.escrowStatus ?? 0) === 0)) {
          Button('确认收到')
            .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.SM).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(MODULE_COLOR.CART).borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => {
              this.confirmingOrderId = order.id
              this.showConfirmDialog = true
            })
        } else if (order.status === 1) {
          Text('等待商家接单，可在订单详情取消')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        } else if (order.status === 2) {
          Text('订单已进入制作，如需处理请联系平台')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        } else if (order.status === 3) {
          Text('订单已进入配送，如需处理请联系平台')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        } else if (order.status === 5) {
          Text((order.cancelSource ?? '') === 'MERCHANT' ? '商家未能接单' : '已取消')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        }
      }.width('100%')
    }
    .width('100%').padding(SPACING.MD)
    .attributeModifier(new AppCardStyle())
    .id(`order-card-${order.id}`)
    .onClick(() => {
      AppStorage.setOrCreate<Order>('currentOrder', order)
      AppStorage.setOrCreate<number>('currentOrderId', order.id)
      router.pushUrl({ url: 'pages/OrderDetailPage' })
    })
  }
}
