/**
 * 四端密码 / 邮箱验证码登录；公开注册仅创建用户账号。
 */
import { User, UserRole } from '../model/Models'
import { EmailCaptchaField } from '../components/EmailCaptchaField'
import { FormInput } from '../components/FormInput'
import { loginRemote, loginByEmailRemote, registerRemote, logout, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { logInfo, logWarn } from '../service/AppLogger'
import { APP_CONFIG } from '../common/Constants'
import { newPasswordError } from '../common/PasswordPolicy'
import BuildProfile from 'BuildProfile'
import { getQuickLoginAccount, QuickLoginAccount } from '../common/QuickLoginConfig'
import { getApiBaseUrl } from '../service/HttpClient'
import { AppTheme, AppInputStyle, AppButtonStyle } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'
import { requestEmailCodeApi, EmailCodeResult } from '../service/ApiService'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { KeyboardAvoidMode } from '@kit.ArkUI'

@Component
export struct LoginPage {
  @StorageLink('appReduceMotion') reduceMotion: boolean = false
  @State isLoginMode: boolean = true
  @State useEmailLogin: boolean = false
  @State selectedRole: UserRole = UserRole.CUSTOMER
  @State phone: string = ''
  @State email: string = ''
  @State emailCode: string = ''
  @State captchaId: string = ''
  @State captchaCode: string = ''
  @State sendingCode: boolean = false
  @State cooldownSeconds: number = 0
  private cooldownTimer: number = -1
  private pageActive: boolean = true
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET
  private keyboardModeChanged: boolean = false
  @State password: string = ''
  @State confirmPassword: string = ''
  @State username: string = ''
  @State errorMsg: string = ''
  @State errorField: string = ''
  @State tipMsg: string = ''
  @State submitting: boolean = false
  @State versionClickCount: number = 0
  onLoginSuccess: () => void = () => {}
  private quickLoginDialog: CustomDialogController = new CustomDialogController({
    builder: QuickLoginDialog({
      onSelectLogin: (role: UserRole): void => {
        this.quickLogin(role)
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Bottom,
    customStyle: true
  })

  build() {
    Column() {
      if ((this.errorMsg && !this.errorField) || this.tipMsg) {
        Row() {
          Column() {
            Text(this.errorMsg || this.tipMsg).fontSize(14).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
              .fontColor(this.errorMsg ? AppTheme.ERROR : AppTheme.SUCCESS).width('100%').padding(10)
              .border({ width: 1, color: this.errorMsg ? AppTheme.ERROR : AppTheme.SUCCESS })
              .backgroundColor(this.errorMsg ? AppTheme.ERROR_BG : AppTheme.SUCCESS_BG).borderRadius(10)
              .id(this.errorMsg ? 'login-error' : 'login-success').margin({ bottom: 8 })
          }.width('100%').constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH })
        }.width('100%').justifyContent(FlexAlign.Center).padding({ left: 24, right: 24, top: 8 })
      }
      Scroll() {
        Column() {
          Column() {
            this.brandHeader()
            this.modeSelector()
            if (this.isLoginMode) {
              this.roleSelector()
              this.loginMethodSelector()
            }

            if (!this.isLoginMode) {
              FormInput({ compact: true, label: '账号名', placeholder: '请输入账户名', value: this.username,
                icon: $r('app.media.login_user'), fieldId: 'login-username', isEnabled: !this.submitting && !this.sendingCode,
                errorMessage: this.errorField === 'login-username' ? this.errorMsg : '',
                onChange: (value: string) => { this.username = value; this.clearFeedback() } }).margin({ bottom: 4 })
              FormInput({ compact: true, label: '邮箱', placeholder: '请输入邮箱', value: this.email,
                icon: $r('app.media.login_user'), inputType: InputType.Email, fieldId: 'login-email', isEnabled: !this.submitting && !this.sendingCode,
                errorMessage: this.errorField === 'login-email' ? this.errorMsg : '',
                onChange: (value: string) => { this.email = value; this.emailCode = ''; this.clearFeedback() } }).margin({ bottom: 4 })
            }
            FormInput({ compact: true, label: '手机号', placeholder: '请输入11位手机号', value: this.phone,
              icon: $r('app.media.login_phone'), inputType: InputType.PhoneNumber, fieldId: 'login-phone', maxLength: 11,
              isEnabled: !this.submitting && !this.sendingCode, errorMessage: this.errorField === 'login-phone' ? this.errorMsg : '',
              onChange: (value: string) => { this.phone = value; this.emailCode = ''; this.clearFeedback() } }).margin({ bottom: 4 })
            if (this.isLoginMode && this.useEmailLogin) {
              FormInput({ compact: true, label: '绑定邮箱', placeholder: '请输入邮箱', value: this.email,
                icon: $r('app.media.login_user'), inputType: InputType.Email, fieldId: 'login-email', isEnabled: !this.submitting && !this.sendingCode,
                errorMessage: this.errorField === 'login-email' ? this.errorMsg : '',
                onChange: (value: string) => { this.email = value; this.emailCode = ''; this.clearFeedback() } }).margin({ bottom: 4 })
            }
            if (!this.isLoginMode || this.useEmailLogin) {
              this.verificationCodeField()
            }
            if (!this.isLoginMode || !this.useEmailLogin) {
              FormInput({ compact: true, label: '密码', placeholder: this.isLoginMode ? '请输入密码' : '请输入 6 至 64 位密码', value: this.password,
                icon: $r('app.media.login_lock'), inputType: InputType.Password, fieldId: 'login-password', maxLength: 64, passwordRules: !this.isLoginMode,
                isEnabled: !this.submitting && !this.sendingCode, errorMessage: this.errorField === 'login-password' ? this.errorMsg : '',
                onChange: (value: string) => { this.password = value; this.clearFeedback() } }).margin({ bottom: 4 })
            }
            if (!this.isLoginMode) {
              FormInput({ compact: true, label: '确认密码', placeholder: '请再次输入相同密码', value: this.confirmPassword,
                icon: $r('app.media.login_lock'), inputType: InputType.Password, fieldId: 'login-confirm-password', maxLength: 64,
                isEnabled: !this.submitting && !this.sendingCode, errorMessage: this.errorField === 'login-confirm-password' ? this.errorMsg : '',
                onChange: (value: string) => { this.confirmPassword = value; this.clearFeedback() } }).margin({ bottom: 4 })
            }
            if (this.isLoginMode && !this.useEmailLogin) {
              Button('忘记登录密码？')
                .fontSize(13).fontColor(AppTheme.ACCENT).backgroundColor(Color.Transparent)
                .height(36).width('100%').id('login-forgot-password')
                .enabled(!this.submitting && !this.sendingCode)
                .onClick(() => {
                  AppStorage.setOrCreate<string>('passwordResetMode', 'login')
                  AppStorage.setOrCreate<string>('passwordResetPhone', this.phone.trim())
                  router.pushUrl({ url: 'pages/PasswordResetPage' })
                })
            }

          }
          .width('100%')
          .constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 8 })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)

      Row() {
        Column() { this.submitButton() }
          .width('100%').constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH })
      }.width('100%').justifyContent(FlexAlign.Center)
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })

      // 固定底部入口，窄屏与长表单下也可连续点击三次打开快捷登录。
      if (this.isLoginMode) {
        Button('v' + APP_CONFIG.VERSION, { type: ButtonType.Normal })
          .fontSize(12)
          .fontColor(AppTheme.MUTED)
          .backgroundColor(Color.Transparent)
          .height(44)
          .padding({ left: 24, right: 24 })
          .borderRadius(12)
          .id('version-text')
          .margin({ bottom: 4 })
          .onClick(() => {
            if (!BuildProfile.DEBUG) { return }
            this.versionClickCount = this.versionClickCount + 1
            if (this.versionClickCount >= 3) {
              this.versionClickCount = 0
              this.quickLoginDialog.open()
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.PAGE)
  }

  aboutToAppear(): void {
    this.pageActive = true
    try {
      this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode()
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
      this.keyboardModeChanged = true
    } catch (_) {}
  }

  aboutToDisappear(): void {
    this.pageActive = false
    if (this.keyboardModeChanged) {
      try { this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode) } catch (_) {}
      this.keyboardModeChanged = false
    }
    if (this.cooldownTimer !== -1) { clearInterval(this.cooldownTimer); this.cooldownTimer = -1 }
    this.emailCode = ''
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
          .height(44).layoutWeight(1).id(this.isLoginMode ? 'login-email-code' : 'register-email-code')
          .enabled(!this.submitting && !this.sendingCode)
          .border({ width: this.errorField.endsWith('email-code') ? 1.5 : 1,
            color: this.errorField.endsWith('email-code') ? AppTheme.ERROR : AppTheme.BORDER })
          .onChange((value: string) => { this.emailCode = value; this.clearFeedback() })
        Button(this.sendingCode ? '发送中…' : this.cooldownSeconds > 0 ? this.cooldownSeconds + '秒后重发' : '获取验证码')
          .attributeModifier(new AppButtonStyle()).height(44).width(120).id(this.isLoginMode ? 'login-send-code' : 'register-send-code')
          .enabled(!this.sendingCode && this.cooldownSeconds === 0 && !this.submitting)
          .onClick(() => { this.sendVerificationCode() })
      }.width('100%')
      if (this.errorMsg && this.errorField.endsWith('email-code')) {
        Text(this.errorMsg).fontSize(13).fontColor(AppTheme.ERROR).width('100%')
          .id(this.isLoginMode ? 'login-email-code-error' : 'register-email-code-error')
      }
    }.width('100%').margin({ bottom: 8 })
  }

  private async sendVerificationCode(): Promise<void> {
    if (this.sendingCode || this.cooldownSeconds > 0 || this.submitting) { return }
    this.clearFeedback()
    if (!this.isLoginMode && this.username.trim() === '') { this.showError('请输入账号名', 'login-username'); return }
    if (!/^1\d{10}$/.test(this.phone.trim())) { this.showError('请输入正确的 11 位手机号', 'login-phone'); return }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email.trim())) { this.showError('请输入正确的邮箱地址', 'login-email'); return }
    if (!this.captchaId && /^[A-Za-z0-9]{5}$/.test(this.captchaCode)) {
      this.showError('校对码已使用，请点击图片更换后重试', 'email-captcha-input'); return
    }
    if (!this.captchaId || !/^[A-Za-z0-9]{5}$/.test(this.captchaCode)) {
      this.showError('请先输入图片中的 5 位校对码', 'email-captcha-input'); return
    }
    this.sendingCode = true
    const captchaId: string = this.captchaId
    this.captchaId = ''
    try {
      const result: EmailCodeResult = await requestEmailCodeApi(this.phone.trim(), this.email.trim(),
        this.isLoginMode ? 'signin' : 'register', this.username.trim(), captchaId, this.captchaCode)
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

  @Builder
  private loginMethodSelector() {
    Row({ space: 8 }) {
      this.loginMethodButton('密码登录', false, 'login-method-password')
      this.loginMethodButton('验证码登录', true, 'login-method-email')
    }.width('100%').margin({ bottom: 12 })
  }

  @Builder
  private loginMethodButton(label: string, emailLogin: boolean, id: string) {
    Button(label, { type: ButtonType.Normal }).height(44).layoutWeight(1)
      .fontSize(14).fontWeight(this.useEmailLogin === emailLogin ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.useEmailLogin === emailLogin ? AppTheme.ACCENT : AppTheme.MUTED)
      .backgroundColor(this.useEmailLogin === emailLogin ? AppTheme.ACCENT_SOFT : AppTheme.CARD)
      .border({ width: 1, color: this.useEmailLogin === emailLogin ? AppTheme.ACCENT : AppTheme.BORDER })
      .borderRadius(AppTheme.CONTROL_RADIUS).id(id).accessibilitySelected(this.useEmailLogin === emailLogin)
      .enabled(!this.submitting && !this.sendingCode).onClick(() => this.switchLoginMethod(emailLogin))
  }

  private switchLoginMethod(emailLogin: boolean): void {
    if (this.submitting || this.sendingCode || this.useEmailLogin === emailLogin) { return }
    this.useEmailLogin = emailLogin
    this.password = ''; this.confirmPassword = ''; this.emailCode = ''; this.captchaId = ''; this.captchaCode = ''
    this.clearFeedback()
  }

  private clearFeedback(): void {
    this.errorMsg = ''; this.errorField = ''; this.tipMsg = ''
  }

  private showError(message: string, field: string = ''): void {
    this.tipMsg = ''
    this.errorMsg = message
    this.errorField = field || (/校对码/.test(message) ? 'email-captcha-input'
      : /验证码/.test(message) ? (this.isLoginMode ? 'login-email-code' : 'register-email-code')
      : /密码/.test(message) ? 'login-password' : /邮箱/.test(message) ? 'login-email'
      : /手机号/.test(message) ? 'login-phone' : '')
  }

  @Builder
  private brandHeader() {
    Row({ space: 12 }) {
      Image($r('app.media.login_brand'))
        .width(36)
        .height(36)
        .objectFit(ImageFit.Contain)
        .accessibilityLevel('no')
      Column({ space: 5 }) {
        Text('简单外卖')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 10 })
  }

  @Builder
  private modeSelector() {
    Row({ space: 4 }) {
      this.modeButton('登录', true, 'login-mode-login')
      this.modeButton('注册', false, 'login-mode-register')
    }
    .width('100%')
    .padding(4)
    .backgroundColor(AppTheme.INPUT)
    .borderRadius(AppTheme.CONTROL_RADIUS)
    .margin({ bottom: 10 })
  }

  @Builder
  private modeButton(label: string, loginMode: boolean, id: string) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(44)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isLoginMode === loginMode ? AppTheme.TEXT : AppTheme.MUTED)
      .backgroundColor(this.isLoginMode === loginMode ? AppTheme.CARD : Color.Transparent)
      .borderRadius(10)
      .animation({ duration: this.reduceMotion ? 0 : AppMotion.PRESS, curve: Curve.EaseOut })
      .id(id)
      .accessibilitySelected(this.isLoginMode === loginMode)
      .accessibilityText(label + (this.isLoginMode === loginMode ? '，已选中' : '，未选中'))
      .enabled(!this.submitting && !this.sendingCode)
      .onClick(() => this.switchMode(loginMode))
  }

  @Builder
  private roleSelector() {
    Column({ space: 6 }) {
      Text(this.isLoginMode ? '选择登录身份' : '选择账户类型')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.MUTED)
        .width('100%')
      Row({ space: 10 }) {
        this.roleCard('用户点餐', $r('app.media.login_user'), $r('app.media.login_user_active'),
          UserRole.CUSTOMER, 'login-role-user')
        this.roleCard('商户管理', $r('app.media.login_store'), $r('app.media.login_store_active'),
          UserRole.MERCHANT, 'login-role-merchant')
      }
      .width('100%')
      Row({ space: 10 }) {
        this.roleCard('骑手配送', $r('app.media.login_rider'), $r('app.media.login_rider_active'),
          UserRole.RIDER, 'login-role-rider')
        if (this.isLoginMode) {
          this.roleCard('管理端', $r('app.media.login_shield'), $r('app.media.login_shield_active'),
            UserRole.ADMIN, 'login-role-admin')
        } else {
          Blank().layoutWeight(1)
        }
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  @Builder
  private roleCard(label: string, icon: Resource, activeIcon: Resource, role: UserRole, id: string) {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Row({ space: 8 }) {
          Image(this.selectedRole === role ? activeIcon : icon)
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .accessibilityLevel('no')
          Text(label)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedRole === role ? AppTheme.ACCENT : AppTheme.TEXT)
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12 })
        if (this.selectedRole === role) {
          Image($r('app.media.login_check'))
            .width(12)
            .height(12)
            .margin({ top: 6, right: 6 })
            .accessibilityLevel('no')
        }
      }
      .width('100%')
      .height('100%')
    }
    .layoutWeight(1)
    .height(44)
    .padding(0)
    .backgroundColor(this.selectedRole === role ? AppTheme.ACCENT_SOFT : AppTheme.CARD)
    .border({ width: this.selectedRole === role ? 1.5 : 1,
      color: this.selectedRole === role ? AppTheme.ACCENT : AppTheme.BORDER })
    .borderRadius(AppTheme.CONTROL_RADIUS)
    .animation({ duration: this.reduceMotion ? 0 : AppMotion.PRESS, curve: Curve.EaseOut })
    .id(id)
    .accessibilitySelected(this.selectedRole === role)
    .accessibilityText(label + (this.selectedRole === role ? '，已选中' : '，未选中'))
    .enabled(!this.submitting && !this.sendingCode)
    .onClick(() => { this.selectedRole = role; this.clearFeedback() })
  }

  @Builder
  private submitButton() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        if (this.submitting) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(AppTheme.PRIMARY_TEXT)
        }
        Text(this.submitting ? '提交中…' : (this.isLoginMode ? '登录' : '注册'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.PRIMARY_TEXT)
        if (!this.submitting) {
          Image($r('app.media.login_arrow'))
            .width(20)
            .height(20)
            .accessibilityLevel('no')
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(44)
    .backgroundColor(AppTheme.PRIMARY)
    .borderRadius(16)
    .id('login-submit')
    .enabled(!this.submitting && !this.sendingCode)
    .margin({ top: 0 })
    .onClick(() => this.submitForm())
  }

  private switchMode(loginMode: boolean): void {
    if (this.submitting || this.sendingCode || this.isLoginMode === loginMode) {
      return
    }
    this.isLoginMode = loginMode
    this.useEmailLogin = false
    this.emailCode = ''; this.password = ''; this.confirmPassword = ''; this.captchaId = ''; this.captchaCode = ''
    if (!this.isLoginMode) {
      this.selectedRole = UserRole.CUSTOMER
    }
    this.clearFeedback()
    logInfo('Auth', `切换${this.isLoginMode ? '登录' : '注册'}模式`)
  }

  private async submitForm(): Promise<void> {
    if (this.submitting || this.sendingCode) { return }
    this.clearFeedback()
    if (!/^1\d{10}$/.test(this.phone.trim())) {
      this.showError('请输入正确的 11 位手机号', 'login-phone'); return
    }
    const needsCode: boolean = !this.isLoginMode || this.useEmailLogin
    if (!this.isLoginMode && this.username.trim() === '') {
      this.showError('请输入账号名', 'login-username'); return
    }
    if (needsCode && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email.trim())) {
      this.showError('请输入正确的邮箱地址', 'login-email'); return
    }
    if (needsCode && !/^\d{6}$/.test(this.emailCode.trim())) {
      this.showError('请输入 6 位邮箱验证码', this.isLoginMode ? 'login-email-code' : 'register-email-code'); return
    }
    if ((!this.isLoginMode || !this.useEmailLogin) && this.password === '') {
      this.showError('请输入密码', 'login-password'); return
    }
    if (!this.isLoginMode && newPasswordError(this.password)) {
      this.showError(newPasswordError(this.password), 'login-password'); return
    }
    if (!this.isLoginMode && this.password !== this.confirmPassword) {
      this.showError('两次输入的密码不一致，请重新输入确认密码', 'login-confirm-password'); return
    }
    this.submitting = true
    try {
      if (this.isLoginMode) {
        const user: User | undefined = this.useEmailLogin
          ? await loginByEmailRemote(this.phone.trim(), this.email.trim(), this.emailCode.trim(), this.loginTypeName())
          : await loginRemote(this.phone.trim(), this.password, this.loginTypeName())
        if (!this.pageActive) { return }
        if (user === undefined) {
          this.showError(getLastRemoteErrorMessage() || (this.useEmailLogin ? '验证码不正确或已过期' : '账号或密码错误'))
          return
        }
        if (user.role !== this.selectedRole) {
          this.showError('登录身份与账号不匹配，请选择正确的身份')
          await logout()
          return
        }
        this.password = ''; this.emailCode = ''
        this.onLoginSuccess()
      } else {
        const newUser: User | undefined = await registerRemote(this.username.trim(), this.phone.trim(), this.email.trim(),
          this.emailCode.trim(), this.password, UserRole.CUSTOMER)
        if (!this.pageActive) { return }
        if (newUser === undefined) {
          this.showError(getLastRemoteErrorMessage() || '注册失败，请核对信息后重试')
          return
        }
        this.isLoginMode = true; this.useEmailLogin = false; this.selectedRole = UserRole.CUSTOMER
        this.phone = this.phone.trim()
        this.password = ''; this.confirmPassword = ''; this.emailCode = ''; this.captchaId = ''; this.captchaCode = ''
        this.tipMsg = '注册成功，已保留手机号，请重新输入密码登录。'
        setTimeout(() => {
          if (this.pageActive && this.isLoginMode && !this.useEmailLogin) {
            this.getUIContext().getFocusController().requestFocus('login-password')
          }
        }, 100)
      }
    } catch (_) {
      if (this.pageActive) { this.showError('操作未完成，请检查网络后重试') }
    } finally {
      this.submitting = false
    }
  }

  private async quickLogin(role: UserRole): Promise<void> {
    if (this.submitting) {
      promptAction.showToast({ message: '正在处理，请稍候', duration: 1200 })
      return
    }
    const account: QuickLoginAccount | undefined = getQuickLoginAccount(role, getApiBaseUrl())
    if (account === undefined) {
      this.errorMsg = '当前环境未配置该身份的快捷登录账号'
      promptAction.showToast({ message: this.errorMsg, duration: 2200 })
      return
    }
    this.submitting = true
    this.errorMsg = ''
    this.tipMsg = ''
    this.selectedRole = role
    try {
      const user = await loginRemote(account.phone, account.password, this.loginTypeName())
      if (user !== undefined && user.role === role) {
        this.phone = account.phone
        this.password = ''
        this.onLoginSuccess()
      } else {
        if (user !== undefined) {
          logout()
        }
        const remoteMessage: string = getLastRemoteErrorMessage()
        this.errorMsg = remoteMessage !== '' ? remoteMessage : role === UserRole.ADMIN
          ? '管理端快捷登录失败，请确认账号可用'
          : role === UserRole.MERCHANT ? '商户快捷登录失败，请确认账号可用'
          : role === UserRole.RIDER ? '骑手快捷登录失败，请确认账号可用' : '用户快捷登录失败，请确认账号可用'
      }
    } catch (_) {
      this.errorMsg = '快捷登录失败，请稍后重试'
    } finally {
      this.submitting = false
    }
  }

  private loginTypeName(): string {
    return this.selectedRole === UserRole.ADMIN
      ? 'ADMIN'
      : this.selectedRole === UserRole.MERCHANT ? 'MERCHANT'
      : this.selectedRole === UserRole.RIDER ? 'RIDER' : 'USER'
  }
}

