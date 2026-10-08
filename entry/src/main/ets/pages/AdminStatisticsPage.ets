import { AppCardStyle } from '../common/theme/AppTheme'
/** 平台经营统计：订单、GMV、托管资金与热销商品。 */
import { AppMotion } from '../common/theme/AppMotion'
import { ColorMetrics } from '@kit.ArkUI';
import { AdminHotGoods, AdminOrderStatusCount, AdminStatisticsData, AdminTopStore, AdminTrendPoint, User, UserRole } from '../model/Models'
import { fetchAdminDashboardApi, fetchAdminOrderTrendApi, fetchAdminStatisticsApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, getOrderStatusColor, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { PageHeader } from '../components/PageHeader'

@Entry
@Component
export struct AdminStatisticsPage {
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

  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State stats: AdminStatisticsData | null = null
  @State @Watch('redrawCharts') trend: AdminTrendPoint[] = []
  @State orderStatuses: AdminOrderStatusCount[] = []
  @State topStores: AdminTopStore[] = []
  @State maxStatusCount: number = 1
  @State maxStoreGmv: number = 0
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
      let statusMax: number = 1
      for (const item of this.orderStatuses) {
        statusMax = Math.max(statusMax, item.count)
      }
      this.maxStatusCount = statusMax
      let storeMax: number = 0
      for (const store of this.topStores.slice(0, 5)) {
        storeMax = Math.max(storeMax, store.gmv)
      }
      this.maxStoreGmv = storeMax
    }
    this.loading = false
  }

  private valueOrZero(value: number | undefined): string {
    return (value ?? 0).toFixed(2)
  }

  build() {
    Column() {
      PageHeader({
        title: '平台统计',
        backId: 'admin-statistics-back',
        headerBgColor: COLORS.BG_PRIMARY,
        actionColor: MODULE_COLOR.ADMIN,
        actionLabel: this.loading ? '加载中' : '刷新',
        onBack: () => { router.back() },
        onAction: () => { this.refresh() }
      })

      // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一块内容不在顶部
      List({ space: SPACING.MD }) {
        if (this.stats === null) {
          ListItem() {
            Text('暂无统计数据，请稍后刷新').width('100%').padding(SPACING.LG).fontColor(COLORS.TEXT_HINT)
          }
        } else {
          ListItem() {
            Column({ space: SPACING.MD }) {
              Row() {
                Text('平台概览').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
                  .fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
                Text('实时汇总').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
              }.width('100%')
              Row({ space: SPACING.SM }) {
                this.Metric('用户', this.stats.totalUsers.toString(), false)
                this.Metric('商户', this.stats.totalMerchants.toString(), false)
                this.Metric('店铺', this.stats.totalStores.toString(), false)
                this.Metric('商品', this.stats.totalGoods.toString(), false)
              }.width('100%')
              Divider().color(COLORS.DIVIDER)
              Row({ space: SPACING.SM }) {
                this.Metric('订单', this.stats.totalOrders.toString(), false)
                this.Metric('累计成交', `¥${this.valueOrZero(this.stats.totalGmv)}`, true)
                this.Metric('已结算', `¥${this.valueOrZero(this.stats.settledAmount)}`, false)
                this.Metric('待结算', `¥${this.valueOrZero(this.stats.pendingEscrowAmount)}`, false)
              }.width('100%')
            }
            .attributeModifier(new AppCardStyle())
            .width('100%').padding(SPACING.MD)
          }
          ListItem() {
            Column({ space: SPACING.SM }) {
              Text('今日表现').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY).width('100%')
              Row({ space: SPACING.MD }) {
                Column({ space: SPACING.XS }) {
                  Text(`${this.stats.todayOrders}`).fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
                    .fontColor(accentFg(0))
                  Text('今日订单').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Column({ space: SPACING.XS }) {
                  Text(`¥${this.valueOrZero(this.stats.todayGmv)}`).fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
                    .fontColor(MODULE_COLOR.ADMIN)
                  Text('今日成交').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%')
            }
            .attributeModifier(new AppCardStyle())
            .width('100%').padding(SPACING.MD)
          }
          ListItem() {
            this.SectionTitle('近7日订单趋势', 0)
          }
          ListItem() {
            Column() {
              if (this.trend.length === 0) {
                this.ChartEmpty('近 7 日暂无订单数据', 190)
              } else {
                Canvas(this.trendChartContext)
                  .width('100%')
                  .height(190)
                  .onReady(() => { this.drawTrendChart() })
              }
            }
            .attributeModifier(new AppCardStyle())
            .width('100%').padding(SPACING.MD)
          }
          ListItem() {
            this.SectionTitle('订单状态分布', 1)
          }
          ListItem() {
            Column({ space: SPACING.LG }) {
              if (this.orderStatuses.length === 0) {
                this.ChartEmpty('暂无订单状态数据', 190)
              } else {
                ForEach(this.orderStatuses, (item: AdminOrderStatusCount) => {
                  this.StatusBar(item)
                }, (item: AdminOrderStatusCount) => item.status.toString())
              }
            }
            .attributeModifier(new AppCardStyle())
            .width('100%').padding(SPACING.MD)
          }
          ListItem() {
            this.SectionTitle('店铺成交额排行', 2)
          }
          ListItem() {
            Column({ space: SPACING.LG }) {
              if (this.topStores.length === 0) {
                this.ChartEmpty('暂无店铺成交数据', 230)
              } else if (this.maxStoreGmv <= 0) {
                this.ChartEmpty('暂无成交额数据', 230)
              } else {
                ForEach(this.topStores.slice(0, 5), (store: AdminTopStore, index: number) => {
                  this.StoreBar(store, index + 1)
                }, (store: AdminTopStore) => store.storeId.toString())
              }
            }
            .attributeModifier(new AppCardStyle())
            .width('100%').padding(SPACING.MD)
          }
          ListItem() {
            this.SectionTitle('热销商品排行', 3)
          }
          ForEach(this.stats.hotGoods, (item: AdminHotGoods) => {
            ListItem() {
              this.HotGoodsRow(item.goodsName, item.storeName, item.sales, item.price, item.status)
            }
          }, (item: AdminHotGoods) => item.goodsId.toString())
          ListItem() {
            this.SectionTitle('订单状态明细', 4)
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
            this.SectionTitle('店铺成交额明细', 5)
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

  @Builder
  ChartEmpty(message: string, height: number) {
    Text(message).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_SECONDARY)
      .textAlign(TextAlign.Center).width('100%').height(height)
      .padding(SPACING.LG)
  }

  @Builder
  StatusBar(item: AdminOrderStatusCount) {
    Column({ space: SPACING.SM }) {
      Row({ space: SPACING.SM }) {
        Text(this.statusLabel(item.status)).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        Text(`${item.count} 单`).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_PRIMARY)
      }.width('100%')
      Progress({ value: item.count, total: this.maxStatusCount, type: ProgressType.Linear })
        .width('100%').color(getOrderStatusColor(item.status))
        .backgroundColor(COLORS.INPUT).style({ strokeWidth: SPACING.SM })
    }.width('100%')
  }

  @Builder
  StoreBar(store: AdminTopStore, rank: number) {
    Column({ space: SPACING.SM }) {
      Row({ space: SPACING.SM }) {
        Text(`${rank}`).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
          .fontColor(MODULE_COLOR.ADMIN).width(SPACING.XL)
        Text(store.storeName).fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`¥${store.gmv.toFixed(2)}`).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium)
          .fontColor(MODULE_COLOR.ADMIN)
      }.width('100%')
      Progress({ value: store.gmv, total: this.maxStoreGmv, type: ProgressType.Linear })
        .width('100%').color(MODULE_COLOR.ADMIN).backgroundColor(COLORS.INPUT)
        .style({ strokeWidth: SPACING.SM })
    }.width('100%')
  }

  /** 分区标题：窄色条 + 文字 + 分隔线，减少大面积底色干扰。 */
  @Builder
  SectionTitle(title: string, index: number) {
    Row({ space: SPACING.SM }) {
      Text('').width(4).height(18).backgroundColor(accentFg(index)).borderRadius(2)
      Text(title).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
      Divider().layoutWeight(1).color(COLORS.DIVIDER)
    }
    .width('100%').padding({ left: SPACING.XS, right: SPACING.XS, top: SPACING.SM, bottom: SPACING.XS })
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
      .attributeModifier(new AppCardStyle())
    .width('100%').padding(SPACING.MD)
  }

  @Builder
  Metric(title: string, value: string, highlight: boolean) {
    Column({ space: SPACING.XS }) {
      Text(value).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
        .fontColor(highlight ? COLORS.PRIMARY : accentFg(accentIndexFromText(title)))
      Text(title).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
    }.layoutWeight(1).padding({ top: SPACING.XS, bottom: SPACING.XS })
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
    }
      .attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD)
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
    if (this.trend.length === 0) {
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
    ctx.font = `${FONT_SIZE.SM}vp sans-serif`
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

    const pointDenominator: number = Math.max(this.trend.length - 1, 1)
    ctx.strokeStyle = ColorMetrics.resourceColor(MODULE_COLOR.ADMIN).color
    ctx.lineWidth = 2
    ctx.beginPath()
    for (let i = 0; i < this.trend.length; i++) {
      const x: number = this.trend.length === 1
        ? paddingLeft + chartW / 2
        : paddingLeft + chartW * i / pointDenominator
      const y: number = paddingTop + chartH - chartH * this.trend[i].orderCount / maxCount
      if (i === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    }
    ctx.stroke()

    for (let i = 0; i < this.trend.length; i++) {
      const x: number = this.trend.length === 1
        ? paddingLeft + chartW / 2
        : paddingLeft + chartW * i / pointDenominator
      const y: number = paddingTop + chartH - chartH * this.trend[i].orderCount / maxCount
      ctx.fillStyle = ColorMetrics.resourceColor(MODULE_COLOR.ADMIN).color
      ctx.beginPath()
      ctx.arc(x, y, 3, 0, 2 * Math.PI)
      ctx.fill()
      ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_HINT).color
      ctx.font = `${FONT_SIZE.SM}vp sans-serif`
      const label: string = this.trend[i].date.length >= 10 ? this.trend[i].date.substring(5, 10) : this.trend[i].date
      ctx.fillText(label, x - 12, height - 6)
    }
    if (this.trend.length === 1) {
      ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_SECONDARY).color
      ctx.font = `${FONT_SIZE.SM}vp sans-serif`
      ctx.fillText(`${this.trend[0].orderCount} 单`, paddingLeft + chartW / 2 - 12, paddingTop + 18)
    }
  }

  private redrawCharts(): void {
    this.drawTrendChart()
  }

  @Builder
  TrendRow(point: AdminTrendPoint) {
    Row({ space: SPACING.MD }) {
      Text(point.date).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width(90)
      Text(`订单 ${point.orderCount}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
      Text(`成交 ¥${point.gmv.toFixed(2)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
    }
      .attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD)
  }
}
