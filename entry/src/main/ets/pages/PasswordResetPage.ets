import { AppButtonStyle, AppCardStyle, AppInputStyle, AppTheme } from '../common/theme/AppTheme'
import { COLORS, FONT_SIZE, SPACING } from '../common/Constants'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { requestSmsCodeApi, resetLoginPasswordApi, resetPaymentPasswordApi, PaymentPasswordResult, SmsCodeResult } from '../service/ApiService'
import { getAuthToken } from '../service/HttpClient'
import { User } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { KeyboardAvoidMode } from '@kit.ArkUI'

@Entry
@Component
export struct PasswordResetPage {
  @StorageLink('user') user: User = {
    id: 0, username: '', avatar: '', phone: '', password: '', role: 0,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State mode: string = 'login'
  @State phone: string = ''
  @State code: string = ''
  @State newPassword: string = ''
  @State confirmPassword: string = ''
  @State busy: boolean = false
  @State sendingCode: boolean = false
  private sessionToken: string = ''
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET
  private keyboardModeChanged: boolean = false

  aboutToAppear(): void {
    this.phone = this.user.phone
    this.sessionToken = getAuthToken()
    this.mode = AppStorage.get<string>('passwordResetMode') === 'payment' ? 'payment' : 'login'
    AppStorage.setOrCreate<string>('passwordResetMode', 'login')
  }

  onPageShow(): void {
    if (this.keyboardModeChanged) { return }
    try {
      this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode()
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
      this.keyboardModeChanged = true
    } catch (_) {}
  }

  aboutToDisappear(): void { this.restoreKeyboardAvoidMode(); this.clearFields() }

  private restoreKeyboardAvoidMode(): void {
    if (!this.keyboardModeChanged) { return }
    try {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode)
      this.keyboardModeChanged = false
    } catch (_) {}
  }

  private clearFields(): void {
    this.code = ''
    this.newPassword = ''
    this.confirmPassword = ''
  }

  private async sendCode(): Promise<void> {
    if (this.sendingCode) { return }
    const phone: string = this.phone.trim()
    if (!/^1\d{10}$/.test(phone)) {
      promptAction.showToast({ message: '请输入正确的手机号', duration: 1800 })
      return
    }
    this.sendingCode = true
    const result: SmsCodeResult = await requestSmsCodeApi(phone)
    this.sendingCode = false
    if (!result.success) {
      promptAction.showToast({ message: '验证码发送失败，请稍后重试', duration: 1800 })
      return
    }
    // 当前开发环境为 Mock 短信，接口返回固定验证码；接入真实短信后此字段不会回传。
    this.code = result.code
    promptAction.showToast({ message: '验证码已发送', duration: 1500 })
  }

  private async submit(): Promise<void> {
    if (this.busy) { return }
    const phone: string = this.phone.trim()
    if (!/^1\d{10}$/.test(phone) || this.code.trim() === '') {
      promptAction.showToast({ message: '请填写手机号和验证码', duration: 1800 })
      return
    }
    if (this.mode === 'login' && this.newPassword.length < 6) {
      promptAction.showToast({ message: '新登录密码至少 6 位', duration: 1800 })
      return
    }
    if (this.mode === 'payment' && !/^\d{6}$/.test(this.newPassword)) {
      promptAction.showToast({ message: '新支付密码必须是 6 位数字', duration: 1800 })
      return
    }
    if (this.newPassword !== this.confirmPassword) {
      promptAction.showToast({ message: '两次输入的密码不一致', duration: 1800 })
      return
    }
    this.busy = true
    const result: PaymentPasswordResult = this.mode === 'login'
      ? await resetLoginPasswordApi(phone, this.code.trim(), this.newPassword)
      : await resetPaymentPasswordApi(phone, this.code.trim(), this.newPassword)
    this.busy = false
    this.clearFields()
    if (!result.success) {
      promptAction.showToast({ message: result.message || '密码重置失败，请重试', duration: 2200 })
      return
    }
    promptAction.showToast({ message: this.mode === 'login' ? '登录密码已重置，请重新登录' : '支付密码已重置', duration: 2200 })
    if (this.mode === 'login' && this.loggedIn && this.sessionToken === getAuthToken()) {
      logout()
      router.replaceUrl({ url: 'pages/Index' })
    } else {
      router.back()
    }
  }

  build() {
    Column() {
      PageHeader({ title: this.mode === 'login' ? '找回登录密码' : '找回支付密码',
        showBack: true, backId: 'password-reset-back', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.LG }) {
          Column({ space: SPACING.MD }) {
            Text(this.mode === 'login' ? '找回登录密码' : '找回支付密码')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT).width('100%')
            Text('通过手机号验证码验证身份，密码不会在页面上保存。')
              .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
            TextInput({ text: this.phone, placeholder: '请输入手机号' }).attributeModifier(new AppInputStyle())
              .type(InputType.PhoneNumber).width('100%').id('password-reset-phone')
              .onChange((value: string) => { this.phone = value })
            Row({ space: SPACING.SM }) {
              TextInput({ text: this.code, placeholder: '短信验证码' }).attributeModifier(new AppInputStyle())
                .type(InputType.Number).layoutWeight(1).id('password-reset-code')
                .onChange((value: string) => { this.code = value })
              Button(this.sendingCode ? '发送中…' : '获取验证码').attributeModifier(new AppButtonStyle())
                .height(AppTheme.CONTROL_HEIGHT).width(120).enabled(!this.sendingCode)
                .id('password-reset-send-code').onClick(() => { this.sendCode() })
            }.width('100%')
            TextInput({ text: this.newPassword, placeholder: this.mode === 'login' ? '请输入新登录密码，至少 6 位' : '请输入 6 位支付密码' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).width('100%')
              .maxLength(this.mode === 'payment' ? 6 : 64).id('password-reset-new')
              .onChange((value: string) => { this.newPassword = this.mode === 'payment' ? value.replace(/[^0-9]/g, '') : value })
            TextInput({ text: this.confirmPassword, placeholder: '请再次输入密码' }).attributeModifier(new AppInputStyle())
              .type(InputType.Password).width('100%').maxLength(this.mode === 'payment' ? 6 : 64)
              .id('password-reset-confirm').onChange((value: string) => { this.confirmPassword = this.mode === 'payment' ? value.replace(/[^0-9]/g, '') : value })
            Button(this.busy ? '提交中…' : '确认重置').attributeModifier(new AppButtonStyle())
              .height(AppTheme.CONTROL_HEIGHT).width('100%').enabled(!this.busy)
              .id('password-reset-submit').onClick(() => { this.submit() })
          }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')
        }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
