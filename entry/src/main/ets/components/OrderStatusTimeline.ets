/**
 * 订单状态时间轴组件
 * 展示订单状态流转（已下单→制作中→配送中→已送达）
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { DeliveryStep } from '../model/Models'

@Component
export struct OrderStatusTimeline {
  steps: DeliveryStep[] = []

  build() {
    Column({ space: 0 }) {
      ForEach(this.steps, (step: DeliveryStep, index: number) => {
        Row({ space: SPACING.MD }) {
          // 左侧时间轴圆点与连线
          Column() {
            // 圆点
            Stack() {
              if (step.completed) {
                Text('✓')
                  .fontSize(14)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Bold)
              }
            }
            .width(24)
            .height(24)
            .borderRadius(BORDER_RADIUS.CIRCLE)
            .backgroundColor(step.completed ? COLORS.PRIMARY : COLORS.DIVIDER)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            // 连线（最后一个不显示）
            if (index < this.steps.length - 1) {
              Column()
                .width(2)
                .layoutWeight(1)
                .backgroundColor(step.completed ? COLORS.PRIMARY : COLORS.DIVIDER)
                .margin({ top: 4, bottom: 4 })
            }
          }
          .width(24)
          .height(index < this.steps.length - 1 ? 60 : 24)

          // 右侧状态信息
          Column({ space: 4 }) {
            Text(step.title)
              .fontSize(FONT_SIZE.MD)
              .fontColor(step.completed ? COLORS.TEXT_PRIMARY : COLORS.TEXT_HINT)
              .fontWeight(step.completed ? FontWeight.Bold : FontWeight.Normal)
            if (step.time !== '') {
              Text(step.time)
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.TEXT_HINT)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .padding({ bottom: index < this.steps.length - 1 ? SPACING.MD : 0 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Top)
      }, (step: DeliveryStep) => step.status.toString())
    }
    .width('100%')
    .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD })
  }
}
