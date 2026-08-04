/**
 * 空状态组件
 * 用于列表无数据时展示
 */
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'

@Component
export struct EmptyState {
  icon: string = '📭'
  title: string = '暂无数据'
  description: string = ''

  build() {
    Column({ space: SPACING.SM }) {
      Text(this.icon)
        .fontSize(60)
        .margin({ top: 80 })
      Text(this.title)
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ top: SPACING.MD })
      if (this.description !== '') {
        Text(this.description)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ top: SPACING.XS })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