/** 调试包的快捷登录选择弹窗，账号由本机私有构建配置提供。 */
@CustomDialog
export struct QuickLoginDialog {
  controller?: CustomDialogController
  onSelectLogin: (role: UserRole) => void = () => {}

  build() {
    Column() {
      Row() {
        Text('选择登录身份')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
        Blank()
        Button('取消', { type: ButtonType.Normal })
          .fontSize(14)
          .fontColor(AppTheme.MUTED)
          .backgroundColor(Color.Transparent)
          .height(44)
          .padding({ left: 12, right: 12 })
          .borderRadius(12)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close()
            }
          })
      }
      .width('100%')
      .padding({ left: 24, right: 12, top: 12, bottom: 8 })

      Divider().color(AppTheme.BORDER)
      Column({ space: 10 }) {
        this.quickLoginButton('用户点餐', $r('app.media.login_user'),
          UserRole.CUSTOMER, 'quick-login-user')
        this.quickLoginButton('商户管理', $r('app.media.login_store'),
          UserRole.MERCHANT, 'quick-login-merchant')
        this.quickLoginButton('管理端', $r('app.media.login_shield'),
          UserRole.ADMIN, 'quick-login-admin')
        this.quickLoginButton('骑手配送', $r('app.media.login_rider'),
          UserRole.RIDER, 'quick-login-rider')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 18, bottom: 28 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 508 })
    .backgroundColor(AppTheme.PAGE)
    .borderRadius({ topLeft: 24, topRight: 24 })
  }

  @Builder
  quickLoginButton(label: string, icon: Resource, role: UserRole, id: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Image(icon)
          .width(24)
          .height(24)
          .accessibilityLevel('no')
        Text(label)
          .fontSize(16)
          .fontColor(AppTheme.TEXT)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(44)
    .backgroundColor(AppTheme.INPUT)
    .border({ width: 1, color: AppTheme.BORDER })
    .borderRadius(AppTheme.CONTROL_RADIUS)
    .id(id)
    .accessibilityText(label)
    .onClick(() => {
      this.onSelectLogin(role)
      if (this.controller !== undefined) {
        this.controller.close()
      }
    })
  }
}
