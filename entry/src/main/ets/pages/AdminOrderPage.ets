import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
/**
 * 管理端-订单管理页（大纲 9.6 订单管理）
 * 全平台托管订单：按状态筛选、查看托管资金状态、异常订单退款（未完成订单可直接退款）
 * 已送达订单（status=4）需走退款审批流程，不在此直接退款
 */
import { AppMotion } from '../common/theme/AppMotion'
import { User, UserRole, OrderActionSource } from '../model/Models'
import { ApiResponse, get, getAuthSessionEpoch } from '../service/HttpClient'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { PageHeader } from '../components/PageHeader'
import { logInfo } from '../service/AppLogger'
import { adminOrderActionApi } from '../service/ApiService'
import { canOrderAction } from '../service/OrderStatus'

interface AdminOrder extends OrderActionSource {
  id: number
  orderNo: string
  storeName: string
  status: number
  payAmount: number
  escrowStatus?: number
  /** 出餐时间：非空表示已出餐并已进入骑手待取餐池（此时 status 仍为 2 制作中） */
  readyTime?: string
}

interface AdminOrderPageData {
  list: AdminOrder[]
  total: number
  page: number
  pageSize: number
  hasMore: boolean
}

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

@Entry
@Component
export struct AdminOrderPage {
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

  @StorageLink('isLoggedIn') @Watch('onOrdersOwnerChange') loggedIn: boolean = false
  @StorageLink('user') @Watch('onOrdersOwnerChange') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State orders: AdminOrder[] = []
  // 当前页结果：避免 build 阶段依赖 getter 计算属性（ArkUI 对 getter 求值存在时序问题）。
  @State displayOrders: AdminOrder[] = []
  @State currentStatus: number = -1
  @State page: number = 1
  @State total: number = 0
  @State hasMore: boolean = false
  @State loading: boolean = false
  @State ordersError: boolean = false
  private ordersRequestVersion: number = 0
  private pageActive: boolean = true
  private retryPage: number = 1
  private retryAppend: boolean = false
  @State actioningOrderId: number = 0
  // 拼进 ForEach 键，强制重建同 id 的订单行（否则刷新后状态/按钮文案停留在旧值）

