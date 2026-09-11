/**
 * 我的配送单（四端改造）：骑手已接订单，取餐 / 送达
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText } from '../common/Constants'
import { Order } from '../model/Models'
import { syncRiderOrdersRemote, pickupOrderRemote, deliverOrderRemote } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct RiderOrdersPage {
  @State orders: Order[] = []
  @State loading: boolean = false
  @State acting: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入我的配送单 RiderOrdersPage')
    await this.loadOrders()
  }

  private async loadOrders(): Promise<void> {
    this.loading = true
    this.orders = await syncRiderOrdersRemote()
    this.loading = false
  }

  private async pickup(order: Order): Promise<void> {
    if (this.acting) {
      return
    }
    this.acting = true
    const ok: boolean = await pickupOrderRemote(order.id)
    this.acting = false
    if (ok) {
      promptAction.showToast({ message: '已取餐，开始配送', duration: 1500 })
    } else {
      promptAction.showToast({ message: '取餐失败，请确认订单状态', duration: 2000 })
    }
    await this.loadOrders()
  }

  private async deliver(order: Order): Promise<void> {
    if (this.acting) {
      return
    }
    this.acting = true
    const ok: boolean = await deliverOrderRemote(order.id)
    this.acting = false
    if (ok) {
      promptAction.showToast({ message: '已送达', duration: 1500 })
    } else {
      promptAction.showToast({ message: '送达失败，请确认订单状态', duration: 2000 })
    }
    await this.loadOrders()
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('我的配送单')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('刷新')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
          .onClick(() => { this.loadOrders() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      if (this.loading) {
        Column() {
          Text('正在加载配送单…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.orders.length === 0) {
        Column() {
          Text('🛵').fontSize(60).margin({ top: 40 })
          Text('暂无配送单').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: SPACING.SM }) {
            ForEach(this.orders, (order: Order) => {
              this.OrderCard(order)
            }, (order: Order) => order.id.toString())
          }
          .width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  OrderCard(order: Order) {
    Column({ space: SPACING.XS }) {
      Row() {
        Text(`🏪 ${order.storeName}`)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(getOrderStatusText(order.status, order.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY).fontWeight(FontWeight.Bold)
      }.width('100%')

      Text(`收货：${order.address.name} ${order.address.phone}`)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      Text(`地址：${order.address.detail}`)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        Text(`¥${order.payAmount.toFixed(2)} · ${order.createTime}`)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
        if (order.status === 2) {
          Button('取餐')
            .height(36).fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .id(`rider-pickup-${order.id}`)
            .onClick(() => { this.pickup(order) })
        } else if (order.status === 3) {
          Button('送达')
            .height(36).fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.SUCCESS)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .id(`rider-deliver-${order.id}`)
            .onClick(() => { this.deliver(order) })
        }
      }.width('100%')
    }
    .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    .id(`rider-order-card-${order.id}`)
  }
}
