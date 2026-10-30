import { AppButtonStyle, AppInputStyle, AppTheme } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { EmailCaptchaField } from '../components/EmailCaptchaField'
import { FormInput } from '../components/FormInput'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { requestEmailCodeApi, resetLoginPasswordApi, resetPaymentPasswordApi, PaymentPasswordResult, EmailCodeResult } from '../service/ApiService'
import { getAuthToken } from '../service/HttpClient'
import { User } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import { newPasswordError } from '../common/PasswordPolicy'

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
  @State captchaId: string = ''
  @State captchaCode: string = ''
  @State errorMsg: string = ''
  @State errorField: string = ''
  @State tipMsg: string = ''
  private pageActive: boolean = true
  private sessionToken: string = ''
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET
  private keyboardModeChanged: boolean = false

  aboutToAppear(): void {
    this.pageActive = true
    this.phone = this.loggedIn ? this.user.phone : AppStorage.get<string>('passwordResetPhone') ?? ''
    AppStorage.setOrCreate<string>('passwordResetPhone', '')
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

  aboutToDisappear(): void { this.pageActive = false; this.restoreKeyboardAvoidMode(); this.clearFields(); if (this.cooldownTimer !== -1) { clearInterval(this.cooldownTimer) } }

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
      this.showError('请输入该账号绑定的 11 位手机号', 'password-reset-phone')
      return false
    }
    return true
  }

  private async sendCode(): Promise<void> {
    if (this.busy || this.sendingCode || this.cooldownSeconds > 0) { return }
    this.clearFeedback()
    if (!this.validAccount()) { return }
    const email: string = this.email.trim()
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      this.showError('请输入正确的邮箱地址', 'password-reset-email')
      return
    }
    if (!this.captchaId && /^[A-Za-z0-9]{5}$/.test(this.captchaCode)) {
      this.showError('校对码已使用，请点击图片更换后重试', 'email-captcha-input')
      return
    }
    if (!this.captchaId || !/^[A-Za-z0-9]{5}$/.test(this.captchaCode)) {
      this.showError('请先输入图片中的 5 位校对码', 'email-captcha-input')
      return
    }
    this.sendingCode = true
    const captchaId: string = this.captchaId
    this.captchaId = ''
    try {
      const result: EmailCodeResult = await requestEmailCodeApi(this.phone.trim(), email, this.mode, '', captchaId, this.captchaCode)
      if (!this.pageActive) { return }
      if (!result.success) {
        this.showError(result.message || '验证码发送失败，请稍后重试')
        return
      }
      this.cooldownSeconds = 60
      this.cooldownTimer = setInterval(() => {
        this.cooldownSeconds = Math.max(0, this.cooldownSeconds - 1)
        if (this.cooldownSeconds === 0) { clearInterval(this.cooldownTimer); this.cooldownTimer = -1 }
      }, 1000)
      this.tipMsg = result.mock === true && result.code !== undefined ? `开发模式验证码：${result.code}` : '验证码已发送，15 分钟内有效。'
    } catch (_) {
      if (this.pageActive) { this.showError('验证码发送失败，请检查网络后重试') }
    } finally {
      this.sendingCode = false
    }
  }

  private clearFeedback(): void {
    this.errorMsg = ''; this.errorField = ''; this.tipMsg = ''
  }

  private showError(message: string, field: string = ''): void {
    this.tipMsg = ''; this.errorMsg = message
    this.errorField = field || (/校对码/.test(message) ? 'email-captcha-input'
      : /验证码/.test(message) ? 'password-reset-code' : /邮箱/.test(message) ? 'password-reset-email'
      : /手机号/.test(message) ? 'password-reset-phone' : /密码/.test(message) ? 'password-reset-new' : '')
  }

  private async submit(): Promise<void> {
    if (this.busy || this.sendingCode) { return }
    this.clearFeedback()
    if (!this.validAccount()) { return }
    const email: string = this.email.trim()
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      this.showError('请输入正确的邮箱地址', 'password-reset-email'); return
    }
    if (!/^\d{6}$/.test(this.code.trim())) {
      this.showError('请输入 6 位邮箱验证码', 'password-reset-code'); return
    }
    if (this.mode === 'login' && newPasswordError(this.newPassword)) {
      this.showError(newPasswordError(this.newPassword), 'password-reset-new'); return
    }
    if (this.mode === 'payment' && !/^\d{6}$/.test(this.newPassword)) {
      this.showError('新支付密码必须是 6 位数字', 'password-reset-new'); return
    }
    if (this.newPassword !== this.confirmPassword) {
      this.showError('两次输入的密码不一致', 'password-reset-confirm'); return
    }
    this.busy = true
    try {
      const result: PaymentPasswordResult = this.mode === 'login'
        ? await resetLoginPasswordApi(this.phone.trim(), email, this.code.trim(), this.newPassword)
        : await resetPaymentPasswordApi(this.phone.trim(), email, this.code.trim(), this.newPassword)
      if (!this.pageActive) { return }
      if (!result.success) {
        this.showError(result.message || '密码重置失败，请重试'); return
      }
      this.clearFields()
      promptAction.showToast({ message: this.mode === 'login' ? '登录密码已重置，请重新登录' : '支付密码已重置', duration: 2200 })
      if (this.mode === 'login' && this.loggedIn && this.sessionToken === getAuthToken()) {
        await logout()
        router.replaceUrl({ url: 'pages/Index' })
      } else {
        router.back()
      }
    } catch (_) {
      if (this.pageActive) { this.showError('操作未完成，请检查网络后重试') }
    } finally {
      this.busy = false
    }
  }

  build() {
    Column() {
      PageHeader({ title: this.mode === 'login' ? '找回登录密码' : '找回支付密码', topPadding: 0,
        showBack: true, backId: 'password-reset-back', onBack: () => { router.back() } })
      if ((this.errorMsg && !this.errorField) || this.tipMsg) {
        Row() {
          Text(this.errorMsg || this.tipMsg).fontSize(14).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
            .fontColor(this.errorMsg ? AppTheme.ERROR : AppTheme.SUCCESS).padding(12).width('100%')
            .border({ width: 1, color: this.errorMsg ? AppTheme.ERROR : AppTheme.SUCCESS })
            .backgroundColor(this.errorMsg ? AppTheme.ERROR_BG : AppTheme.SUCCESS_BG).borderRadius(10)
            .constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH }).id('password-reset-message')
        }.width('100%').justifyContent(FlexAlign.Center).padding({ left: 24, right: 24, top: 8 })
      }
      Scroll() {
        Column() {
          Column({ space: 8 }) {
            FormInput({ compact: true, label: '绑定手机号', placeholder: '请输入11位手机号', value: this.phone,
              inputType: InputType.PhoneNumber, maxLength: 11, fieldId: 'password-reset-phone', isEnabled: !this.busy && !this.sendingCode,
              errorMessage: this.errorField === 'password-reset-phone' ? this.errorMsg : '',
              onChange: (value: string) => { this.phone = value; this.code = ''; this.clearFeedback() } })
            FormInput({ compact: true, label: '绑定邮箱', placeholder: '请输入邮箱', value: this.email,
              inputType: InputType.Email, fieldId: 'password-reset-email', isEnabled: !this.busy && !this.sendingCode,
              errorMessage: this.errorField === 'password-reset-email' ? this.errorMsg : '',
              onChange: (value: string) => { this.email = value; this.code = ''; this.clearFeedback() } })
            EmailCaptchaField({ captchaId: $captchaId, captchaCode: $captchaCode,
              disabled: this.busy || this.sendingCode,
              errorMessage: this.errorField === 'email-captcha-input' ? this.errorMsg : '' })
            Column({ space: 4 }) {
              Text('邮箱验证码').fontSize(13).fontColor(AppTheme.TEXT).width('100%')
              Row({ space: 8 }) {
                TextInput({ text: this.code, placeholder: '请输入 6 位验证码' }).attributeModifier(new AppInputStyle())
                  .height(44).type(InputType.Number).maxLength(6).layoutWeight(1).id('password-reset-code')
                  .enabled(!this.busy && !this.sendingCode)
                  .onChange((value: string) => { this.code = value; this.clearFeedback() })
                Button(this.sendingCode ? '发送中…' : this.cooldownSeconds > 0 ? this.cooldownSeconds + '秒后重发' : '获取验证码')
                  .attributeModifier(new AppButtonStyle()).height(44).width(120)
                  .enabled(!this.busy && !this.sendingCode && this.cooldownSeconds === 0)
                  .id('password-reset-send-code').onClick(() => { this.sendCode() })
              }.width('100%')
              if (this.errorMsg && this.errorField === 'password-reset-code') {
                Text(this.errorMsg).fontSize(13).fontColor(AppTheme.ERROR).width('100%').id('password-reset-code-error')
              }
            }.width('100%')
            FormInput({ compact: true, label: this.mode === 'login' ? '新登录密码' : '新支付密码',
              placeholder: this.mode === 'login' ? '请输入 6 至 64 位密码' : '请输入 6 位数字', value: this.newPassword,
              inputType: InputType.Password, maxLength: this.mode === 'payment' ? 6 : 64, passwordRules: this.mode === 'login',
              fieldId: 'password-reset-new', isEnabled: !this.busy && !this.sendingCode,
              errorMessage: this.errorField === 'password-reset-new' ? this.errorMsg : '',
              onChange: (value: string) => { this.newPassword = this.mode === 'payment' ? value.replace(/[^0-9]/g, '') : value; this.clearFeedback() } })
            FormInput({ compact: true, label: '确认新密码', placeholder: '请再次输入相同密码', value: this.confirmPassword,
              inputType: InputType.Password, maxLength: this.mode === 'payment' ? 6 : 64,
              fieldId: 'password-reset-confirm', isEnabled: !this.busy && !this.sendingCode,
              errorMessage: this.errorField === 'password-reset-confirm' ? this.errorMsg : '',
              onChange: (value: string) => { this.confirmPassword = this.mode === 'payment' ? value.replace(/[^0-9]/g, '') : value; this.clearFeedback() } })
          }.width('100%').constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH })
        }.width('100%').padding({ left: 24, right: 24, top: 16, bottom: 12 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      Row() {
        Button(this.busy ? '提交中…' : '确认重置').attributeModifier(new AppButtonStyle())
          .height(44).width('100%').constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH }).enabled(!this.busy && !this.sendingCode)
          .id('password-reset-submit').onClick(() => { this.submit() })
      }.width('100%').justifyContent(FlexAlign.Center).padding({ left: 24, right: 24, top: 8, bottom: 16 })
    }.width('100%').height('100%').backgroundColor(AppTheme.PAGE)
  }
}
