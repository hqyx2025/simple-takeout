/**
 * 登录/注册页面
 * 支持商户账户和普通用户账户
 */
import { UserRole } from '../model/Models'
import { loginRemote, registerRemote, logout } from '../service/AppStorageManager'
import { logInfo, logWarn } from '../service/AppLogger'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'

@Component
export struct LoginPage {
  @State isLoginMode: boolean = true  // true=登录 false=注册
  @State selectedRole: UserRole = UserRole.CUSTOMER
  @State phone: string = ''
  @State password: string = ''
  @State username: string = ''
  @State errorMsg: string = ''
  @State submitting: boolean = false
  onLoginSuccess: () => void = () => {}

  build() {
    Column() {
      // 顶部Logo区域
      Column({ space: 8 }) {
        Text('🍜')
          .fontSize(60)
        Text('简单外卖')
          .fontSize(FONT_SIZE.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text('美味送到家')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
      }
      .width('100%')
      .margin({ top: 60, bottom: 40 })

      // 角色选择（仅注册模式显示）
      if (!this.isLoginMode) {
        Text('选择账户类型')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
        Row({ space: SPACING.MD }) {
          Button('我是用户')
            .width('45%')
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(this.selectedRole === UserRole.CUSTOMER ? Color.White : COLORS.PRIMARY)
            .backgroundColor(this.selectedRole === UserRole.CUSTOMER ? COLORS.PRIMARY : Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .borderWidth(this.selectedRole === UserRole.CUSTOMER ? 0 : 1)
            .borderColor(COLORS.PRIMARY)
            .onClick(() => { this.selectedRole = UserRole.CUSTOMER })

          Button('我是商户')
            .width('45%')
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(this.selectedRole === UserRole.MERCHANT ? Color.White : COLORS.PRIMARY)
            .backgroundColor(this.selectedRole === UserRole.MERCHANT ? COLORS.PRIMARY : Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .borderWidth(this.selectedRole === UserRole.MERCHANT ? 0 : 1)
            .borderColor(COLORS.PRIMARY)
            .onClick(() => { this.selectedRole = UserRole.MERCHANT })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: SPACING.LG })
      }

      // 角色提示（登录模式下显示）
      if (this.isLoginMode) {
        Text('请选择身份登录')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
          .width('100%')
          .margin({ bottom: 4 })
        Row({ space: SPACING.SM }) {
          Text('👤 用户点餐')
            .fontSize(FONT_SIZE.SM)
            .fontColor(this.selectedRole === UserRole.CUSTOMER ? COLORS.PRIMARY : COLORS.TEXT_HINT)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.selectedRole === UserRole.CUSTOMER ? COLORS.TAG_BG : '#F5F5F5')
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.selectedRole = UserRole.CUSTOMER })
          Text('🏪 商户管理')
            .fontSize(FONT_SIZE.SM)
            .fontColor(this.selectedRole === UserRole.MERCHANT ? COLORS.PRIMARY : COLORS.TEXT_HINT)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.selectedRole === UserRole.MERCHANT ? COLORS.TAG_BG : '#F5F5F5')
            .borderRadius(BORDER_RADIUS.ROUND)
            .onClick(() => { this.selectedRole = UserRole.MERCHANT })
        }
        .width('100%')
        .margin({ bottom: SPACING.LG })
      }

      // 用户名（注册时显示）
      if (!this.isLoginMode) {
        TextInput({ placeholder: '请输入用户名', text: this.username })
          .fontSize(FONT_SIZE.LG)
          .width('100%')
          .height(48)
          .margin({ bottom: SPACING.MD })
          .onChange((value: string) => { this.username = value })
      }

      // 手机号
      TextInput({ placeholder: '请输入手机号', text: this.phone })
        .fontSize(FONT_SIZE.LG)
        .width('100%')
        .height(48)
        .margin({ bottom: SPACING.MD })
        .type(InputType.PhoneNumber)
        .id('login-phone')
        .onChange((value: string) => { this.phone = value })

      // 密码
      TextInput({ placeholder: '请输入密码', text: this.password })
        .fontSize(FONT_SIZE.LG)
        .width('100%')
        .height(48)
        .margin({ bottom: SPACING.LG })
        .type(InputType.Password)
        .id('login-password')
        .onChange((value: string) => { this.password = value })

