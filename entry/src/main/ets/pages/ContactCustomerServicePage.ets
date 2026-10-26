import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
/**
 * 售后帮助页面：只提供当前真实可用的订单售后入口和规则说明。
 */
import { AppMotion } from '../common/theme/AppMotion'
import { routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { PageHeader } from '../components/PageHeader'

const FAQ_QUESTIONS: string[] = [
  '如何发起售后？',
  '怎样查看处理进度？',
  '餐品漏送、错送或洒漏怎么办？',
  '退款会退到哪里？'
]

const FAQ_ANSWERS: string[] = [
  '进入“我的订单”，打开对应订单。已送达且未确认收货、未评价的订单，可在详情页提交退款申请。',
  '退款申请提交后，订单会显示“退款中”。进入对应订单详情即可查看当前处理状态。',
  '请保留餐品和包装，在对应订单详情选择与问题相符的退款原因，并补充实际情况。',
  '审批同意后，款项按原支付渠道退回。最终结果以订单资金状态和支付渠道到账记录为准。'
]

@Entry
@Component
export struct ContactCustomerServicePage {
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

  @State expandedQuestion: number = -1

  private toggleQuestion(index: number): void {
    this.expandedQuestion = this.expandedQuestion === index ? -1 : index
  }

  private openOrders(status: number): void {
    AppStorage.setOrCreate<number>('orderFilterStatus', status)
    router.pushUrl({ url: 'pages/OrderListPage' })
  }

  build() {
    Column() {
      PageHeader({ title: '售后帮助', onBack: () => { router.back() } })

      Scroll() {
        Column({ space: SPACING.MD }) {
          Column({ space: SPACING.SM }) {
            Text('订单售后')
              .fontSize(FONT_SIZE.XXL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.ON_PRIMARY)
            Text('从对应订单发起申请，可保留完整的商品、配送和处理记录')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.ON_PRIMARY)
          }
          .width('100%')
          .padding(SPACING.XL)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.LG)
          .alignItems(HorizontalAlign.Start)

          Column({ space: SPACING.SM }) {
            Button('从订单发起售后')
              .attributeModifier(new AppButtonStyle())
              .width('100%')
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.ON_PRIMARY)
              .backgroundColor(COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.openOrders(4) })
            Button('查看退款 / 售后进度')
              .attributeModifier(new AppButtonStyle())
              .width('100%')
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.PRIMARY)
              .backgroundColor(COLORS.BG_WHITE)
              .border({ width: 1, color: COLORS.PRIMARY })
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.openOrders(6) })
          }
          .width('100%')

          Column({ space: SPACING.SM }) {
            Text('处理说明')
              .fontSize(FONT_SIZE.LG)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Text('选择对应订单后再提交问题，避免重复填写订单号，也能准确展示退款状态。')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .lineHeight(22)
              .width('100%')
          }
          .attributeModifier(new AppCardStyle())
          .width('100%')
          .padding(SPACING.LG)

          Column({ space: SPACING.SM }) {
            Text('常见问题')
              .fontSize(FONT_SIZE.LG)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            ForEach(FAQ_QUESTIONS, (question: string, index: number) => {
              this.FaqRow(question, FAQ_ANSWERS[index], index)
            }, (question: string, index: number) => index.toString() + '-' + question)
          }
          .attributeModifier(new AppCardStyle())
          .width('100%')
          .padding(SPACING.LG)
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XXL })
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
  FaqRow(question: string, answer: string, index: number) {
    Column({ space: SPACING.SM }) {
      Row() {
        Text(question)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.expandedQuestion === index ? '-' : '+')
          .fontSize(FONT_SIZE.XL)
          .fontColor(COLORS.PRIMARY)
      }
      .width('100%')
      .onClick(() => { this.toggleQuestion(index) })
      if (this.expandedQuestion === index) {
        Text(answer)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
          .padding({ top: SPACING.XS, bottom: SPACING.XS })
      }
    }
    .width('100%')
    .padding({ top: SPACING.SM, bottom: SPACING.SM })
    .border({ width: { bottom: 1 }, color: COLORS.DIVIDER })
  }
}
