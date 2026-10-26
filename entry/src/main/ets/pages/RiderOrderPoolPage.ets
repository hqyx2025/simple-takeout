import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
/**
 * 抢单大厅（四端改造）：展示待取餐池订单，骑手在线即可抢单
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Order, OrderPageData, Rider, User, UserRole } from '../model/Models'
import { grabOrderRemote, getLastRemoteErrorMessage, fetchRiderProfileRemote, reportRiderLocationRemote, startRiderLocationTimer } from '../service/AppStorageManager'
import { fetchRiderOrdersPageResultApi, fetchRiderPoolResultApi } from '../service/api/RiderApi'
import { logInfo } from '../service/AppLogger'
import { PageHeader } from '../components/PageHeader'

@Entry
@Component
export struct RiderOrderPoolPage {
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

  @State orders: Order[] = []
  @State loading: boolean = false
  @State loadFailed: boolean = false
  @State grabbingOrderId: number = 0
  @State rider: Rider | null = null
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = { id: 0, username: '', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER, balance: 0, coupons: [], orders: [], storeIds: [] }
  private poolRequestVersion: number = 0

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入抢单大厅 RiderOrderPoolPage')
    if (!this.loggedIn || this.user.role !== UserRole.RIDER) {
      promptAction.showToast({ message: '仅骑手账号可以进入抢单大厅', duration: 1600 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    await this.loadPool()
  }

  private async loadPool(): Promise<boolean> {
    const requestVersion: number = this.poolRequestVersion + 1
    this.poolRequestVersion = requestVersion
    this.loading = true
    this.loadFailed = false
    try {
      const rider: Rider | null = await fetchRiderProfileRemote(false)
      const orders: Order[] | null = await fetchRiderPoolResultApi(false)
      if (requestVersion !== this.poolRequestVersion) {
        return false
      }
      if (rider === null || orders === null) {
        this.loadFailed = true
        return false
      }
      this.rider = rider
      this.orders = orders
      return true
    } finally {
      if (requestVersion === this.poolRequestVersion) {
        this.loading = false
      }
    }
  }

  /** 接单范围摘要：没有接单位置就抢不到任何单。 */
  private rangeText(): string {
    if (this.rider === null) {
      return ''
    }
    const radiusMeters: number = this.rider.deliveryRadius ?? 0
    const radiusKm: number = radiusMeters > 0 ? radiusMeters / 1000 : 25
    const latitude: number | undefined = this.rider.latitude
    const longitude: number | undefined = this.rider.longitude
    const hasLocation: boolean = latitude !== undefined && longitude !== undefined
      && Number.isFinite(latitude) && Number.isFinite(longitude) && !(latitude === 0 && longitude === 0)
    if (!hasLocation) {
      return '未设置接单位置：请到骑手中心用地图选点或当前定位，否则抢不到单'
    }
    return `接单范围 ${radiusKm} 公里；平台只把商家与骑手半径内的订单派给你`
  }

  private needsLocation(): boolean {
    if (this.rider === null) {
      return false
    }
    const latitude: number | undefined = this.rider.latitude
    const longitude: number | undefined = this.rider.longitude
    return latitude === undefined || longitude === undefined
      || !Number.isFinite(latitude) || !Number.isFinite(longitude) || (latitude === 0 && longitude === 0)
  }

  private async grab(order: Order): Promise<void> {
    if (this.grabbingOrderId !== 0) {
      promptAction.showToast({ message: '正在抢单，请稍候', duration: 1200 })
      return
    }
    this.grabbingOrderId = order.id
    try {
      let ok: boolean = false
      try {
        ok = await grabOrderRemote(order.id, false)
      } catch (_) {
        ok = false
      }
      if (ok) {
        this.finishGrab()
      } else {
        const errorMessage: string = getLastRemoteErrorMessage()
        const result: OrderPageData | null = await fetchRiderOrdersPageResultApi(1, 30, false)
        const assigned: Order | undefined = result === null ? undefined
          : result.list.find((item: Order) => item.id === order.id && item.status >= 2 && item.status <= 4)
        if (assigned !== undefined) {
          this.finishGrab()
        } else if (result === null) {
          promptAction.showToast({ message: '抢单结果待确认，请到“我的配送单”查看', duration: 2800 })
        } else {
          promptAction.showToast({
            message: errorMessage === '' ? '手慢了，该订单已被其他骑手接走' : errorMessage,
            duration: 2500
          })
          await this.loadPool()
        }
      }
    } finally {
      this.grabbingOrderId = 0
    }
  }

  private finishGrab(): void {
    reportRiderLocationRemote()
    startRiderLocationTimer()
    promptAction.showToast({ message: '抢单成功，请及时取餐', duration: 1500 })
    router.replaceUrl({ url: 'pages/RiderOrdersPage' })
  }

  build() {
    Column() {
      PageHeader({ title: '抢单大厅', backText: '‹ 返回', backId: 'rider-pool-back', titleColor: COLORS.TEXT_PRIMARY, headerBgColor: COLORS.BG_PRIMARY, actionLabel: '刷新', onAction: () => { this.loadPool() }, onBack: () => { router.back() } })

      if (this.rangeText() !== '') {
        Text(this.rangeText())
          .fontSize(FONT_SIZE.XS)
          .fontColor(this.needsLocation() ? COLORS.ERROR : COLORS.TEXT_SECONDARY)
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
          .id('rider-pool-range-hint')
      }

      if (this.loading) {
        Column() {
          Text('正在加载可抢订单…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.loadFailed) {
        Column({ space: SPACING.MD }) {
          Text('抢单信息暂时无法加载').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
          Text('请检查网络后重试').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          Button('重新加载')
            .attributeModifier(new AppButtonStyle()).height(44)
            .id('rider-pool-retry')
            .onClick(() => { this.loadPool() })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.orders.length === 0) {
        Column({ space: SPACING.SM }) {
          Image($r('app.media.login_rider')).width(60).height(60).objectFit(ImageFit.Contain).margin({ top: 40 })
          Text(this.needsLocation() ? '请先设置接单位置' : '暂无待抢订单')
            .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
          Text(this.needsLocation()
            ? '未设置接单位置时，平台无法判断你在哪些商家的配送范围内'
            : '商家出餐后，落在你接单范围内的订单会出现在这里')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).textAlign(TextAlign.Center)
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

      Text('抢单后显示收货信息')
        .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')

      Row() {
        Text(`${getOrderStatusText(order.status)} · ${order.createTime}`)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
        Button(this.grabbingOrderId === order.id ? '抢单中…' : '抢单')
          .attributeModifier(new AppButtonStyle()).height(44).fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY).backgroundColor(MODULE_COLOR.RIDER)
          .borderRadius(BORDER_RADIUS.ROUND)
          .enabled(this.grabbingOrderId === 0)
          .id(`rider-grab-${order.id}`)
          .onClick(() => { this.grab(order) })
      }.width('100%')
    }
      .attributeModifier(new AppCardStyle())
    .width('100%').padding(SPACING.LG)
    .id(`rider-pool-card-${order.id}`)
  }
}
