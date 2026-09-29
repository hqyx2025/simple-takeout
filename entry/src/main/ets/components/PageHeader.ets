/**
 * 通用页面标题栏（router 模式，替代各页手写 Row/Text header）。
 *
 * 登录页暖白底色、左对齐标题和圆角操作按钮；标题、返回文案与 ID 保留测试锚点。
 * 顶部安全区独立计入高度，保证返回与动作按钮始终拥有 44vp 触控区域。
 *
 * 用法：
 *   PageHeader({ title: '我的订单', backId: 'order-list-back', onBack: () => { router.back() } })
 *   PageHeader({ title: '订单详情', actionLabel: '取消', onAction: () => {...} })
 *   PageHeader({ title: '我的页面', showBack: false })  // Tab 内嵌页无返回键
 */
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppTheme } from '../common/theme/AppTheme'
import { SoftPressModifier } from '../common/theme/SoftPressModifier'
import { AppMotion } from '../common/theme/AppMotion'

@Component
export struct PageHeader {
  /** 标题文字（调用方传入，逐字保留） */
  @Prop title: string = ''
  /** 副标题，为空不显示 */
  @Prop subtitle: string = ''
  /** 右侧动作文案，为空不显示 */
  @Prop actionLabel: string = ''
  /** Tab 与角色中心可隐藏返回键 */
  @Prop showBack: boolean = true
  /** 返回键文本：默认 '‹ 返回'；部分页 UiTest 依赖 '‹' 文本兜底锚点（OrderDetailPage/SearchPage） */
  @Prop backText: string = '‹ 返回'
  /** 返回键 UiTest 锚点 id（透传原页面 .id('xxx-back')，保设备回归） */
  @Prop backId: string = ''
  /** 顶部安全区 padding（默认 30；部分页面原值 40） */
  @Prop topPadding: number = 30
  /** 标题栏背景色（默认 COLORS.BG_WHITE；Admin/Merchant 端用 MODULE_BG.ADMIN/MODULE_BG.MERCHANT 等） */
  @Prop headerBgColor: Resource = AppTheme.PAGE
  /** 右侧动作文字颜色（默认主题橙；Admin/Merchant 端传 MODULE_COLOR.ADMIN/MODULE_COLOR.MERCHANT 保持模块色调） */
  @Prop actionColor: Resource = COLORS.PRIMARY
  /** 返回回调（showBack=true 时生效） */
  onBack: () => void = (): void => {}
  /** 右侧动作回调 */
  onAction: () => void = (): void => {}
  /** 标题文字颜色（默认 COLORS.TEXT_PRIMARY；Rider/Merchant 端可传 MODULE_COLOR.RIDER/MERCHANT 保持模块色调） */
  @Prop titleColor: Resource = COLORS.TEXT_PRIMARY
  private softPress: SoftPressModifier = new SoftPressModifier()

  @Builder
  backButton() {
    // 保留返回文案：UiTest clickByIdOrText 的文本兜底锚点依赖 backText 字符串。
    Button(this.backText, { type: ButtonType.Normal })
      .id(this.backId)
      .fontSize(FONT_SIZE.MD)
      .fontColor(COLORS.TEXT_PRIMARY)
      .height(44)
      .constraintSize({ minWidth: 60 })
      .padding({ left: 10, right: 10 })
      .backgroundColor(AppTheme.INPUT)
      .border({ width: 1, color: AppTheme.BORDER })
      .borderRadius(AppTheme.CONTROL_RADIUS)
      .attributeModifier(this.softPress)
      .animation(AppMotion.pressAnimation())
      .onClick(() => { this.onBack() })
      .accessibilityText('返回')
  }

  build() {
    Row({ space: SPACING.MD }) {
      if (this.showBack) {
        this.backButton()
      }

      Column({ space: 0 }) {
        Text(this.title)
          .fontSize(FONT_SIZE.XXL)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.titleColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.actionLabel !== '') {
        Button(this.actionLabel, { type: ButtonType.Normal })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .attributeModifier(this.softPress)
          .animation(AppMotion.pressAnimation())
          .fontSize(FONT_SIZE.MD)
          .fontColor(this.actionColor)
          .height(44)
          .padding({ left: SPACING.MD, right: SPACING.MD })
          .backgroundColor(AppTheme.ACCENT_SOFT)
          .borderRadius(AppTheme.CONTROL_RADIUS)
          .onClick(() => { this.onAction() })
      }
    }
    .width('100%')
    .height(64 + this.topPadding)
    .padding({ left: SPACING.XL, right: SPACING.XL, top: this.topPadding })
    .backgroundColor(this.headerBgColor)
    .border({ width: { bottom: 1 }, color: AppTheme.BORDER })
  }
}
