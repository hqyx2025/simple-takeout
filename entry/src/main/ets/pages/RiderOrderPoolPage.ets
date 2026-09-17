/**
 * 抢单大厅（四端改造）：展示待取餐池订单，骑手在线即可抢单
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Order } from '../model/Models'
import { syncRiderPoolRemote, grabOrderRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct RiderOrderPoolPage {
  @State orders: Order[] = []
  @State loading: boolean = false
  @State grabbing: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入抢单大厅 RiderOrderPoolPage')
    await this.loadPool()
  }

  private async loadPool(): Promise<void> {
    this.loading = true
    this.orders = await syncRiderPoolRemote()
    this.loading = false
  }

  private async grab(order: Order): Promise<void> {
    if (this.grabbing) {
      promptAction.showToast({ message: '正在抢单，请稍候', duration: 1200 })
      return
    }
    this.grabbing = true
    const ok: boolean = await grabOrderRemote(order.id)
    this.grabbing = false
    if (ok) {
      promptAction.showToast({ message: '抢单成功，请及时取餐', duration: 1500 })
      await this.loadPool()
    } else {
      // 抢单失败可能因为被抢走、未上线、账号停用等，优先展示后端原因，避免全部误报成"手慢了"
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({
        message: errorMessage === '' ? '手慢了，该订单已被其他骑手接走' : errorMessage,
        duration: 2500
      })
      await this.loadPool()
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('抢单大厅')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.RIDER)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('刷新')
          .fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.RIDER)
          .onClick(() => { this.loadPool() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(MODULE_BG.RIDER)

      if (this.loading) {
        Column() {
          Text('正在加载可抢订单…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.orders.length === 0) {
        Column() {
          Text('🛵').fontSize(60).margin({ top: 40 })
          Text('暂无待抢订单').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
        List({ space: SPACING.SM }) {
          ForEach(this.orders, (order: Order) => {
            ListItem() {
              this.PoolCard(order)
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
  PoolCard(order: Order) {
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
        Text(`配送费 ¥${order.deliveryFee.toFixed(2)}`)
          .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.RIDER).fontWeight(FontWeight.Bold)
      }.width('100%')

      Text(`收货：${order.address.name} ${order.address.phone}`)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      Text(`地址：${order.address.detail}`)
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        Text(`${getOrderStatusText(order.status)} · ${order.createTime}`)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
        Button('抢单')
          .height(36).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.RIDER)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .id(`rider-grab-${order.id}`)
          .onClick(() => { this.grab(order) })
      }.width('100%')
    }
    .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    .id(`rider-pool-card-${order.id}`)
  }
}
