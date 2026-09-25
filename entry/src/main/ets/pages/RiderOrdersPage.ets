/**
 * 我的配送单（四端改造）：骑手已接订单，取餐 / 送达
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Order } from '../model/Models'
import { syncRiderOrdersRemote, pickupOrderRemote, deliverOrderRemote, getLastRemoteErrorMessage, reportRiderLocationRemote, startRiderLocationTimer, stopRiderLocationTimer } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'
import { PageHeader } from '../components/PageHeader'

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

  /**
   * 加载并排序配送单：
   * ① 需要操作的（取餐/送达）按 readyTime 升序排在最上面——越早出餐越先取；
   * ② 已完成的按 completeTime 降序排在下面——最近完成的最靠上。
   */
  private sortOrders(orders: Order[]): Order[] {
    const O = [...orders]
    O.sort((a: Order, b: Order) => {
      const aActive: boolean = a.status === 2 || a.status === 3
      const bActive: boolean = b.status === 2 || b.status === 3
      if (aActive && !bActive) {
        return -1
      }
      if (!aActive && bActive) {
        return 1
      }
      if (aActive) {
        const aReady: string = a.readyTime ?? ''
        const bReady: string = b.readyTime ?? ''
        return aReady.localeCompare(bReady)
      }
      const aDone: string = a.completeTime ?? a.createTime ?? ''
      const bDone: string = b.completeTime ?? b.createTime ?? ''
      return bDone.localeCompare(aDone)
    })
    return O
  }

  private async loadOrders(): Promise<void> {
    this.loading = true
    const raw: Order[] = await syncRiderOrdersRemote()
    this.orders = this.sortOrders(raw)
    this.loading = false
    // 全局定时器按「有无配送中订单」开关，切页不中断
    if (this.orders.some((order: Order) => order.status === 3)) {
      startRiderLocationTimer()
    } else {
      stopRiderLocationTimer()
    }
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
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({
        message: errorMessage === '' ? '取餐失败，请确认订单状态' : errorMessage,
        duration: 2500
      })
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
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({
        message: errorMessage === '' ? '送达失败，请确认订单状态' : errorMessage,
        duration: 2500
      })
    }
    await this.loadOrders()
  }

  build() {
    Column() {
      PageHeader({ title: '我的配送单', backText: '‹ 返回', backId: 'rider-orders-back', titleColor: MODULE_COLOR.RIDER, headerBgColor: MODULE_BG.RIDER, actionLabel: '刷新', onAction: () => { this.loadOrders() }, onBack: () => { router.back() } })

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
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
        List({ space: SPACING.SM }) {
          ForEach(this.orders, (order: Order) => {
            ListItem() {
              this.OrderCard(order)
            }
          }, (order: Order) => order.id.toString())
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  OrderCard(order: Order) {
    Column({ space: SPACING.XS }) {
      Row({ space: SPACING.SM }) {
        Text(order.storeName.substring(0, 1))
          .width(32).height(32).textAlign(TextAlign.Center)
          .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
          .fontColor(accentFg(accentIndexFromText(order.storeName)))
          .backgroundColor(accentBg(accentIndexFromText(order.storeName)))
          .borderRadius(BORDER_RADIUS.MD)
        Text(order.storeName)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(getOrderStatusText(order.status, order.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.RIDER).fontWeight(FontWeight.Bold)
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
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.RIDER)
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
