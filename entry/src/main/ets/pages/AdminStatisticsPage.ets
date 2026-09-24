/** 平台经营统计：订单、GMV、托管资金与热销商品。 */
import { ColorMetrics } from '@kit.ArkUI';
import { AdminHotGoods, AdminOrderStatusCount, AdminStatisticsData, AdminTopStore, AdminTrendPoint, User, UserRole } from '../model/Models'
import { fetchAdminDashboardApi, fetchAdminOrderTrendApi, fetchAdminStatisticsApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

@Entry
@Component
export struct AdminStatisticsPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State stats: AdminStatisticsData | null = null
  @State trend: AdminTrendPoint[] = []
  @State orderStatuses: AdminOrderStatusCount[] = []
  @State topStores: AdminTopStore[] = []
  @State loading: boolean = false
  private trendChartContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))

  aboutToAppear(): void {
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入统计页', duration: 1600 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      promptAction.showToast({ message: '统计数据正在刷新，请稍候', duration: 1200 })
      return
    }
    this.loading = true
    this.stats = await fetchAdminStatisticsApi(10)
    this.trend = await fetchAdminOrderTrendApi(7)
    const dashboard = await fetchAdminDashboardApi()
    if (dashboard !== null) {
      this.orderStatuses = dashboard.orderStatuses
      this.topStores = dashboard.topStores
    }
    this.loading = false
  }

  private valueOrZero(value: number | undefined): string {
    return (value ?? 0).toFixed(2)
  }

  build() {
    Column() {
      Row() {
        Text('返回').fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.ADMIN).onClick(() => { router.back() })
        Text('平台统计').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.ADMIN).layoutWeight(1).textAlign(TextAlign.Center)
        Button(this.loading ? '加载中' : '刷新').height(32).fontSize(FONT_SIZE.SM)
          .onClick(() => { this.refresh() })
      }.width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 }).backgroundColor(MODULE_BG.ADMIN)

      // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一块内容不在顶部
      List({ space: SPACING.MD }) {
        if (this.stats === null) {
          ListItem() {
            Text('暂无统计数据，请稍后刷新').width('100%').padding(SPACING.LG).fontColor(COLORS.TEXT_HINT)
          }
        } else {
          ListItem() {
            Row({ space: SPACING.SM }) {
              this.Metric('用户', this.stats.totalUsers.toString(), false)
              this.Metric('商户', this.stats.totalMerchants.toString(), false)
              this.Metric('店铺', this.stats.totalStores.toString(), false)
              this.Metric('商品', this.stats.totalGoods.toString(), false)
            }.width('100%')
          }
          ListItem() {
            Row({ space: SPACING.SM }) {
              this.Metric('订单', this.stats.totalOrders.toString(), false)
              this.Metric('累计成交', `¥${this.valueOrZero(this.stats.totalGmv)}`, true)
              this.Metric('已结算', `¥${this.valueOrZero(this.stats.settledAmount)}`, false)
              this.Metric('待结算', `¥${this.valueOrZero(this.stats.pendingEscrowAmount)}`, false)
            }.width('100%')
          }
          ListItem() {
            Row({ space: SPACING.MD }) {
              Text(`今日订单：${this.stats.todayOrders}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
              Text(`今日成交：¥${this.valueOrZero(this.stats.todayGmv)}`).fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.ADMIN)
            }.width('100%').padding(SPACING.MD).backgroundColor(MODULE_BG.ADMIN).borderRadius(BORDER_RADIUS.MD)
          }
          ListItem() {
            this.SectionTitle('近7日订单趋势', 0)
          }
          ListItem() {
            Canvas(this.trendChartContext)
              .width('100%')
              .height(190)
              .backgroundColor(COLORS.BG_WHITE)
              .borderRadius(BORDER_RADIUS.MD)
              .onReady(() => { this.drawTrendChart() })
          }
          ListItem() {
            this.SectionTitle('热销商品排行', 1)
          }
          ForEach(this.stats.hotGoods, (item: AdminHotGoods) => {
            ListItem() {
              this.HotGoodsRow(item.goodsName, item.storeName, item.sales, item.price, item.status)
            }
          }, (item: AdminHotGoods) => item.goodsId.toString())
          ListItem() {
            this.SectionTitle('订单状态分布', 2)
          }
          ListItem() {
            Row({ space: SPACING.SM }) {
              ForEach(this.orderStatuses, (s: AdminOrderStatusCount) => {
                Text(`${this.statusLabel(s.status)} ${s.count}`)
                  .fontSize(FONT_SIZE.XS).fontColor(accentFg(accentIndexFromText(this.statusLabel(s.status))))
                  .padding({ left: SPACING.SM, right: SPACING.SM, top: 4, bottom: 4 })
                  .backgroundColor(accentBg(accentIndexFromText(this.statusLabel(s.status))))
                  .borderRadius(BORDER_RADIUS.SM)
              }, (s: AdminOrderStatusCount) => s.status.toString())
            }
            .width('100%')
          }
          ListItem() {
            this.SectionTitle('店铺成交额排行', 3)
          }
          ForEach(this.topStores, (store: AdminTopStore, index: number) => {
            ListItem() {
              this.TopStoreRow(index + 1, store)
            }
          }, (store: AdminTopStore) => store.storeId.toString())
        }
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  /** 分区标题：小色块 + 主题色文字 + 浅底标题条（模块标题层级感）。 */
  @Builder
  SectionTitle(title: string, index: number) {
    Row({ space: SPACING.SM }) {
      Text('•')
        .width(28).height(28).textAlign(TextAlign.Center)
        .fontColor(accentFg(index)).backgroundColor(accentBg(index))
        .borderRadius(BORDER_RADIUS.SM)
      Text(title).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.ADMIN)
    }
    .width('100%').padding({ left: SPACING.SM, right: SPACING.SM, top: SPACING.XS, bottom: SPACING.XS })
    .backgroundColor(MODULE_BG.ADMIN).borderRadius(BORDER_RADIUS.MD)
  }

  private statusLabel(status: number): string {
    switch (status) {
      case 0: return '待付款'
      case 1: return '待接单'
      case 2: return '制作中'
      case 3: return '配送中'
      case 4: return '已送达'
      case 5: return '已取消'
      case 6: return '退款中'
      default: return `状态${status}`
    }
  }

  @Builder
  TopStoreRow(rank: number, store: AdminTopStore) {
    Row({ space: SPACING.MD }) {
      Text(`${rank}`).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
        .fontColor(rank <= 3 ? accentFg(rank - 1) : COLORS.TEXT_HINT).width(28).textAlign(TextAlign.Center)
      Text(store.storeName.substring(0, 1))
        .width(36).height(36).textAlign(TextAlign.Center)
        .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
        .fontColor(accentFg(accentIndexFromText(store.storeName)))
        .backgroundColor(accentBg(accentIndexFromText(store.storeName)))
        .borderRadius(BORDER_RADIUS.ROUND)
      Text(store.storeName).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).layoutWeight(1)
      Text(`成交 ¥${store.gmv.toFixed(2)}`).fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.ADMIN)
    }
    .width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
  }

  @Builder
  Metric(title: string, value: string, highlight: boolean) {
    Column({ space: SPACING.XS }) {
      Text(value).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
        .fontColor(highlight ? COLORS.PRIMARY : accentFg(accentIndexFromText(title)))
      Text(title).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
    }.layoutWeight(1).padding({ top: SPACING.MD, bottom: SPACING.MD })
    .backgroundColor(accentBg(accentIndexFromText(title))).borderRadius(BORDER_RADIUS.MD)
  }

  @Builder
  HotGoodsRow(name: string, storeName: string, sales: number, price: number, status: number) {
    Row({ space: SPACING.MD }) {
      Text(name.substring(0, 1))
        .width(36).height(36).textAlign(TextAlign.Center)
        .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
        .fontColor(accentFg(accentIndexFromText(name)))
        .backgroundColor(accentBg(accentIndexFromText(name)))
        .borderRadius(BORDER_RADIUS.ROUND)
      Column({ space: SPACING.XS }) {
        Text(name).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
        Text(`${storeName}  ¥${price.toFixed(2)}  销量${sales}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(status === 1 ? '上架' : '下架').fontSize(FONT_SIZE.XS).fontColor(status === 1 ? COLORS.SUCCESS : COLORS.ERROR)
    }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
  }

  /** 近7日订单趋势折线图（复用商户端 Canvas 画法）。 */
  private drawTrendChart(): void {
    const ctx: CanvasRenderingContext2D = this.trendChartContext
    const width: number = ctx.width
    const height: number = ctx.height
    const paddingLeft: number = 36
    const paddingBottom: number = 22
    const paddingTop: number = 10
    const chartW: number = width - paddingLeft - 10
    const chartH: number = height - paddingTop - paddingBottom

    ctx.clearRect(0, 0, width, height)
    if (this.trend.length < 2) {
      return
    }
    let maxCount: number = 0
    for (let i = 0; i < this.trend.length; i++) {
      if (this.trend[i].orderCount > maxCount) {
        maxCount = this.trend[i].orderCount
      }
    }
    if (maxCount <= 0) {
      maxCount = 1
    }

    ctx.strokeStyle = ColorMetrics.resourceColor(COLORS.DIVIDER).color
    ctx.lineWidth = 1
    ctx.font = '10px sans-serif'
    for (let i = 0; i <= 4; i++) {
      const y: number = paddingTop + chartH * i / 4
      ctx.beginPath()
      ctx.moveTo(paddingLeft, y)
      ctx.lineTo(width - 10, y)
      ctx.stroke()
      const label: number = Math.round(maxCount * (4 - i) / 4)
      ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_HINT).color
      ctx.fillText(`${label}`, 2, y + 3)
    }

    ctx.strokeStyle = ColorMetrics.resourceColor(MODULE_COLOR.ADMIN).color
    ctx.lineWidth = 2
    ctx.beginPath()
    for (let i = 0; i < this.trend.length; i++) {
      const x: number = paddingLeft + chartW * i / (this.trend.length - 1)
      const y: number = paddingTop + chartH - chartH * this.trend[i].orderCount / maxCount
      if (i === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    }
    ctx.stroke()

    for (let i = 0; i < this.trend.length; i++) {
      const x: number = paddingLeft + chartW * i / (this.trend.length - 1)
      const y: number = paddingTop + chartH - chartH * this.trend[i].orderCount / maxCount
      ctx.fillStyle = ColorMetrics.resourceColor(MODULE_COLOR.ADMIN).color
      ctx.beginPath()
      ctx.arc(x, y, 3, 0, 2 * Math.PI)
      ctx.fill()
      ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_HINT).color
      ctx.font = '9px sans-serif'
      const label: string = this.trend[i].date.length > 10 ? this.trend[i].date.substring(5, 10) : this.trend[i].date
      ctx.fillText(label, x - 12, height - 6)
    }
  }

  @Builder
  TrendRow(point: AdminTrendPoint) {
    Row({ space: SPACING.MD }) {
      Text(point.date).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width(90)
      Text(`订单 ${point.orderCount}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
      Text(`成交 ¥${point.gmv.toFixed(2)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
    }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
  }
}
