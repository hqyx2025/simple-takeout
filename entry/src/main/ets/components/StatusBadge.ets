/**
 * 通用状态徽章（药丸标签）
 * mode: primary | success | warning | error | gray
 * 统一状态文本的浅底 + 同色字，替代各处散落的纯色文字标签。
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'

@Component
export struct StatusBadge {
  @Prop text: string = ''
  @Prop mode: string = 'primary'
  @Prop small: boolean = false

  private bg(): ResourceColor {
    switch (this.mode) {
      case 'success': return COLORS.SUCCESS_LIGHT
      case 'warning': return COLORS.WARNING_LIGHT
      case 'error': return COLORS.ERROR_LIGHT
      case 'gray': return COLORS.STATUS_GRAY_BG
      default: return COLORS.TAG_BG
    }
  }

  private fg(): ResourceColor {
    switch (this.mode) {
      case 'success': return COLORS.SUCCESS
      case 'warning': return COLORS.WARNING
      case 'error': return COLORS.ERROR
      case 'gray': return COLORS.TEXT_HINT
      default: return COLORS.PRIMARY
    }
  }

  build() {
    Text(this.text)
      .fontSize(this.small ? FONT_SIZE.XS : FONT_SIZE.SM)
      .fontColor(this.fg())
      .backgroundColor(this.bg())
      .padding({ left: SPACING.SM, right: SPACING.SM, top: SPACING.XS, bottom: SPACING.XS })
      .borderRadius(BORDER_RADIUS.ROUND)
      .textAlign(TextAlign.Center)
  }
}
