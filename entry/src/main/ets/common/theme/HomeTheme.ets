/** 本轮首页专用的颜色与控件尺寸；不改变其他业务页的全局主题。 */
export class HomeTheme {
  static readonly SURFACE: Resource = $r('app.color.home_surface')
  static readonly CARD: Resource = $r('app.color.home_card')
  static readonly TEXT: Resource = $r('app.color.home_text')
  static readonly MUTED: Resource = $r('app.color.home_muted')
  static readonly ACCENT: Resource = $r('app.color.home_accent')
  static readonly SOFT: Resource = $r('app.color.home_soft')
  static readonly INPUT: Resource = $r('app.color.home_input')
  static readonly ICON: number = 24
  static readonly SMALL_ICON: number = 16
  static readonly SEARCH_ICON: number = 20
  static readonly EMPTY_ICON: number = 40
  static readonly CATEGORY_SIZE: number = 44
  static readonly ENTRY_SIZE: number = 48
  static readonly TOUCH_HEIGHT: number = 44
  static readonly SEARCH_HEIGHT: number = 48
  static readonly TAB_HEIGHT: number = 64
  static readonly CONTROL_RADIUS: number = 16
}
