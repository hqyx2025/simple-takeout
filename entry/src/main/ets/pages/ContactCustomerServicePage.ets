/**
 * 客服中心页面：提供客服说明、联系方式和常见问题。
 * 即时通讯等第三方能力暂未接入，页面先提供可用的本地客服指引。
 */
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'

const FAQ_QUESTIONS: string[] = [
  '\u5982\u4f55\u4fee\u6539\u6536\u8d27\u5730\u5740\uff1f',
  '\u8ba2\u5355\u63d0\u4ea4\u5931\u8d25\u600e\u4e48\u529e\uff1f',
  '\u5982\u4f55\u7533\u8bf7\u9000\u6b3e\uff1f',
  '\u4f18\u60e0\u5238\u4e3a\u4ec0\u4e48\u4e0d\u80fd\u4f7f\u7528\uff1f'
]

const FAQ_ANSWERS: string[] = [
  '\u8fdb\u5165\u201c\u6211\u7684\u201d\u9875\u9762\uff0c\u6253\u5f00\u6536\u8d27\u5730\u5740\u5373\u53ef\u65b0\u589e\u3001\u7f16\u8f91\u6216\u9009\u62e9\u5df2\u4fdd\u5b58\u5730\u5740\u3002',
  '\u8bf7\u5148\u68c0\u67e5\u8d26\u6237\u4f59\u989d\u3001\u6536\u8d27\u5730\u5740\u548c\u5e97\u94fa\u8d77\u9001\u4ef7\u3002\u5982\u4ecd\u65e0\u6cd5\u63d0\u4ea4\uff0c\u8bf7\u8054\u7cfb\u5ba2\u670d\u5e76\u63d0\u4f9b\u8ba2\u5355\u53f7\u3002',
  '\u5df2\u9001\u8fbe\u7684\u8ba2\u5355\u53ef\u5728\u8ba2\u5355\u8be6\u60c5\u9875\u63d0\u4ea4\u9000\u6b3e\u7533\u8bf7\uff0c\u5e73\u53f0\u5ba1\u6838\u540e\u4f1a\u66f4\u65b0\u8ba2\u5355\u72b6\u6001\u3002',
  '\u4f18\u60e0\u5238\u9700\u6ee1\u8db3\u4f7f\u7528\u95e8\u69db\u3001\u6709\u6548\u671f\u548c\u9002\u7528\u5e97\u94fa\u6761\u4ef6\uff0c\u4e14\u6bcf\u5f20\u4f18\u60e0\u5238\u53ea\u80fd\u4f7f\u7528\u4e00\u6b21\u3002'
]

@Entry
@Component
export struct ContactCustomerServicePage {
  @State expandedQuestion: number = -1

  private toggleQuestion(index: number): void {
    this.expandedQuestion = this.expandedQuestion === index ? -1 : index
  }

  private showHotline(): void {
    promptAction.showToast({ message: '\u5ba2\u670d\u70ed\u7ebf\uff1a400-123-4567\uff0c\u670d\u52a1\u65f6\u95f4\uff1a09:00-22:00', duration: 3000 })
  }

  private showOnlineService(): void {
    promptAction.showToast({ message: '\u5728\u7ebf\u5ba2\u670d\u901a\u9053\u5f85\u63a5\u5165\uff0c\u8bf7\u5148\u62e8\u6253\u5ba2\u670d\u70ed\u7ebf', duration: 2400 })
  }

  build() {
    Column() {
      Row() {
        Text('\u2039')
          .fontSize(FONT_SIZE.BIG_TITLE)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('\u8054\u7cfb\u5ba2\u670d')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
          .fontSize(FONT_SIZE.BIG_TITLE)
          .width(FONT_SIZE.BIG_TITLE)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: SPACING.MD }) {
          Column({ space: SPACING.SM }) {
            Text('\u5ba2\u670d\u4e2d\u5fc3')
              .fontSize(FONT_SIZE.XXL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_WHITE)
            Text('\u9047\u5230\u95ee\u9898\u8bf7\u5148\u67e5\u770b\u5e38\u89c1\u95ee\u9898\uff0c\u4e5f\u53ef\u76f4\u63a5\u8054\u7cfb\u5ba2\u670d')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_WHITE)
          }
          .width('100%')
          .padding(SPACING.XL)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.LG)
          .alignItems(HorizontalAlign.Start)

          Row({ space: SPACING.SM }) {
            Button('\u62e8\u6253\u5ba2\u670d\u70ed\u7ebf')
              .layoutWeight(1)
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.PRIMARY)
              .backgroundColor(COLORS.BG_WHITE)
              .borderRadius(BORDER_RADIUS.ROUND)
              .type(ButtonType.Capsule)
              .onClick(() => { this.showHotline() })
            Button('\u5728\u7ebf\u5ba2\u670d')
              .layoutWeight(1)
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_WHITE)
              .backgroundColor(COLORS.PRIMARY_DARK)
              .borderRadius(BORDER_RADIUS.ROUND)
              .type(ButtonType.Capsule)
              .onClick(() => { this.showOnlineService() })
          }
          .width('100%')

          Column({ space: SPACING.SM }) {
            Text('\u8054\u7cfb\u65b9\u5f0f')
              .fontSize(FONT_SIZE.LG)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Row() {
              Text('\u5ba2\u670d\u70ed\u7ebf')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .layoutWeight(1)
              Text('400-123-4567')
                .fontSize(FONT_SIZE.LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.PRIMARY)
            }
            .width('100%')
            Row() {
              Text('\u670d\u52a1\u65f6\u95f4')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .layoutWeight(1)
              Text('09:00-22:00')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_PRIMARY)
            }
            .width('100%')
          }
          .width('100%')
          .padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)

          Column({ space: SPACING.SM }) {
            Text('\u5e38\u89c1\u95ee\u9898')
              .fontSize(FONT_SIZE.LG)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            ForEach(FAQ_QUESTIONS, (question: string, index: number) => {
              this.FaqRow(question, FAQ_ANSWERS[index], index)
            }, (question: string, index: number) => `${index}-${question}`)
          }
          .width('100%')
          .padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
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
