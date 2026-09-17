/**
 * 我的配送单（四端改造）：骑手已接订单，取餐 / 送达
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Order } from '../model/Models'
import { syncRiderOrdersRemote, pickupOrderRemote, deliverOrderRemote, getLastRemoteErrorMessage, reportRiderLocationRemote } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'

/** 配送途中的位置上报间隔（毫秒）：接单后进入配送阶段开始周期性上报 */
const RIDER_REPORT_INTERVAL_MS: number = 30000

@Entry
@Component
export struct RiderOrdersPage {
  @State orders: Order[] = []
  @State loading: boolean = false
  @State acting: boolean = false
  // 配送途中的实时定位定时器（-1 表示未开启）
  private locationTimer: number = -1

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入我的配送单 RiderOrdersPage')
    await this.loadOrders()
  }

  /** 离开页面停止上报，避免后台空转耗电 */
  onPageHide(): void {
    this.stopLocationReporting()
  }

  private async loadOrders(): Promise<void> {
    this.loading = true
    this.orders = await syncRiderOrdersRemote()
    this.loading = false
    this.syncLocationReporting()
  }

  /**
   * 配送途中实时定位：只要名下有"配送中(status=3)"的订单，就每 30 秒上报一次骑手位置；
   * 没有配送中订单（还没取餐或已送达）就停掉，避免无意义的后台定位。
   */
  private syncLocationReporting(): void {
    const delivering: boolean = this.orders.some((order: Order) => order.status === 3)
    if (delivering && this.locationTimer < 0) {
      this.locationTimer = setInterval(() => { reportRiderLocationRemote() }, RIDER_REPORT_INTERVAL_MS)
      logInfo('Rider', `开始配送途中位置上报（每 ${RIDER_REPORT_INTERVAL_MS / 1000} 秒一次）`)
      // 取餐后立刻补一次，不等第一个周期
      reportRiderLocationRemote()
    } else if (!delivering) {
      this.stopLocationReporting()
    }
  }

  private stopLocationReporting(): void {
    if (this.locationTimer >= 0) {
      clearInterval(this.locationTimer)
      this.locationTimer = -1
      logInfo('Rider', '已无配送中订单，停止位置上报')
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
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('我的配送单')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.RIDER)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('刷新')
          .fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.RIDER)
          .onClick(() => { this.loadOrders() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(MODULE_BG.RIDER)

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
