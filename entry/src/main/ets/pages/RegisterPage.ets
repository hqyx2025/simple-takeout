import { User, UserRole } from '../model/Models'
import { PageHeader } from '../components/PageHeader'
import { FormInput } from '../components/FormInput'
import { EmailCaptchaField } from '../components/EmailCaptchaField'
import { AppTheme, AppInputStyle, AppButtonStyle } from '../common/theme/AppTheme'
import { newPasswordError } from '../common/PasswordPolicy'
import { registerRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { requestEmailCodeApi, EmailCodeResult, checkUsernameAvailableApi } from '../service/ApiService'
import { routerCompat as router } from '../common/UiNavigation'
import { KeyboardAvoidMode } from '@kit.ArkUI'

@Entry
@Component
struct RegisterPage {
  @State username: string = ''
  @State usernameError: string = ''
  private usernameCheckVersion: number = 0
  private usernameCheckTimer: number = -1
  private checkedUsername: string = ''
  private usernameAvailable: boolean | null = null
  @State phone: string = ''
  @State email: string = ''
  @State emailCode: string = ''
  @State password: string = ''
  @State confirmPassword: string = ''
  @State captchaId: string = ''
  @State captchaCode: string = ''
  @State submitting: boolean = false
  @State sendingCode: boolean = false
  @State cooldownSeconds: number = 0
  @State errorMsg: string = ''
  @State errorField: string = ''
  @State tipMsg: string = ''
  private cooldownTimer: number = -1
  private pageActive: boolean = true
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET

  aboutToAppear(): void {
    this.pageActive = true
    this.phone = AppStorage.get<string>('registrationPhone') ?? ''
    AppStorage.setOrCreate<string>('registrationPhone', '')
    this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode()
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.usernameCheckVersion++
    if (this.usernameCheckTimer !== -1) { clearTimeout(this.usernameCheckTimer); this.usernameCheckTimer = -1 }
    if (this.cooldownTimer !== -1) { clearInterval(this.cooldownTimer); this.cooldownTimer = -1 }
    this.password = ''; this.confirmPassword = ''; this.emailCode = ''; this.captchaId = ''; this.captchaCode = ''
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode)
  }

  build() {
    Column() {
      PageHeader({ title: '注册', backId: 'login-mode-login', backText: '‹ 返回登录', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: 8 }) {
          if ((this.errorMsg && !this.errorField) || this.tipMsg) {
            Text(this.errorMsg || this.tipMsg).fontSize(14).width('100%').padding(10).borderRadius(10)
              .fontColor(this.errorMsg ? AppTheme.ERROR : AppTheme.SUCCESS)
              .backgroundColor(this.errorMsg ? AppTheme.ERROR_BG : AppTheme.SUCCESS_BG)
              .id(this.errorMsg ? 'register-error' : 'register-success')
          }
          FormInput({ compact: true, label: '用户名', placeholder: '请输入用户名', value: this.username,
            icon: $r('app.media.login_user'), fieldId: 'login-username', maxLength: 64,
            isEnabled: !this.submitting && !this.sendingCode,
            errorMessage: this.usernameError || (this.errorField === 'login-username' ? this.errorMsg : ''),
            onChange: (value: string) => { this.usernameChanged(value) },
            onInputBlur: () => { this.checkUsername() } })
          FormInput({ compact: true, label: '邮箱', placeholder: '请输入邮箱', value: this.email,
            icon: $r('app.media.login_user'), inputType: InputType.Email, fieldId: 'login-email', maxLength: 254,
            isEnabled: !this.submitting && !this.sendingCode, errorMessage: this.errorField === 'login-email' ? this.errorMsg : '',
            onChange: (value: string) => { this.email = value; this.emailCode = ''; this.clearFeedback() } })
          FormInput({ compact: true, label: '手机号', placeholder: '请输入 11 位手机号', value: this.phone,
            icon: $r('app.media.login_phone'), inputType: InputType.PhoneNumber, fieldId: 'login-phone', maxLength: 11,
            isEnabled: !this.submitting && !this.sendingCode, errorMessage: this.errorField === 'login-phone' ? this.errorMsg : '',
            onChange: (value: string) => { this.phone = value; this.emailCode = ''; this.clearFeedback() } })
          this.verificationCodeField()
          FormInput({ compact: true, label: '密码', placeholder: '请输入 6 至 64 位密码', value: this.password,
            icon: $r('app.media.login_lock'), inputType: InputType.Password, fieldId: 'login-password', maxLength: 64, passwordRules: true,
            isEnabled: !this.submitting && !this.sendingCode, errorMessage: this.errorField === 'login-password' ? this.errorMsg : '',
            onChange: (value: string) => { this.password = value; this.clearFeedback() } })
          FormInput({ compact: true, label: '确认密码', placeholder: '请再次输入相同密码', value: this.confirmPassword,
            icon: $r('app.media.login_lock'), inputType: InputType.Password, fieldId: 'login-confirm-password', maxLength: 64,
            isEnabled: !this.submitting && !this.sendingCode, errorMessage: this.errorField === 'login-confirm-password' ? this.errorMsg : '',
            onChange: (value: string) => { this.confirmPassword = value; this.clearFeedback() } })
        }.width('100%').constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH }).padding({ top: 16, bottom: 12 }).flexShrink(0)
      }.width('100%').layoutWeight(1).padding({ left: 24, right: 24 }).scrollBar(BarState.Off)
      Row() {
        Button(this.submitting ? '注册中…' : '注册', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonStyle()).height(44).width('100%')
          .constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH }).id('register-submit')
          .enabled(!this.submitting && !this.sendingCode).onClick(() => { this.submitForm() })
      }.width('100%').justifyContent(FlexAlign.Center).padding({ left: 24, right: 24, top: 8, bottom: 20 })
    }.width('100%').height('100%').backgroundColor(AppTheme.PAGE)
  }

  private usernameChanged(value: string): void {
    this.username = value
    this.usernameCheckVersion++
    this.usernameError = ''; this.checkedUsername = ''; this.usernameAvailable = null
    this.clearFeedback()
    if (this.usernameCheckTimer !== -1) { clearTimeout(this.usernameCheckTimer) }
    this.usernameCheckTimer = -1
    if (!value.trim()) { return }
    this.usernameCheckTimer = setTimeout(() => { this.usernameCheckTimer = -1; this.checkUsername() }, 400)
  }

  private async checkUsername(): Promise<boolean> {
    if (!this.pageActive) { return false }
    if (this.usernameCheckTimer !== -1) { clearTimeout(this.usernameCheckTimer); this.usernameCheckTimer = -1 }
    const name: string = this.username.trim()
    if (!name) { return false }
    if (name === this.checkedUsername && this.usernameAvailable !== null) { return this.usernameAvailable }
    const version: number = ++this.usernameCheckVersion
    let available: boolean | null = null
    try { available = await checkUsernameAvailableApi(name) } catch (_) {}
    if (!this.pageActive || version !== this.usernameCheckVersion || name !== this.username.trim()) { return false }
    this.usernameAvailable = available
    this.checkedUsername = available === null ? '' : name
    this.usernameError = available === null ? '用户名暂时无法校验，请重试' : available ? '' : '用户名已重复'
    return available === true
  }

  @Builder
  private verificationCodeField() {
    Column({ space: 4 }) {
      EmailCaptchaField({ captchaId: $captchaId, captchaCode: $captchaCode,
        disabled: this.submitting || this.sendingCode,
        errorMessage: this.errorField === 'email-captcha-input' ? this.errorMsg : '' })
      Text('邮箱验证码').fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.emailCode, placeholder: '请输入 6 位验证码' })
          .attributeModifier(new AppInputStyle()).type(InputType.Number).maxLength(6)
          .height(44).layoutWeight(1).id('register-email-code')
          .enabled(!this.submitting && !this.sendingCode)
          .border({ width: this.errorField.endsWith('email-code') ? 1.5 : 1,
            color: this.errorField.endsWith('email-code') ? AppTheme.ERROR : AppTheme.BORDER })
          .onChange((value: string) => { this.emailCode = value; this.clearFeedback() })
        Button(this.sendingCode ? '发送中…' : this.cooldownSeconds > 0 ? this.cooldownSeconds + '秒后重发' : '获取验证码')
          .attributeModifier(new AppButtonStyle()).height(44).width(120).id('register-send-code')
          .enabled(!this.sendingCode && this.cooldownSeconds === 0 && !this.submitting)
          .onClick(() => { this.sendVerificationCode() })
      }.width('100%').height(44).flexShrink(0)
      if (this.errorMsg && this.errorField.endsWith('email-code')) {
        Text(this.errorMsg).fontSize(13).fontColor(AppTheme.ERROR).width('100%')
          .id('register-email-code-error')
      }
    }.width('100%').margin({ bottom: 8 }).flexShrink(0)
  }

  private async sendVerificationCode(): Promise<void> {
    if (this.sendingCode || this.cooldownSeconds > 0 || this.submitting) { return }
    this.clearFeedback()
    if (this.username.trim() === '') { this.showError('请输入用户名', 'login-username'); return }
    if (!/^1\d{10}$/.test(this.phone.trim())) { this.showError('请输入正确的 11 位手机号', 'login-phone'); return }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email.trim())) { this.showError('请输入正确的邮箱地址', 'login-email'); return }
    if (!this.captchaId && /^[A-Za-z0-9]{5}$/.test(this.captchaCode)) {
      this.showError('校对码已使用，请点击图片更换后重试', 'email-captcha-input'); return
    }
    if (!this.captchaId || !/^[A-Za-z0-9]{5}$/.test(this.captchaCode)) {
      this.showError('请先输入图片中的 5 位校对码', 'email-captcha-input'); return
    }
    this.sendingCode = true
    try {
      if (!await this.checkUsername()) { this.showError(this.usernameError || '请检查用户名', 'login-username'); return }
      const captchaId: string = this.captchaId
      this.captchaId = ''
      const result: EmailCodeResult = await requestEmailCodeApi(this.phone.trim(), this.email.trim(),
        'register', this.username.trim(), captchaId, this.captchaCode)
      if (!this.pageActive) { return }
      if (!result.success) {
        this.showError(result.message || '验证码发送失败，请稍后重试')
        return
      }
      this.tipMsg = result.mock === true && result.code !== undefined
        ? `开发模式验证码：${result.code}` : '验证码已发送至邮箱，15 分钟内有效。'
      this.cooldownSeconds = 60
      this.cooldownTimer = setInterval(() => {
        this.cooldownSeconds = Math.max(0, this.cooldownSeconds - 1)
        if (this.cooldownSeconds === 0) { clearInterval(this.cooldownTimer); this.cooldownTimer = -1 }
      }, 1000)
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
    this.tipMsg = ''
    this.errorMsg = message
    this.errorField = field || (/校对码/.test(message) ? 'email-captcha-input'
      : /验证码/.test(message) ? ('register-email-code')
      : /密码/.test(message) ? 'login-password' : /邮箱/.test(message) ? 'login-email'
      : /手机号/.test(message) ? 'login-phone' : /用户名|账号名/.test(message) ? 'login-username' : '')
  }

  private async submitForm(): Promise<void> {
    if (this.submitting || this.sendingCode) { return }
    this.clearFeedback()
    if (!this.username.trim()) { this.showError('请输入用户名', 'login-username'); return }
    if (!/^1\d{10}$/.test(this.phone.trim())) { this.showError('请输入正确的 11 位手机号', 'login-phone'); return }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email.trim())) { this.showError('请输入正确的邮箱地址', 'login-email'); return }
    if (!/^\d{6}$/.test(this.emailCode.trim())) { this.showError('请输入 6 位邮箱验证码', 'register-email-code'); return }
    if (newPasswordError(this.password)) { this.showError(newPasswordError(this.password), 'login-password'); return }
    if (this.password !== this.confirmPassword) {
      this.showError('两次输入的密码不一致，请重新输入确认密码', 'login-confirm-password'); return
    }
    this.submitting = true
    try {
      if (!await this.checkUsername()) { this.showError(this.usernameError || '请检查用户名', 'login-username'); return }
      const user: User | undefined = await registerRemote(this.username.trim(), this.phone.trim(), this.email.trim(),
        this.emailCode.trim(), this.password, UserRole.CUSTOMER)
      if (!this.pageActive) { return }
      if (user === undefined) { this.showError(getLastRemoteErrorMessage() || '注册失败，请核对信息后重试'); return }
      const phone: string = this.phone.trim()
      this.password = ''; this.confirmPassword = ''; this.emailCode = ''; this.captchaId = ''; this.captchaCode = ''
      AppStorage.setOrCreate<string>('registrationCompletedPhone', phone)
      router.back()
    } catch (_) {
      if (this.pageActive) { this.showError('操作未完成，请检查网络后重试') }
    } finally {
      this.submitting = false
    }
  }
}
