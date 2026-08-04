/**
 * 商户收入统计页
 * 展示今日 / 本周 / 累计收入与订单数据，以及账户余额
 */
import router from '@ohos.router'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { MerchantStatsData, User } from '../model/Models'
import { getCurrentUser, getMerchantTodayStats, getMerchantWeekStats, formatPrice } from '../service/AppStorageManager'

@Component
export struct MerchantStatsPage {
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

  aboutToAppear() {
    const user: User | undefined = getCurrentUser()
    if (user !== undefined && user !== null) {
      this.balance = user.balance
      this.todayStats = getMerchantTodayStats(user.id)
      this.weekStats = getMerchantWeekStats(user.id)
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      this.NavBar()

      // 内容区
      Scroll() {
        Column({ space: SPACING.MD }) {
          // 今日数据卡片（主色调背景，大卡片）
          this.TodayCard()

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
      Text('‹')
        .fontSize(FONT_SIZE.BIG_TITLE)
        .fontColor(COLORS.TEXT_PRIMARY)
        .onClick(() => { router.back() })
      Text('收入统计')
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(' ')
        .fontSize(FONT_SIZE.BIG_TITLE)
        .width(28)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.LG, right: SPACING.LG })
    .backgroundColor(COLORS.BG_WHITE)
    .alignItems(VerticalAlign.Center)
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

      Row() {
        Column({ space: SPACING.XS }) {
          Text(`${this.todayStats.todayOrders}`)
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_WHITE)
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
    .backgroundColor(COLORS.PRIMARY)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  WeekCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text('本周数据')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
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
        Text('累计数据')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
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
        Text('账户余额')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(formatPrice(this.balance))
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRIMARY)
      }
      .width('100%')

      Divider()
        .color(COLORS.DIVIDER)
        .margin({ top: SPACING.XS, bottom: SPACING.XS })

      Row() {
        Text('💡 收入统计仅包含已完成订单')
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
