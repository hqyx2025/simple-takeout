/**
 * 确认弹窗组件
 * 用于需要用户确认的操作
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { AppMotion } from '../common/theme/AppMotion'
import { SoftPressModifier } from '../common/theme/SoftPressModifier'

@Component
export struct ConfirmDialog {
  @StorageLink('appReduceMotion') reducedMotion: boolean = false
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
        .transition(AppMotion.scrimTransition(this.reducedMotion))
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
            .backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .attributeModifier(new SoftPressModifier())
            .animation(AppMotion.pressAnimation())
            .onClick(() => { this.onCancel() })

          Button(this.confirmText)
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(Color.White)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .attributeModifier(new SoftPressModifier())
            .animation(AppMotion.pressAnimation())
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
      .transition(AppMotion.dialogTransition(this.reducedMotion))
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
