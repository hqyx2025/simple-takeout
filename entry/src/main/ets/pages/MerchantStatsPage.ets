/**
 * 商户收入统计页
 * 展示今日 / 本周 / 累计收入与订单数据，以及账户余额
 */
import { AppMotion } from '../common/theme/AppMotion'
import { ColorMetrics } from '@kit.ArkUI';
import { routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusColor, MODULE_COLOR, MODULE_BG, accentBg, accentFg } from '../common/Constants'
import { MerchantStatsData, User, UserRole } from '../model/Models'
import { getCurrentUser, getMerchantTodayStats, getMerchantWeekStats, getMerchantWeekRevenue, getMerchantTodayStatusOrders, formatPrice, syncMerchantOrdersFromServer } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct MerchantStatsPage {
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
  @State todayStats: MerchantStatsData = {
    todayOrders: 0,
    todayRevenue: 0,
    completedOrders: 0,
    totalOrders: 0,
    totalRevenue: 0
  }
  @State weekStats: MerchantStatsData = {
    todayOrders: 0,
    todayRevenue: 0,
    completedOrders: 0,
    totalOrders: 0,
    totalRevenue: 0
  }
  @State balance: number = 0
  @State loadError: boolean = false
  // 近7天每日收入（折线图）
  @State weekRevenue: number[] = [0, 0, 0, 0, 0, 0, 0]
  @State weekLabels: string[] = []
  // 今日订单状态分布（柱状图）：待接单/制作中/配送中/已完成/已取消
  @State todayStatus: number[] = [0, 0, 0, 0, 0]
  private statusLabels: string[] = ['待接单', '制作中', '配送中', '已完成', '已取消']
  private weekChartContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private statusChartContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))

  aboutToAppear() {
    logInfo('Page', '进入商户收入统计页 MerchantStatsPage')
    const user: User | undefined = getCurrentUser()
    if (this.loggedIn && user !== undefined && user !== null && user.role === UserRole.MERCHANT) {
      this.balance = user.balance
      this.todayStats = getMerchantTodayStats(user.id)
      this.weekStats = getMerchantWeekStats(user.id)
      this.weekRevenue = getMerchantWeekRevenue(user.id)
      this.todayStatus = getMerchantTodayStatusOrders(user.id)
      // 生成近7天日期标签
      const now: Date = new Date()
      const labels: string[] = []
      const dayMillis: number = 24 * 60 * 60 * 1000
      const cursor: Date = new Date(now.getTime() - 6 * dayMillis)
      for (let i = 6; i >= 0; i--) {
        labels.push(`${cursor.getMonth() + 1}/${cursor.getDate()}`)
        cursor.setTime(cursor.getTime() + dayMillis)
      }
      this.weekLabels = labels
      // 从后端拉取最新统计（真实后端模式）
      this.refreshRemoteStats()
    } else {
      logInfo('Page', '商户统计页跳过加载：未登录或角色不匹配')
      router.back()
    }
  }

  // 从后端同步订单后按统一口径重算统计（status=4 且 escrow=1，与大纲 21.4/后端接口一致）
  private async refreshRemoteStats(): Promise<void> {
    this.loadError = false
    try {
      await syncMerchantOrdersFromServer()
      const user: User | undefined = getCurrentUser()
      if (user !== undefined && user !== null) {
        this.todayStats = getMerchantTodayStats(user.id)
        this.weekStats = getMerchantWeekStats(user.id)
        this.weekRevenue = getMerchantWeekRevenue(user.id)
        this.todayStatus = getMerchantTodayStatusOrders(user.id)
      }
    } catch (_e) {
      this.loadError = true
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      this.NavBar()

      // 内容区
      Scroll() {
        Column({ space: SPACING.MD }) {
          // 网络错误时显示重试横幅——否则全零数据与"真的没订单"无法区分
          if (this.loadError) {
            this.ErrorBanner()
          }

          // 今日数据卡片（主色调背景，大卡片）
          this.TodayCard()

          // 近7天收入趋势折线图
          this.WeekChartCard()

          // 今日订单状态分布柱状图
          this.StatusChartCard()

          // 本周数据卡片
          this.WeekCard()

          // 累计数据卡片
          this.CumulativeCard()

          // 数据说明 + 账户余额
          this.InfoCard()
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(COLORS.BG_PRIMARY)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  NavBar() {
    Row() {
      Text('‹ 返回')
        .fontSize(FONT_SIZE.MD)
        .fontColor(MODULE_COLOR.MERCHANT)
        .onClick(() => { router.back() })
      Text('收入统计')
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(MODULE_COLOR.MERCHANT)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(' ')
        .fontSize(FONT_SIZE.BIG_TITLE)
        .width(28)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.LG, right: SPACING.LG, top: 26 })
    .backgroundColor(MODULE_BG.MERCHANT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ErrorBanner() {
    Row() {
      Text('数据加载失败，以下数据可能不准确')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.ERROR)
        .layoutWeight(1)
      Text('重试')
        .fontSize(FONT_SIZE.SM)
        .fontColor(MODULE_COLOR.MERCHANT)
        .fontWeight(FontWeight.Bold)
        .onClick(() => { this.refreshRemoteStats() })
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
    .backgroundColor(COLORS.ERROR_LIGHT)
    .borderRadius(BORDER_RADIUS.MD)
  }

  @Builder
  TodayCard() {
    Column({ space: SPACING.MD }) {
      Text('今日收入')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_WHITE)
        .width('100%')

      Text(formatPrice(this.todayStats.todayRevenue))
        .fontSize(FONT_SIZE.BIG_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_WHITE)
        .width('100%')
        .id('stats-today-revenue')

      Row() {
        Column({ space: SPACING.XS }) {
          Text(`${this.todayStats.todayOrders}`)
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_WHITE)
            .id('stats-today-orders')
          Text('今日订单')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_WHITE)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: SPACING.XS }) {
          Text(`${this.todayStats.completedOrders}`)
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_WHITE)
            .id('stats-completed-orders')
          Text('已完成订单')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_WHITE)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .margin({ top: SPACING.SM })
    }
    .width('100%')
    .padding(SPACING.XL)
    .backgroundColor(MODULE_COLOR.MERCHANT)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  WeekChartCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text('📈')
          .fontSize(FONT_SIZE.MD)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .backgroundColor(accentBg(0))
          .borderRadius(BORDER_RADIUS.SM)
        Text('近7天收入趋势')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(accentFg(0))
          .margin({ left: SPACING.SM })
        Text('单位：元')
          .fontSize(FONT_SIZE.XS)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ left: SPACING.SM })
      }
      .width('100%')

      Canvas(this.weekChartContext)
        .width('100%')
        .height(190)
        .onReady(() => { this.drawWeekRevenueChart() })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  StatusChartCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(FONT_SIZE.MD)
          .width(28)
          .height(28)
          .backgroundColor(accentBg(1))
          .borderRadius(BORDER_RADIUS.SM)
        Text('今日订单状态分布')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(accentFg(1))
          .margin({ left: SPACING.SM })
      }
      .width('100%')

      Canvas(this.statusChartContext)
        .width('100%')
        .height(180)
        .onReady(() => { this.drawStatusChart() })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  // 绘制近7天收入趋势折线图
  private drawWeekRevenueChart(): void {
    const ctx: CanvasRenderingContext2D = this.weekChartContext
    const width: number = ctx.width
    const height: number = ctx.height
    const paddingLeft: number = 36
    const paddingBottom: number = 22
    const paddingTop: number = 10
    const chartW: number = width - paddingLeft - 10
    const chartH: number = height - paddingTop - paddingBottom

    ctx.clearRect(0, 0, width, height)

    // 计算最大值（至少为1，避免除零）
    let maxRevenue: number = 0
    for (let i = 0; i < this.weekRevenue.length; i++) {
      if (this.weekRevenue[i] > maxRevenue) {
        maxRevenue = this.weekRevenue[i]
      }
    }
    if (maxRevenue <= 0) {
      maxRevenue = 1
    }

    // 绘制横向网格线与Y轴刻度
    ctx.strokeStyle = ColorMetrics.resourceColor(COLORS.DIVIDER).color
    ctx.lineWidth = 1
    ctx.font = '10px sans-serif'
    for (let i = 0; i <= 4; i++) {
      const y: number = paddingTop + chartH * i / 4
      ctx.beginPath()
      ctx.moveTo(paddingLeft, y)
      ctx.lineTo(width - 10, y)
      ctx.stroke()
      const label: number = Math.round(maxRevenue * (4 - i) / 4)
      ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_HINT).color
      ctx.fillText(`${label}`, 2, y + 3)
    }

    // 绘制折线
    ctx.strokeStyle = ColorMetrics.resourceColor(MODULE_COLOR.MERCHANT).color
    ctx.lineWidth = 2
    ctx.beginPath()
    for (let i = 0; i < this.weekRevenue.length; i++) {
      const x: number = paddingLeft + chartW * i / (this.weekRevenue.length - 1)
      const y: number = paddingTop + chartH - chartH * this.weekRevenue[i] / maxRevenue
      if (i === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    }
    ctx.stroke()

    // 绘制数据点与日期标签
    for (let i = 0; i < this.weekRevenue.length; i++) {
      const x: number = paddingLeft + chartW * i / (this.weekRevenue.length - 1)
      const y: number = paddingTop + chartH - chartH * this.weekRevenue[i] / maxRevenue
      ctx.fillStyle = ColorMetrics.resourceColor(MODULE_COLOR.MERCHANT).color
      ctx.beginPath()
      ctx.arc(x, y, 3, 0, 2 * Math.PI)
      ctx.fill()

      ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_HINT).color
      ctx.font = '9px sans-serif'
      let label: string = ''
      if (i < this.weekLabels.length) {
        label = this.weekLabels[i]
      }
      ctx.fillText(label, x - 12, height - 6)
    }
  }

  // 绘制今日订单状态分布柱状图
  private drawStatusChart(): void {
    const ctx: CanvasRenderingContext2D = this.statusChartContext
    const width: number = ctx.width
    const height: number = ctx.height
    const paddingBottom: number = 22
    const paddingTop: number = 18
    const chartH: number = height - paddingTop - paddingBottom

    ctx.clearRect(0, 0, width, height)

    // 计算最大值（至少为1，避免除零）
    let maxCount: number = 0
    for (let i = 0; i < this.todayStatus.length; i++) {
      if (this.todayStatus[i] > maxCount) {
        maxCount = this.todayStatus[i]
      }
    }
    if (maxCount <= 0) {
      maxCount = 1
    }

    const barCount: number = this.todayStatus.length
    const barW: number = (width - 24 - 12 * (barCount - 1)) / barCount
    const colors: ResourceColor[] = [
      getOrderStatusColor(1),
      getOrderStatusColor(2),
      getOrderStatusColor(3),
      getOrderStatusColor(4),
      getOrderStatusColor(5)
    ]

    ctx.font = '10px sans-serif'
    for (let i = 0; i < barCount; i++) {
      const x: number = 12 + i * (barW + 12)
      const barH: number = chartH * this.todayStatus[i] / maxCount
      const y: number = paddingTop + chartH - barH

      // 柱子
      ctx.fillStyle = ColorMetrics.resourceColor(colors[i]).color
      ctx.fillRect(x, y, barW, barH)

      // 数值
      if (this.todayStatus[i] > 0) {
        ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_PRIMARY).color
        ctx.fillText(`${this.todayStatus[i]}`, x + barW / 2 - 4, y - 4)
      }

      // 底部标签
      ctx.fillStyle = ColorMetrics.resourceColor(COLORS.TEXT_HINT).color
      const label: string = this.statusLabels[i]
      ctx.fillText(label, x + barW / 2 - label.length * 5, height - 6)
    }
  }

  @Builder
  WeekCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text('🗓️')
          .fontSize(FONT_SIZE.MD)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .backgroundColor(accentBg(2))
          .borderRadius(BORDER_RADIUS.SM)
        Text('本周数据')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(accentFg(2))
          .margin({ left: SPACING.SM })
      }
      .width('100%')

      Row() {
        Column({ space: SPACING.XS }) {
          Text(formatPrice(this.weekStats.todayRevenue))
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.PRICE_RED)
          Text('本周收入')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column({ space: SPACING.XS }) {
          Text(`${this.weekStats.todayOrders}`)
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('本周订单')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column({ space: SPACING.XS }) {
          Text(`${this.weekStats.completedOrders}`)
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('已完成')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  CumulativeCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        SymbolGlyph($r('sys.symbol.star_trophy'))
          .fontSize(FONT_SIZE.MD)
          .width(28)
          .height(28)
          .backgroundColor(accentBg(3))
          .borderRadius(BORDER_RADIUS.SM)
        Text('累计数据')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(accentFg(3))
          .margin({ left: SPACING.SM })
      }
      .width('100%')

      Row() {
        Column({ space: SPACING.XS }) {
          Text(formatPrice(this.todayStats.totalRevenue))
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.PRICE_RED)
          Text('累计收入')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column({ space: SPACING.XS }) {
          Text(`${this.todayStats.totalOrders}`)
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('累计订单')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  InfoCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        SymbolGlyph($r('sys.symbol.wallet'))
          .fontSize(FONT_SIZE.MD)
          .width(28)
          .height(28)
          .backgroundColor(accentBg(4))
          .borderRadius(BORDER_RADIUS.SM)
        Text('账户余额')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
        Text(formatPrice(this.balance))
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(accentFg(4))
      }
      .width('100%')

      Divider()
        .color(COLORS.DIVIDER)
        .margin({ top: SPACING.XS, bottom: SPACING.XS })

      Row() {
        SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(FONT_SIZE.SM)
        Text(' 收入统计仅包含已结算订单（用户确认收货后到账）')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }
}
