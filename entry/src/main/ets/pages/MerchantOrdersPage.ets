/**
 * 商户订单管理页
 * 按状态Tab分类展示商户所有店铺订单
 * 支持接单(1→2)、出餐(2→3)、确认送达(3→4)状态流转
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor } from '../common/Constants'
import { Order, CartItem, User } from '../model/Models'
import { getCurrentUser, getMerchantOrders, merchantActionRemote, syncMerchantOrdersFromServer } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

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
  @State currentStatus: number = -1
  @State allOrders: Order[] = []
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
    if (user !== undefined && user !== null) {
      this.merchantId = user.id
      this.loadOrders()
    }
  }

  private async loadOrders(): Promise<void> {
    // 先从后端拉取最新订单，再按本地商户过滤展示
    await syncMerchantOrdersFromServer()
    if (this.merchantId > 0) {
      this.allOrders = getMerchantOrders(this.merchantId)
    }
  }

  private getFilteredOrders(): Order[] {
    if (this.currentStatus === -1) {
      return this.allOrders
    }
    return this.allOrders.filter(o => o.status === this.currentStatus)
  }

  private async handleAccept(order: Order): Promise<void> {
    await merchantActionRemote(order.id, 'accept')
    logInfo('Merchant', `点击接单 orderId=${order.id} 店铺=${order.storeName}`)
    promptAction.showToast({ message: '已接单' })
    this.loadOrders()
  }

  private async handleStartDelivery(order: Order): Promise<void> {
    await merchantActionRemote(order.id, 'deliver')
    logInfo('Merchant', `点击出餐 orderId=${order.id} 店铺=${order.storeName}`)
    promptAction.showToast({ message: '已出餐，配送中' })
    this.loadOrders()
  }

  private async handleComplete(order: Order): Promise<void> {
    await merchantActionRemote(order.id, 'complete')
    logInfo('Merchant', `点击确认送达 orderId=${order.id} 店铺=${order.storeName}`)
    promptAction.showToast({ message: '已确认送达' })
    this.loadOrders()
  }

  build() {
    Column() {
      // 顶部导航栏：标题 + 返回按钮
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('订单管理')
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

      // 状态Tab栏（横向滚动）
      Scroll() {
        Row({ space: SPACING.SM }) {
          ForEach(this.statusTabs, (tab: OrderStatusTab) => {
            Text(tab.name)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentStatus === tab.status ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
              .backgroundColor(this.currentStatus === tab.status ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
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
          Text('📭').fontSize(60).margin({ top: 100 })
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
          }, (order: Order) => order.id.toString())
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
        Text(order.storeName)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
        Text(getOrderStatusText(order.status))
          .fontSize(FONT_SIZE.MD)
          .fontColor(getOrderStatusColor(order.status))
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
        }, (item: CartItem) => `${item.goods.id}`)
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
  }

  @Builder
  OrderAction(order: Order) {
    if (order.status === 1) {
      // 待接单：接单按钮（1→2）
      Button('接单')
        .height(32)
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .onClick(() => { this.handleAccept(order) })
    } else if (order.status === 2) {
      // 制作中：出餐按钮（2→3）
      Button('出餐')
        .height(32)
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .onClick(() => { this.handleStartDelivery(order) })
    } else if (order.status === 3) {
      // 配送中：确认送达按钮（3→4）
      Button('确认送达')
        .height(32)
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_WHITE)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .onClick(() => { this.handleComplete(order) })
    } else if (order.status === 4) {
      // 已完成：仅文字
      Text('已完成')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
    } else if (order.status === 5) {
      // 已取消：仅文字
      Text('已取消')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
    }
  }
}
