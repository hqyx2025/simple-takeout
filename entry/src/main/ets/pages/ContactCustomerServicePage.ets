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
  '退款会退到哪里？',
  '取消后的库存和优惠券如何处理？'
]

const FAQ_ANSWERS: string[] = [
  '进入“我的订单”，打开对应订单。送达48小时内可申请剩余金额内的全部或部分退款；已确认、已评价仍可售后，具体可用入口以订单详情为准。',
  '进入对应订单详情的退款进度，可查看申请、商家举证、驳回原因与退款结果。部分退款后仍可在可退余额内继续申请。',
  '请保留餐品和包装，在订单详情选择原因、填写退款金额并上传图片证据；驳回后48小时内可申诉一次，由平台裁决。',
  '审批同意后，款项按原支付渠道退回。最终结果以退款记录和支付渠道到账记录为准。',
  '制作前取消释放库存，进入制作后取消不恢复库存。未付款取消释放优惠券；已付款后用户主动取消不返券，平台或商家取消退回仍在有效期内的券。'
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
