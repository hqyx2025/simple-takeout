/**
 * 加载中指示组件
 * 原生进度动画；系统减少动态效果时保留静态圆环与加载文案。
 */
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'

@Component
export struct LoadingIndicator {
  text: string = '加载中...'
  @StorageLink('appReduceMotion') reducedMotion: boolean = false

  build() {
    Column({ space: SPACING.MD }) {
      Stack() {
        if (this.reducedMotion) {
          Circle()
            .width(36)
            .height(36)
            .stroke(COLORS.PRIMARY)
            .strokeWidth(3)
            .fillOpacity(0)
            .strokeDashArray([24, 999])
            .accessibilityLevel('no')
        } else {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(COLORS.PRIMARY)
            .accessibilityLevel('no')
        }
      }
      .width(40)
      .height(40)

      if (this.text !== '') {
        Text(this.text)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(this.text === '' ? '加载中' : this.text)
  }
}
