/**
 * 空状态组件
 * 用于列表无数据时展示
 */
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppButtonStyle, AppTheme } from '../common/theme/AppTheme'
import { routerCompat as router } from '../common/UiNavigation'

@Component
export struct EmptyState {
  icon: Resource = $r('app.media.ui_inbox')
  title: string = '暂无数据'
  description: string = ''
  actionLabel: string = ''
  actionId: string = 'empty-state-action'
  actionUrl: string = ''
  onAction: () => void = () => {}

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
      if (this.actionLabel !== '') {
        Button(this.actionLabel).attributeModifier(new AppButtonStyle())
          .constraintSize({ minHeight: 44 }).padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .id(this.actionId).margin({ top: 8 })
          .onClick(() => {
            if (this.actionUrl !== '') { router.replaceUrl({ url: this.actionUrl }) }
            else { this.onAction() }
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 24, right: 24, top: 32, bottom: 32 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
