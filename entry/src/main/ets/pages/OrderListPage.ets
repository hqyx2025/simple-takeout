/**
 * 我的订单页（独立路由页）。
 *
 * 历史上订单是首页底部 Tab 之一，现在底部只保留「首页 / AI 助手 / 我的」三个标签，
 * 订单改为从「我的」页的订单入口进入本页。
 */
import { CartItem, Order } from '../model/Models'
import { syncUserOrdersFromServer, confirmOrderRemote, cancelOrderRemote, payOrderRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor, MODULE_COLOR, MODULE_BG } from '../common/Constants'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
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
  // 注意：数据源必须在 @StorageLink+@Watch 字段之前声明，
  // 避免 @StorageLink 首次绑定时触发 @Watch 回调访问到未初始化的数据源
  private orderDataSource: OrderDataSource = new OrderDataSource()
  @StorageLink('orderList') @Watch('onOrderListChange') orderList: Order[] = []
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @StorageLink('orderFilterStatus') @Watch('onOrderFilterRequest') requestedStatus: number = -1
  @State @Watch('onFilterChange') currentStatus: number = -1
  @State isRefreshing: boolean = false

  aboutToAppear() {
    logInfo('Page', '进入我的订单页 OrderListPage')
    this.currentStatus = this.requestedStatus
    this.refreshDataSource()
    if (!this.loggedIn) {
      this.orderList = []
      return
    }
    // 从后端拉取最新订单（真实后端模式）
    this.refreshOrders()
  }

  onLoginStateChange(): void {
    if (!this.loggedIn) {
      this.orderList = []
      this.refreshDataSource()
      return
    }
    this.refreshOrders()
  }

  onOrderFilterRequest(): void {
    if (this.requestedStatus >= -1 && this.requestedStatus <= 6) {
      this.currentStatus = this.requestedStatus
    }
  }

  // 拉取后端用户订单并刷新列表
  private async refreshOrders(): Promise<void> {
    if (!this.loggedIn) {
      this.orderList = []
      this.refreshDataSource()
      return
    }
    await syncUserOrdersFromServer()
    this.orderList = AppStorage.get<Order[]>('orderList') || []
    this.refreshDataSource()
  }

  onOrderListChange(): void {
    // 防御：@StorageLink 首次绑定也可能触发本回调，数据源未就绪时直接返回
    if (this.orderDataSource === undefined || this.orderDataSource === null) {
      return
    }
    this.refreshDataSource()
  }

  onFilterChange(): void {
    if (this.orderDataSource === undefined || this.orderDataSource === null) {
      return
    }
    this.refreshDataSource()
  }

  private refreshDataSource(): void {
    // 绝对防御：orderList 非数组时按空数组处理，避免 LazyForEach 崩溃
    let list: Order[] = []
    if (this.loggedIn && Array.isArray(this.orderList)) {
      list = this.orderList
    }
    let filtered: Order[] = list
    if (this.currentStatus !== -1) {
      filtered = filtered.filter(o => o !== null && typeof o === 'object' && o.status === this.currentStatus)
    }
    this.orderDataSource.setData(filtered)
  }

  /** 支付待付款订单：扣余额并流转到待接单（余额支付模型）。 */
  private async payPendingOrder(order: Order): Promise<void> {
    const paid: Order | null = await payOrderRemote(order.id)
    this.orderList = AppStorage.get<Order[]>('orderList') || []
    this.refreshDataSource()
    if (paid === null) {
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: errorMessage === '' ? '支付失败，请稍后重试' : errorMessage, duration: 3000 })
      return
    }
    promptAction.showToast({ message: `支付成功，已支付 ¥${paid.payAmount.toFixed(2)}`, duration: 2500 })
  }

  /** 取消待付款订单：尚未扣款，仅释放库存与优惠券。 */
  private async cancelPendingOrder(order: Order): Promise<void> {
    const ok: boolean = await cancelOrderRemote(order.id)
    this.orderList = AppStorage.get<Order[]>('orderList') || []
    this.refreshDataSource()
    if (ok) {
      promptAction.showToast({ message: '订单已取消，库存与优惠券已释放', duration: 2400 })
    } else {
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: errorMessage === '' ? '取消订单失败，请稍后重试' : errorMessage, duration: 3000 })
    }
  }

  build() {
    Column() {
      // 导航栏：独立路由页必须自带返回
      PageHeader({ title: '我的订单', backId: 'order-list-back', onBack: () => { router.back() } })

      Scroll() {
        Row({ space: 0 }) {
          ForEach([
            OrderTabItem.create('全部', -1),
            OrderTabItem.create('待付款', 0),
            OrderTabItem.create('待接单', 1),
            OrderTabItem.create('配送中', 3),
            OrderTabItem.create('已完成', 4),
          ], (item: OrderTabItem) => {
            Text(item.title)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentStatus === item.status ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
              .fontWeight(this.currentStatus === item.status ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
              .id(`order-filter-${item.status}`)
              .onClick(() => { this.currentStatus = item.status })
          }, (item: OrderTabItem) => item.title)
        }
        .padding({ left: SPACING.LG, right: SPACING.LG })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').backgroundColor(COLORS.BG_WHITE)

      if (!this.loggedIn) {
        EmptyState({ icon: '🔒', title: '暂无登录', description: '请登录后查看订单' })
      } else if (!Array.isArray(this.orderList) || this.orderList.length === 0) {
        EmptyState({ icon: '📦', title: '暂无订单', description: '快去点一份美味吧' })
      } else {
        Refresh({ refreshing: this.isRefreshing }) {
          List({ space: SPACING.SM }) {
            LazyForEach(this.orderDataSource, (order: Order) => {
              ListItem() {
                this.OrderCard(order)
              }
            }, (item: Order) => item.id.toString())
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.LG })
          .scrollBar(BarState.Off).divider({ strokeWidth: 0 })
          .cachedCount(5)
        }
        .onRefreshing(() => {
          this.orderList = AppStorage.get<Order[]>('orderList') || []
          this.refreshDataSource()
          this.isRefreshing = false
        })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  OrderCard(order: Order) {
    Column({ space: SPACING.SM }) {
      Row() {
        Text(order.storeName)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        Text(getOrderStatusText(order.status, order.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.MD).fontColor(getOrderStatusColor(order.status, order.escrowStatus ?? 0)).fontWeight(FontWeight.Bold)
      }
      ForEach(order.items || [], (item: CartItem) => {
        Row() {
          // 多规格：订单行附带下单时锁定的规格快照
          Text((item.specName ?? '') !== '' ? `${item.goods.name}（${item.specName}）` : item.goods.name)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).layoutWeight(1)
          Text(`x${item.quantity}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.width('100%')
      }, (item: CartItem) => `${item.goods.id}_${item.specId ?? 0}`)
      Row() {
        Text(`共${(order.items || []).reduce((s, i) => s + i.quantity, 0)}件 实付`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(`¥${order.payAmount.toFixed(2)}`)
          .fontSize(FONT_SIZE.LG).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
        Blank()
        if (order.status === 0) {
          // 待付款：可取消（释放库存与优惠券）或立即支付
          Button('取消订单').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .margin({ right: SPACING.SM })
            .onClick(() => { this.cancelPendingOrder(order) })
          Button('立即支付').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(MODULE_COLOR.ORDER).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.payPendingOrder(order) })
        } else if (order.status === 4 && (order.escrowStatus ?? 0) === 0) {
          Button('确认收货并结算').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(MODULE_COLOR.CART).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(async () => {
              const ok: boolean = await confirmOrderRemote(order.id)
              this.orderList = AppStorage.get<Order[]>('orderList') || []
              this.refreshDataSource()
              if (ok) {
                promptAction.showToast({ message: '已确认收货，订单已完成', duration: 1800 })
              } else {
                const errorMessage: string = getLastRemoteErrorMessage()
                promptAction.showToast({ message: errorMessage === '' ? '确认收货失败，请稍后重试' : errorMessage, duration: 2200 })
              }
            })
        } else if (order.status === 3) {
          Text('配送中，送达后可确认收货')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        } else if (order.status === 5) {
          Button('已取消').height(32).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
            .backgroundColor(COLORS.BG_PRIMARY).borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
        }
      }.width('100%')
    }
    .width('100%').padding(SPACING.MD)
    .backgroundColor(MODULE_BG.ORDER).borderRadius(BORDER_RADIUS.LG)
    .id(`order-card-${order.id}`)
    .onClick(() => {
      AppStorage.setOrCreate<Order>('currentOrder', order)
      AppStorage.setOrCreate<number>('currentOrderId', order.id)
      router.pushUrl({ url: 'pages/OrderDetailPage' })
    })
  }
}
