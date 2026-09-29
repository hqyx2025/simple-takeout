import { SoftPressModifier } from './SoftPressModifier'

/** 登录页与四端页面共用的视觉基准，颜色由深浅色资源提供。 */
export class AppTheme {
  static readonly PAGE: Resource = $r('app.color.bg_primary')
  static readonly CARD: Resource = $r('app.color.bg_card')
  static readonly TEXT: Resource = $r('app.color.text_primary')
  static readonly MUTED: Resource = $r('app.color.text_secondary')
  static readonly BORDER: Resource = $r('app.color.divider')
  static readonly INPUT: Resource = $r('app.color.input')
  static readonly ACCENT: Resource = $r('app.color.tag_text')
  static readonly ACCENT_SOFT: Resource = $r('app.color.tag_bg')
  static readonly PRIMARY: Resource = $r('app.color.primary')
  static readonly PRIMARY_TEXT: Resource = $r('app.color.on_primary')
  static readonly ERROR: Resource = $r('app.color.error')
  static readonly ERROR_BG: Resource = $r('app.color.error_light')
  static readonly SUCCESS: Resource = $r('app.color.success')
  static readonly SUCCESS_BG: Resource = $r('app.color.success_light')
  static readonly FORM_MAX_WIDTH: number = 460
  static readonly CONTROL_HEIGHT: number = 52
  static readonly CONTROL_RADIUS: number = 14
  static readonly CARD_RADIUS: number = 18
  static readonly FILTER_HEIGHT: number = 44
  static readonly REFRESH_OFFSET: number = 64
  static readonly SHEET_RADIUS: number = 24
}

/** Search 自带清除、键盘搜索与焦点处理，颜色跟随应用深浅色资源。 */
export class AppSearchStyle implements AttributeModifier<SearchAttribute> {
  applyNormalAttribute(search: SearchAttribute): void {
    search.height(AppTheme.CONTROL_HEIGHT).fontColor(AppTheme.TEXT)
      .textFont({ size: 16 }).placeholderFont({ size: 16 })
      .placeholderColor(AppTheme.MUTED).backgroundColor(AppTheme.INPUT)
      .caretStyle({ color: AppTheme.ACCENT })
      .searchIcon({ src: $r('app.media.home_search'), size: 20 })
      .cancelButton({ style: CancelButtonStyle.INPUT,
        icon: { src: $r('app.media.ui_close'), size: 18 } })
      .border({ width: 1, color: AppTheme.BORDER }).borderRadius(AppTheme.CONTROL_RADIUS)
  }
  applyFocusedAttribute(search: SearchAttribute): void {
    search.border({ width: 1.5, color: AppTheme.ACCENT })
  }
}

/** 滚动筛选项保留各页 ID 和回调，使用原生 Button 的焦点与按压反馈。 */
export class AppFilterStyle extends SoftPressModifier {
  private selected: boolean

  constructor(selected: boolean) {
    super(false)
    this.selected = selected
  }

  applyNormalAttribute(button: ButtonAttribute): void {
    super.applyNormalAttribute(button)
    button.type(ButtonType.Capsule).height(AppTheme.FILTER_HEIGHT).fontSize(14)
      .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selected ? AppTheme.PRIMARY_TEXT : AppTheme.MUTED)
      .backgroundColor(this.selected ? AppTheme.PRIMARY : AppTheme.INPUT)
      .padding({ left: 16, right: 16 })
      .border({ width: 1, color: this.selected ? AppTheme.PRIMARY : AppTheme.BORDER })
  }
}

export class AppRefreshStyle implements AttributeModifier<RefreshAttribute> {
  applyNormalAttribute(refresh: RefreshAttribute): void {
    refresh.refreshOffset(AppTheme.REFRESH_OFFSET).pullToRefresh(true)
      .pullDownRatio(0.6)
  }
}

/** 输入框默认外观；页面仍负责内容、校验与焦点行为。 */
export class AppInputStyle implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(input: TextInputAttribute): void {
    input.height(AppTheme.CONTROL_HEIGHT).fontSize(16)
      .fontColor(AppTheme.TEXT).placeholderColor(AppTheme.MUTED)
      .caretColor(AppTheme.ACCENT).backgroundColor(AppTheme.INPUT)
      .border({ width: 1, color: AppTheme.BORDER }).borderRadius(AppTheme.CONTROL_RADIUS)
      .padding({ left: 14, right: 14 })
  }
  applyFocusedAttribute(input: TextInputAttribute): void {
    input.border({ width: 1.5, color: AppTheme.ACCENT })
  }
}

export class AppTextAreaStyle implements AttributeModifier<TextAreaAttribute> {
  applyNormalAttribute(input: TextAreaAttribute): void {
    input.fontSize(16).fontColor(AppTheme.TEXT).placeholderColor(AppTheme.MUTED)
      .caretColor(AppTheme.ACCENT).backgroundColor(AppTheme.INPUT)
      .border({ width: 1, color: AppTheme.BORDER }).borderRadius(AppTheme.CONTROL_RADIUS)
      .padding(14)
  }
  applyFocusedAttribute(input: TextAreaAttribute): void {
    input.border({ width: 1.5, color: AppTheme.ACCENT })
  }
}

/** 原生按钮保留按压反馈，页面显式声明的语义色覆盖默认主按钮色。 */
export class AppButtonStyle extends SoftPressModifier {
  applyNormalAttribute(button: ButtonAttribute): void {
    super.applyNormalAttribute(button)
    button.type(ButtonType.Normal).fontSize(14).fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.PRIMARY_TEXT).backgroundColor(AppTheme.PRIMARY)
      .borderRadius(AppTheme.CONTROL_RADIUS)
  }
}

export class AppCardStyle implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(card: CommonAttribute): void {
    card.backgroundColor(AppTheme.CARD).borderRadius(AppTheme.CARD_RADIUS)
      .border({ width: 1, color: AppTheme.BORDER })
  }
}
