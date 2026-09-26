/** 登录样板局部主题；使用双态资源，避免改变其他页面的全局颜色。 */
export class LoginTheme {
  static readonly FORM_MAX_WIDTH: number = 460
  static readonly CONTROL_HEIGHT: number = 52
  static readonly CONTROL_RADIUS: number = 14

  static readonly PAGE: Resource = $r('app.color.login_page')
  static readonly CARD: Resource = $r('app.color.login_card')
  static readonly TEXT: Resource = $r('app.color.login_text')
  static readonly MUTED: Resource = $r('app.color.login_muted')
  static readonly BORDER: Resource = $r('app.color.login_border')
  static readonly INPUT: Resource = $r('app.color.login_input')
  static readonly ACCENT: Resource = $r('app.color.login_accent')
  static readonly ACCENT_SOFT: Resource = $r('app.color.login_accent_soft')
  static readonly PRIMARY: Resource = $r('app.color.login_primary')
  static readonly PRIMARY_TEXT: Resource = $r('app.color.login_primary_text')
  static readonly ERROR: Resource = $r('app.color.login_error')
  static readonly ERROR_BG: Resource = $r('app.color.login_error_bg')
  static readonly SUCCESS: Resource = $r('app.color.login_success')
  static readonly SUCCESS_BG: Resource = $r('app.color.login_success_bg')
}
