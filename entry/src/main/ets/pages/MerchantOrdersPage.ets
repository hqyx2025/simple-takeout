/**
 * 商户订单管理页
 * 按状态Tab分类展示商户所有店铺订单
 * 支持接单(1→2)、出餐(2→3)、确认送达(3→4)状态流转
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Order, CartItem, User, UserRole } from '../model/Models'
import { getCurrentUser, getMerchantOrders, merchantActionRemote, syncMerchantOrdersFromServer } from '../service/AppStorageManager'
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

@Entry
@Component
export struct MerchantOrdersPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State currentStatus: number = -1
  @State allOrders: Order[] = []
  // 列表重建触发器：syncMerchantOrdersFromServer 是**原地修改**同一批 Order 对象，
  // 只重新赋值数组时 ArkUI 按 id 复用旧列表项、不会重绘，于是「点了接单界面仍显示待接单」
  // （设备实测确认）。把它拼进 ForEach key，强制重建（与购物车 cartRenderVersion 同一套路）。
  @State renderVersion: number = 0
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

  private async loadOrders(): Promise<void> {
    // 先从后端拉取最新订单，再按本地商户过滤展示
    await syncMerchantOrdersFromServer()
    if (this.merchantId > 0) {
      this.allOrders = getMerchantOrders(this.merchantId)
      this.renderVersion += 1
    }
  }

  private getFilteredOrders(): Order[] {
    if (this.currentStatus === -1) {
      return this.allOrders
    }
    return this.allOrders.filter(o => o.status === this.currentStatus)
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
        headerBgColor: MODULE_BG.MERCHANT,
        actionColor: MODULE_COLOR.MERCHANT,
        onBack: () => { router.back() }
      })

      // 状态Tab栏（横向滚动）
      Scroll() {
        Row({ space: SPACING.SM }) {
          ForEach(this.statusTabs, (tab: OrderStatusTab) => {
            Text(tab.name)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentStatus === tab.status ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
              .backgroundColor(this.currentStatus === tab.status ? MODULE_COLOR.MERCHANT : COLORS.BG_PRIMARY)
              .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.currentStatus = tab.status })
          }, (tab: OrderStatusTab) => tab.status.toString())
        }
        .padding({ left: SPACING.LG, right: SPACING.LG })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(48)
      .backgroundColor(COLORS.BG_WHITE)

      // 订单列表 / 空状态
      if (this.getFilteredOrders().length === 0) {
        Column() {
          Text('📭').fontSize(32).margin({ top: 40 })
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
          }, (order: Order) => `${this.renderVersion}-${order.id}`)
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
  OrderCard(order: Order) {
    Column({ space: SPACING.SM }) {
      // 店铺名 + 订单状态
      Row() {
        Text('🏪')
          .fontSize(FONT_SIZE.MD)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
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
            Text(item.goods.name)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_PRIMARY)
              .layoutWeight(1)
            Text(`x${item.quantity}`)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
          }
          .width('100%')
        }, (item: CartItem) => `${item.goods.id}_${item.specId ?? 0}`)
      }
      .width('100%')
      .padding({ top: SPACING.XS, bottom: SPACING.XS })

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
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .id(`merchant-order-card-${order.id}`)
  }

  @Builder
  OrderAction(order: Order) {
    if (order.status === 1) {
      // 待接单：接单按钮（1→2）
      Button('接单')
        .height(32)
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(MODULE_COLOR.MERCHANT)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .id(`merchant-action-${order.id}`)
        .onClick(() => { this.handleAccept(order) })
    } else if (order.status === 2) {
      if ((order.riderName ?? '') !== '') {
        // 已被骑手接单：商户侧不再有可执行动作，等骑手取餐即可
        Text(`骑手 ${order.riderName} 已接单，等待取餐`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(MODULE_COLOR.MERCHANT)
      } else if ((order.readyTime ?? '') !== '') {
        // 已出餐并进入骑手待取餐池：状态仍是制作中，必须给可见凭据，否则商户以为没点上
        Text('已出餐，等待骑手接单')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.SUCCESS)
          .id(`merchant-ready-${order.id}`)
      } else {
        // 制作中：出餐完成（写 ready_time，进入骑手待取餐池）
        Button('出餐完成')
          .height(32)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(MODULE_COLOR.MERCHANT)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .id(`merchant-action-${order.id}`)
          .onClick(() => { this.handleReady(order) })
      }
    } else if (order.status === 3) {
      if ((order.riderName ?? '') !== '') {
        // 骑手配送中：由骑手送达，商户不需要也不能确认送达
        Text(`骑手 ${order.riderName} 配送中`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(MODULE_COLOR.MERCHANT)
      } else {
        // 未分配骑手的订单仍保留商户自行确认送达（兼容无骑手时的自配送）
        Button('确认送达')
          .height(32)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(MODULE_COLOR.MERCHANT)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .id(`merchant-action-${order.id}`)
          .onClick(() => { this.handleComplete(order) })
      }
    } else if (order.status === 4) {
      // 已送达待确认收货 / 已结算完成（与大纲 6.4 口径一致）
      Text(getOrderStatusText(order.status, order.escrowStatus ?? 0))
        .fontSize(FONT_SIZE.SM)
        .fontColor(order.escrowStatus === 1 ? COLORS.TEXT_HINT : COLORS.WARNING)
    } else if (order.status === 5) {
      // 已取消：仅文字
      Text('已取消')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
    }
  }
}
