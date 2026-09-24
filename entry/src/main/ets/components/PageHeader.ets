/**
 * 通用页面标题栏（router 模式，替代各页手写 Row/Text header）。
 *
 * 设计对齐项目既有 header 约定：
 *   - 高度 56 + 顶部安全区 padding 30（与各页手写 header 一致）
 *   - 居中大标题（FONT_SIZE.XL + Bold），标题文字由调用方传入，逐字保留
 *   - 左侧返回键保留 Text('‹ 返回') 文本 + 可选 id 透传 —— UiTest 依赖
 *     clickByIdOrText(driver, '<id>', '‹ 返回') 双锚点定位，改图标会破坏设备回归
 *   - 右侧可选 action 按钮（SoftPress 轻按反馈）
 *   - 背景色取 COLORS.BG_WHITE（随深浅色自动切换）
 *
 * 用法：
 *   PageHeader({ title: '我的订单', backId: 'order-list-back', onBack: () => { router.back() } })
 *   PageHeader({ title: '订单详情', actionLabel: '取消', onAction: () => {...} })
 *   PageHeader({ title: '我的页面', showBack: false })  // Tab 内嵌页无返回键
 */
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { SoftPressModifier } from '../common/theme/SoftPressModifier'

@Component
export struct PageHeader {
  /** 标题文字（调用方传入，逐字保留） */
  @Prop title: string = ''
  /** 副标题，为空不显示 */
  @Prop subtitle: string = ''
  /** 右侧动作文案，为空不显示 */
  @Prop actionLabel: string = ''
  /** 是否显示返回键；false 时用同尺寸透明占位保持标题居中（Tab 内嵌页） */
  @Prop showBack: boolean = true
  /** 返回键 UiTest 锚点 id（透传原页面 .id('xxx-back')，保设备回归） */
  @Prop backId: string = ''
  /** 返回回调（showBack=true 时生效） */
  onBack: () => void = (): void => {}
  /** 右侧动作回调 */
  onAction: () => void = (): void => {}
  private softPress: SoftPressModifier = new SoftPressModifier()

  @Builder
  backButton() {
    // 保持 Text('‹ 返回') 而非图标：UiTest clickByIdOrText 的文本兜底锚点依赖 '‹ 返回' 字符串
    Text('‹ 返回')
      .id(this.backId)
      .fontSize(FONT_SIZE.MD)
      .fontColor(COLORS.TEXT_PRIMARY)
      .onClick(() => { this.onBack() })
      .accessibilityText('返回')
  }

  @Builder
  placeholder() {
    // 无返回键时用同尺寸透明占位，保持标题绝对居中
    Text('   ').fontSize(FONT_SIZE.MD).width(60)
  }

  build() {
    Row({ space: SPACING.MD }) {
      if (this.showBack) {
        this.backButton()
      } else {
        this.placeholder()
      }

      Column({ space: 0 }) {
        Text(this.title)
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.actionLabel !== '') {
        Button(this.actionLabel)
          .buttonStyle(ButtonStyleMode.NORMAL)
          .attributeModifier(this.softPress)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .height(40)
          .padding({ left: SPACING.MD, right: SPACING.MD })
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.onAction() })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
    .backgroundColor(COLORS.BG_WHITE)
  }
}