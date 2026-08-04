/**
 * 确认弹窗组件
 * 用于需要用户确认的操作
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'

@Component
export struct ConfirmDialog {
  title: string = '提示'
  content: string = ''
  confirmText: string = '确定'
  cancelText: string = '取消'
  onConfirm: () => void = () => {}
  onCancel: () => void = () => {}

  build() {
    Stack() {
      // 遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => { this.onCancel() })

      // 弹窗内容
      Column({ space: SPACING.MD }) {
        Text(this.title)
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)

        Text(this.content)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)

        Row({ space: SPACING.MD }) {
          Button(this.cancelText)
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor('#F5F5F5')
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .onClick(() => { this.onCancel() })

          Button(this.confirmText)
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(Color.White)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .onClick(() => { this.onConfirm() })
        }
        .width('100%')
        .margin({ top: SPACING.SM })
      }
      .width('80%')
      .padding(SPACING.XL)
      .backgroundColor(COLORS.BG_WHITE)
      .borderRadius(BORDER_RADIUS.XL)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
