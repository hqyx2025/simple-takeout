import { AppTheme } from './AppTheme'

/** 首页控件尺寸；颜色继承全站登录页基准。 */
export class HomeTheme {
  static readonly SURFACE: Resource = AppTheme.PAGE
  static readonly CARD: Resource = AppTheme.CARD
  static readonly TEXT: Resource = AppTheme.TEXT
  static readonly MUTED: Resource = AppTheme.MUTED
  static readonly ACCENT: Resource = AppTheme.ACCENT
  static readonly SOFT: Resource = AppTheme.ACCENT_SOFT
  static readonly INPUT: Resource = AppTheme.INPUT
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