      // 错误提示
      if (this.errorMsg) {
        Text(this.errorMsg)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.ERROR)
          .width('100%')
          .margin({ bottom: SPACING.SM })
      }

      // 登录/注册按钮
      Button(this.submitting ? '提交中…' : (this.isLoginMode ? '登 录' : '注 册'))
        .width('100%')
        .height(48)
        .fontSize(FONT_SIZE.XL)
        .fontColor(Color.White)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .id('login-submit')
        .enabled(!this.submitting)
        .margin({ top: SPACING.SM })
        .onClick(async () => {
          if (this.submitting) {
            return
          }
          this.submitting = true
          this.errorMsg = ''
          if (this.phone === '' || this.password === '') {
            logWarn('Auth', '登录/注册提交失败：手机号或密码为空')
            this.errorMsg = '请输入手机号和密码'
            this.submitting = false
            return
          }
          if (!this.isLoginMode && this.username === '') {
            logWarn('Auth', '注册提交失败：用户名为空')
            this.errorMsg = '请输入用户名'
            this.submitting = false
            return
          }
          logInfo('Auth', `用户点击${this.isLoginMode ? '登录' : '注册'} phone=${this.phone} role=${this.selectedRole === UserRole.MERCHANT ? '商户' : '用户'}`)

          if (this.isLoginMode) {
            const user = await loginRemote(this.phone, this.password)
            if (user !== undefined) {
              if (user.role !== this.selectedRole) {
                this.errorMsg = this.selectedRole === UserRole.MERCHANT ? '该账号不是商户账号' : '该账号不是用户账号'
                logout()
                logWarn('Auth', `登录角色不匹配 phone=${this.phone} 期望角色=${this.selectedRole}`)
                this.submitting = false
                return
              }
              this.onLoginSuccess()
            } else {
              this.errorMsg = '手机号或密码错误'
              this.submitting = false
            }
          } else {
            const newUser = await registerRemote(this.username, this.phone, this.password, this.selectedRole)
            if (newUser !== undefined) {
              const loginUser = await loginRemote(this.phone, this.password)
              if (loginUser !== undefined) {
                this.onLoginSuccess()
              } else {
                this.errorMsg = '注册成功，但自动登录失败，请手动登录'
              }
            } else {
              this.errorMsg = '该手机号已注册'
              logWarn('Auth', `注册失败：手机号已存在 phone=${this.phone}`)
            }
            this.submitting = false
          }
        })

      // 测试环境快捷登录：直接使用预置账号完成登录，无需手动填写手机号和密码
      if (this.isLoginMode) {
        Row({ space: SPACING.MD }) {
          Button('一键登录用户')
            .layoutWeight(1)
            .height(40)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.PRIMARY)
            .backgroundColor('#FFF8F0')
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .id('quick-login-user')
            .enabled(!this.submitting)
            .onClick(() => { this.quickLogin('13800138000', UserRole.CUSTOMER) })
          Button('一键登录商户')
            .layoutWeight(1)
            .height(40)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.PRIMARY)
            .backgroundColor('#FFF8F0')
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .id('quick-login-merchant')
            .enabled(!this.submitting)
            .onClick(() => { this.quickLogin('13600136000', UserRole.MERCHANT) })
        }
        .width('100%')
        .margin({ top: SPACING.MD })
      }

      // 切换登录/注册
      Row({ space: 4 }) {
        Text(this.isLoginMode ? '还没有账号？' : '已有账号？')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
        Text(this.isLoginMode ? '立即注册' : '去登录')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .fontWeight(FontWeight.Bold)
          .onClick(() => {
            this.isLoginMode = !this.isLoginMode
            this.errorMsg = ''
            logInfo('Auth', `切换${this.isLoginMode ? '登录' : '注册'}模式`)
          })
      }
      .margin({ top: SPACING.LG })
    }
    .width('100%')
    .height('100%')
    .padding({ left: SPACING.XL, right: SPACING.XL })
    .backgroundColor(COLORS.BG_WHITE)
  }

  private async quickLogin(phone: string, role: UserRole): Promise<void> {
    if (this.submitting) {
      return
    }
    this.submitting = true
    this.errorMsg = ''
    this.selectedRole = role
    const user = await loginRemote(phone, '123456')
    if (user !== undefined && user.role === role) {
      this.phone = phone
      this.password = '123456'
      this.onLoginSuccess()
    } else {
      if (user !== undefined) {
        logout()
      }
      this.errorMsg = role === UserRole.MERCHANT ? '商户快捷登录失败，请确认测试账号可用' : '用户快捷登录失败，请确认测试账号可用'
    }
    this.submitting = false
  }
}
