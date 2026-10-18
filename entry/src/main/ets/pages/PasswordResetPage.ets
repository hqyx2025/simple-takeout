import { AppButtonStyle, AppCardStyle, AppInputStyle, AppTheme } from '../common/theme/AppTheme'
import { COLORS, FONT_SIZE, SPACING } from '../common/Constants'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { requestEmailCodeApi, resetLoginPasswordApi, resetPaymentPasswordApi, PaymentPasswordResult, EmailCodeResult } from '../service/ApiService'
import { getAuthToken } from '../service/HttpClient'
import { User } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { KeyboardAvoidMode } from '@kit.ArkUI'

@Entry
@Component
export struct PasswordResetPage {
  @StorageLink('user') user: User = {
    id: 0, username: '', avatar: '', phone: '', email: '', password: '', role: 0,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State mode: string = 'login'
  @State phone: string = ''
  @State email: string = ''
  @State cooldownSeconds: number = 0
  private cooldownTimer: number = -1
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
    this.email = this.user.email ?? ''
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

  aboutToDisappear(): void { this.restoreKeyboardAvoidMode(); this.clearFields(); if (this.cooldownTimer !== -1) { clearInterval(this.cooldownTimer) } }

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

  private validAccount(): boolean {
    if (!/^1\d{10}$/.test(this.phone.trim())) {
      promptAction.showToast({ message: '请输入该账号绑定的 11 位手机号', duration: 1800 })
      return false
    }
    return true
  }

  private async sendCode(): Promise<void> {
    if (this.sendingCode || this.cooldownSeconds > 0) { return }
    if (!this.validAccount()) { return }
    const email: string = this.email.trim()
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      promptAction.showToast({ message: '请输入正确的邮箱地址', duration: 1800 })
      return
    }
    this.sendingCode = true
    const result: EmailCodeResult = await requestEmailCodeApi(this.phone.trim(), email, this.mode)
    this.sendingCode = false
    if (!result.success) {
      promptAction.showToast({ message: result.message || '验证码发送失败，请稍后重试', duration: 1800 })
      return
    }
    this.cooldownSeconds = 60
    this.cooldownTimer = setInterval(() => {
      this.cooldownSeconds = Math.max(0, this.cooldownSeconds - 1)
      if (this.cooldownSeconds === 0) { clearInterval(this.cooldownTimer); this.cooldownTimer = -1 }
    }, 1000)
    promptAction.showToast({ message: '验证码已发送', duration: 1500 })
  }

  private async submit(): Promise<void> {
    if (this.busy || !this.validAccount()) { return }
    const email: string = this.email.trim()
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || this.code.trim() === '') {
      promptAction.showToast({ message: '请填写邮箱和验证码', duration: 1800 })
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
      ? await resetLoginPasswordApi(this.phone.trim(), email, this.code.trim(), this.newPassword)
      : await resetPaymentPasswordApi(this.phone.trim(), email, this.code.trim(), this.newPassword)
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
            Text('填写要找回的手机号和绑定邮箱。验证码仅用于该手机号对应账户的本次密码重置。')
              .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
            Text('绑定手机号').fontSize(FONT_SIZE.SM).fontColor(AppTheme.TEXT).width('100%')
            TextInput({ text: this.phone, placeholder: '请输入该账号绑定的 11 位手机号' }).attributeModifier(new AppInputStyle())
              .type(InputType.PhoneNumber).maxLength(11).width('100%').id('password-reset-phone')
              .onChange((value: string) => { this.phone = value; this.code = '' })
            Text('绑定邮箱').fontSize(FONT_SIZE.SM).fontColor(AppTheme.TEXT).width('100%')
            TextInput({ text: this.email, placeholder: '例如 name@qq.com' }).attributeModifier(new AppInputStyle())
              .type(InputType.Email).width('100%').id('password-reset-email')
              .onChange((value: string) => { this.email = value; this.code = '' })
            Row({ space: SPACING.SM }) {
              TextInput({ text: this.code, placeholder: '邮箱验证码' }).attributeModifier(new AppInputStyle())
                .type(InputType.Number).maxLength(6).layoutWeight(1).id('password-reset-code')
                .onChange((value: string) => { this.code = value })
              Button(this.sendingCode ? '发送中…' : this.cooldownSeconds > 0 ? this.cooldownSeconds + '秒后重发' : '获取验证码').attributeModifier(new AppButtonStyle())
                .height(AppTheme.CONTROL_HEIGHT).width(120).enabled(!this.sendingCode && this.cooldownSeconds === 0)
                .id('password-reset-send-code').onClick(() => { this.sendCode() })
            }.width('100%')
            Text('验证码 15 分钟内有效，请勿向他人泄露。').fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
            TextInput({ text: this.newPassword, placeholder: this.mode === 'login' ? '请输入新登录密码，至少 6 位' : '请输入 6 位支付密码' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).width('100%')
              .maxLength(this.mode === 'payment' ? 6 : 64).id('password-reset-new')
              .onChange((value: string) => { this.newPassword = this.mode === 'payment' ? value.replace(/[^0-9]/g, '') : value })
            TextInput({ text: this.confirmPassword, placeholder: '请再次输入密码' }).attributeModifier(new AppInputStyle())
              .type(InputType.Password).width('100%').maxLength(this.mode === 'payment' ? 6 : 64)
              .id('password-reset-confirm').onChange((value: string) => { this.confirmPassword = this.mode === 'payment' ? value.replace(/[^0-9]/g, '') : value })

          }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')
        }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      Row() {
        Button(this.busy ? '提交中…' : '确认重置').attributeModifier(new AppButtonStyle())
          .height(AppTheme.CONTROL_HEIGHT).width('100%').enabled(!this.busy)
          .id('password-reset-submit').onClick(() => { this.submit() })
      }.width('100%').padding(SPACING.LG).backgroundColor(AppTheme.PAGE)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