  aboutToAppear(): void {
    logInfo('Page', '进入管理端订单管理页 AdminOrderPage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  private canApplyOrders(epoch: number, owner: number, version: number): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.pageActive && this.loggedIn && epoch === getAuthSessionEpoch()
      && user?.id === owner && user?.role === UserRole.ADMIN && version === this.ordersRequestVersion
  }

  onPageShow(): void { this.pageActive = true; this.refresh() }

  onPageHide(): void {
    this.pageActive = false
    this.ordersRequestVersion += 1
    this.loading = false
    this.actioningOrderId = 0
  }

  aboutToDisappear(): void { this.onPageHide() }

  onOrdersOwnerChange(): void {
    this.ordersRequestVersion += 1
    this.loading = false
    this.orders = []
    this.displayOrders = []
    this.total = 0
    this.hasMore = false
    this.ordersError = false
    this.actioningOrderId = 0
    if (this.pageActive) { this.refresh() }
  }

  async refresh(): Promise<void> { await this.loadOrders() }

  private async loadMore(): Promise<void> {
    if (!this.loading && this.hasMore) { await this.loadOrders(this.page + 1, true) }
  }

  private async loadOrders(page: number = 1, append: boolean = false): Promise<void> {
    const user: User | undefined = AppStorage.get<User>('user')
    if (!this.pageActive || (this.loading && append) || !this.loggedIn
      || user === undefined || user.id <= 0 || user.role !== UserRole.ADMIN) { return }
    const epoch: number = getAuthSessionEpoch()
    const owner: number = user.id
    const version: number = ++this.ordersRequestVersion
    this.loading = true
    this.ordersError = false
    this.retryPage = page
    this.retryAppend = append
    try {
      const statusQuery: string = this.currentStatus < 0 ? '' : `&status=${this.currentStatus}`
      const resp: ApiResponse<AdminOrderPageData> = await get<AdminOrderPageData>(
        `/api/admin/orders/page?page=${page}&pageSize=50${statusQuery}`, false)
      if (!this.canApplyOrders(epoch, owner, version)) { return }
      if (resp.code !== 200 || resp.data === null || resp.data === undefined || !Array.isArray(resp.data.list)) {
        this.ordersError = true
        return
      }
      this.orders = append ? this.orders.concat(resp.data.list) : resp.data.list
      this.page = resp.data.page
      this.total = resp.data.total
      this.hasMore = resp.data.hasMore
      this.applyFilter()
    } catch (_) {
      if (this.canApplyOrders(epoch, owner, version)) { this.ordersError = true }
    } finally {
      if (this.canApplyOrders(epoch, owner, version)) { this.loading = false }
    }
  }

  /** 按当前状态筛选并写入 displayOrders（显式计算，避免渲染期 getter 求值）。 */
  private applyFilter(): void {
    this.displayOrders = Array.isArray(this.orders) ? this.orders : []
    // 键只含 id 时，刷新回来的同 id 新对象会被 ForEach 复用，退款后状态不刷新。
  }

  /** 切换筛选 Tab。 */
  private onStatusChange(status: number): void {
    this.currentStatus = status
    this.refresh()
  }

  /** 托管资金状态文本：0 托管中 / 1 已结算 / 2 已退款。 */
  private getEscrowText(status: number, escrowStatus?: number): string {
    if (status === 0 || (status === 5 && (escrowStatus ?? 0) === 0)) {
      return '未扣款'
    }
    if (escrowStatus === 1) {
      return '已结算'
    }
    if (escrowStatus === 2) {
      return '已退款'
    }
    return '托管中'
  }

  private getEscrowColor(escrowStatus?: number): ResourceColor {
    if (escrowStatus === 1) {
      return COLORS.SUCCESS
    }
    if (escrowStatus === 2) {
      return COLORS.TEXT_HINT
    }
    return COLORS.WARNING
  }

  private canRunOrderAction(order: AdminOrder, action: string): boolean {
    switch (action) {
      case 'accept': return canOrderAction(order, 'MERCHANT_ACCEPT', order.status === 1)
      case 'ready': return canOrderAction(order, 'MERCHANT_READY', order.status === 2 && (order.readyTime ?? '') === '')
      case 'deliver': return canOrderAction(order, 'MERCHANT_DELIVER', false)
      case 'complete': return canOrderAction(order, 'MERCHANT_COMPLETE', order.status === 3)
      case 'cancel': return canOrderAction(order, 'CANCEL', order.status >= 0 && order.status <= 3)
      default: return false
    }
  }

  async runOrderAction(orderId: number, action: string, successText: string): Promise<void> {
    const current: AdminOrder | undefined = this.orders.find((order: AdminOrder) => order.id === orderId)
    if (!this.pageActive || !this.loggedIn || this.loading || this.user.role !== UserRole.ADMIN
      || current === undefined || !this.canRunOrderAction(current, action)) { return }
    if (this.actioningOrderId !== 0) {
      promptAction.showToast({ message: '该订单操作正在处理，请稍候', duration: 1200 })
      return
    }
    const epoch: number = getAuthSessionEpoch()
    const owner: number = this.user.id
    const version: number = this.ordersRequestVersion
    this.actioningOrderId = orderId
    const ok: boolean = await adminOrderActionApi(orderId, action)
    if (!this.canApplyOrders(epoch, owner, version)) { return }
    this.actioningOrderId = 0
    if (ok) {
      promptAction.showToast({ message: successText, duration: 1400 })
      await this.refresh()
    }
  }

  @Builder
  AdminOrderActions(order: AdminOrder) {
    if (this.canRunOrderAction(order, 'accept')) {
      Button('接单').attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
        .enabled(this.actioningOrderId === 0 && !this.loading).id(`admin-order-accept-${order.id}`)
        .onClick(() => { this.runOrderAction(order.id, 'accept', '订单已接单') })
    }
    if (this.canRunOrderAction(order, 'ready')) {
      Button('出餐').attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
        .enabled(this.actioningOrderId === 0 && !this.loading).id(`admin-order-ready-${order.id}`)
        .onClick(() => { this.runOrderAction(order.id, 'ready', '已出餐，配送方式以订单为准') })
    }
    if (this.canRunOrderAction(order, 'deliver')) {
      Button('开始商家配送').attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
        .enabled(this.actioningOrderId === 0 && !this.loading).id(`admin-order-deliver-${order.id}`)
        .onClick(() => { this.runOrderAction(order.id, 'deliver', '订单已进入商家配送') })
    }
    if (this.canRunOrderAction(order, 'complete')) {
      Button('确认送达').attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
        .enabled(this.actioningOrderId === 0 && !this.loading).id(`admin-order-complete-${order.id}`)
        .onClick(() => { this.runOrderAction(order.id, 'complete', '订单已标记送达') })
    }
    if (this.canRunOrderAction(order, 'cancel')) {
      Button(order.status === 0 ? '取消' : '取消并退款').attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.ERROR).enabled(this.actioningOrderId === 0 && !this.loading).id(`admin-order-cancel-${order.id}`)
        .onClick(() => { this.runOrderAction(order.id, 'cancel', order.status === 0 ? '订单已取消' : '订单已取消并退款') })
    }
    if (order.status === 2 && (order.readyTime ?? '') !== '' && !this.canRunOrderAction(order, 'deliver')) {
      Text('已出餐，等待骑手接单').fontSize(FONT_SIZE.XS).fontColor(COLORS.SUCCESS)
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      PageHeader({
        title: '订单管理',
        backId: 'admin-order-back',
        headerBgColor: COLORS.BG_PRIMARY,
        actionColor: MODULE_COLOR.ADMIN,
        actionLabel: '刷新',
        onBack: () => { router.back() },
        onAction: () => { this.refresh() }
      })

      Button('配送异常处理').attributeModifier(new AppButtonStyle()).height(44).width('100%')
        .id('admin-delivery-issues').onClick(() => { router.pushUrl({ url: 'pages/OrderSupportPage' }) })

      // 状态筛选 Tab
      Scroll() {
        Row({ space: 0 }) {
          ForEach([
            OrderTabItem.create('全部', -1),
            OrderTabItem.create('待付款', 0),
            OrderTabItem.create('待接单', 1),
            OrderTabItem.create('制作中', 2),
            OrderTabItem.create('配送中', 3),
            OrderTabItem.create('已送达', 4),
            OrderTabItem.create('已取消', 5),
            OrderTabItem.create('退款中', 6)
          ], (item: OrderTabItem) => {
            Text(item.title)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentStatus === item.status ? MODULE_COLOR.ADMIN : COLORS.TEXT_SECONDARY)
              .fontWeight(this.currentStatus === item.status ? FontWeight.Bold : FontWeight.Normal)
              .backgroundColor(this.currentStatus === item.status ? MODULE_BG.ADMIN : Color.Transparent)
              .borderRadius(BORDER_RADIUS.ROUND)
              .border({ width: this.currentStatus === item.status ? 2 : 0, color: MODULE_COLOR.ADMIN })
              .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
              .onClick(() => { this.onStatusChange(item.status) })
          }, (item: OrderTabItem) => item.title)
        }
        .padding({ left: SPACING.LG, right: SPACING.LG })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').backgroundColor(MODULE_BG.ADMIN)

      if (this.ordersError) {
        Button('订单加载失败，点击重试（保留上次数据）')
          .attributeModifier(new AppButtonStyle()).enabled(!this.loading)
          .id('admin-order-retry')
          .onClick(() => { this.loadOrders(this.retryPage, this.retryAppend) })
      }

      // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
      List({ space: SPACING.MD }) {
        ListItem() {
          Text('支付后托管，确认收货后结算；送达48小时内含已确认、已评价仍可售后。制作后取消不恢复库存；已付用户主动取消不返券，平台/商家取消退有效券。')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
        }

        if (!Array.isArray(this.displayOrders) || this.displayOrders.length === 0) {
          ListItem() {
            Text('暂无该状态订单').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%').padding(SPACING.MD)
          }
        }
        ForEach(this.displayOrders, (order: AdminOrder) => {
          ListItem() {
            Row({ space: SPACING.MD }) {
              Text(order.storeName.substring(0, 1))
                .width(40).height(40).textAlign(TextAlign.Center)
                .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
                .fontColor(accentFg(accentIndexFromText(order.storeName)))
                .backgroundColor(accentBg(accentIndexFromText(order.storeName)))
                .borderRadius(BORDER_RADIUS.ROUND)
              Column({ space: SPACING.XS }) {
                Text(`${order.storeName}  #${order.orderNo}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
                Row({ space: SPACING.SM }) {
                  Text(getOrderStatusText(order.status, order.escrowStatus))
                    .fontSize(FONT_SIZE.SM).fontColor(getOrderStatusColor(order.status))
                  Text(`资金：${this.getEscrowText(order.status, order.escrowStatus)}`)
                    .fontSize(FONT_SIZE.SM).fontColor(this.getEscrowColor(order.escrowStatus))
                }
                Text(`订单金额 ¥${(order.payAmount ?? 0).toFixed(2)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              this.AdminOrderActions(order)
            }
              .attributeModifier(new AppCardStyle())
            .width('100%').padding(SPACING.MD)
          }
        }, (order: AdminOrder) => `${order.id}`)
        ListItem() {
          Row({ space: SPACING.SM }) {
            Text(`已显示 ${this.displayOrders.length} / ${this.total}`)
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
            if (this.hasMore) {
              Button(this.loading ? '加载中' : '加载更多')
                .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.XS)
                .enabled(!this.loading).id('admin-order-load-more').onClick(() => { this.loadMore() })
            }
          }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.MD })
        }
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })

    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
