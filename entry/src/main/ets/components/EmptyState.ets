/**
 * 空状态组件
 * 用于列表无数据时展示
 */
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppTheme } from '../common/theme/AppTheme'

@Component
export struct EmptyState {
  icon: Resource = $r('app.media.ui_inbox')
  title: string = '暂无数据'
  description: string = ''

  build() {
    Column({ space: SPACING.MD }) {
      Image(this.icon)
        .width(80).height(80).padding(20)
        .objectFit(ImageFit.Contain)
        .backgroundColor(AppTheme.INPUT).borderRadius(24)
        .accessibilityLevel('no')
      Text(this.title)
        .fontSize(FONT_SIZE.LG)
        .fontColor(AppTheme.TEXT)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
      if (this.description !== '') {
        Text(this.description)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 280 })
          .margin({ top: SPACING.XS })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 24, right: 24, top: 32, bottom: 32 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
