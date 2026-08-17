/** 平台经营统计：订单、GMV、托管资金与热销商品。 */
import { AdminHotGoods, AdminStatisticsData, AdminTrendPoint, User, UserRole } from '../model/Models'
import { fetchAdminOrderTrendApi, fetchAdminStatisticsApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
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
  @State loading: boolean = false

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
    this.loading = false
  }

  private valueOrZero(value: number | undefined): string {
    return (value ?? 0).toFixed(2)
  }

  build() {
    Column() {
      Row() {
        Text('返回').fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).onClick(() => { router.back() })
        Text('平台统计').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button(this.loading ? '加载中' : '刷新').height(32).fontSize(FONT_SIZE.SM)
          .onClick(() => { this.refresh() })
      }.width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 }).backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          if (this.stats === null) {
            Text('暂无统计数据，请稍后刷新').width('100%').padding(SPACING.LG).fontColor(COLORS.TEXT_HINT)
          } else {
            Row({ space: SPACING.SM }) {
              this.Metric('用户', this.stats.totalUsers.toString())
              this.Metric('商户', this.stats.totalMerchants.toString())
              this.Metric('店铺', this.stats.totalStores.toString())
              this.Metric('商品', this.stats.totalGoods.toString())
            }.width('100%')
            Row({ space: SPACING.SM }) {
              this.Metric('订单', this.stats.totalOrders.toString())
              this.Metric('累计成交', `¥${this.valueOrZero(this.stats.totalGmv)}`)
              this.Metric('已结算', `¥${this.valueOrZero(this.stats.settledAmount)}`)
              this.Metric('待结算', `¥${this.valueOrZero(this.stats.pendingEscrowAmount)}`)
            }.width('100%')
            Row({ space: SPACING.MD }) {
              Text(`今日订单：${this.stats.todayOrders}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
              Text(`今日成交：¥${this.valueOrZero(this.stats.todayGmv)}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
            }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
            Text('近7日订单趋势').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            ForEach(this.trend, (point: AdminTrendPoint) => {
              this.TrendRow(point)
            }, (point: AdminTrendPoint) => point.date)
            Text('热销商品排行').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            ForEach(this.stats.hotGoods, (item: AdminHotGoods) => {
              this.HotGoodsRow(item.goodsName, item.storeName, item.sales, item.price, item.status)
            }, (item: AdminHotGoods) => item.goodsId.toString())
          }
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  Metric(title: string, value: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
      Text(title).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
    }.layoutWeight(1).padding({ top: SPACING.MD, bottom: SPACING.MD }).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
  }

  @Builder
  HotGoodsRow(name: string, storeName: string, sales: number, price: number, status: number) {
    Row({ space: SPACING.MD }) {
      Column({ space: 4 }) {
        Text(name).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
        Text(`${storeName}  ¥${price.toFixed(2)}  销量${sales}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(status === 1 ? '上架' : '下架').fontSize(FONT_SIZE.XS).fontColor(status === 1 ? COLORS.SUCCESS : COLORS.ERROR)
    }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
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
