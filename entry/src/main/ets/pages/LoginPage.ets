/**
 * 登录/注册页面：四种身份登录，用户、商户、骑手可注册。
 */
import { UserRole } from '../model/Models'
import { loginRemote, registerRemote, logout, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { logInfo, logWarn } from '../service/AppLogger'
import { APP_CONFIG } from '../common/Constants'
import BuildProfile from 'BuildProfile'
import { getQuickLoginAccount, QuickLoginAccount } from '../common/QuickLoginConfig'
import { getApiBaseUrl } from '../service/HttpClient'
import { AppTheme, AppInputStyle, AppButtonStyle } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'
import { requestEmailCodeApi, EmailCodeResult } from '../service/ApiService'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

@Component
export struct LoginPage {
  @StorageLink('appReduceMotion') reduceMotion: boolean = false
  @State isLoginMode: boolean = true
  @State selectedRole: UserRole = UserRole.CUSTOMER
  @State phone: string = ''
  @State email: string = ''
  @State emailCode: string = ''
  @State sendingCode: boolean = false
  @State cooldownSeconds: number = 0
  private cooldownTimer: number = -1
  private pageActive: boolean = true
  @State password: string = ''
  @State username: string = ''
  @State errorMsg: string = ''
  @State tipMsg: string = ''
  @State submitting: boolean = false
  @State versionClickCount: number = 0
  @State focusedField: string = ''
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
      Scroll() {
        Column() {
          Column() {
            this.brandHeader()
            Text(this.isLoginMode ? '登录' : '注册账号')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT)
              .width('100%')
              .margin({ top: 10, bottom: 4 })

            this.modeSelector()
            if (this.isLoginMode) { this.roleSelector() }

            if (!this.isLoginMode) {
              this.formField('账号名', '请输入账号名，例如 takeout_user', this.username, $r('app.media.login_user'),
                InputType.Normal, 'login-username', (value: string) => { this.username = value })
              this.formField('邮箱', '请输入用于找回密码的邮箱', this.email, $r('app.media.login_user'),
                InputType.Email, 'login-email', (value: string) => { this.email = value; this.emailCode = '' })
            }
            this.formField('手机号', '例如：13800138000', this.phone, $r('app.media.login_phone'),
              InputType.PhoneNumber, 'login-phone', (value: string) => { this.phone = value; this.emailCode = '' })
            if (!this.isLoginMode) {
              this.registrationCodeField()
            }
            this.formField('密码', '请输入密码', this.password, $r('app.media.login_lock'),
              InputType.Password, 'login-password', (value: string) => { this.password = value })

            if (this.tipMsg) {
              this.formMessage(this.tipMsg, AppTheme.SUCCESS, AppTheme.SUCCESS_BG)
            }
            if (this.errorMsg) {
              this.formMessage(this.errorMsg, AppTheme.ERROR, AppTheme.ERROR_BG)
            }
            if (this.isLoginMode) { this.submitButton() }

            if (this.isLoginMode) {
              Button('忘记登录密码？')
                .fontSize(13).fontColor(AppTheme.ACCENT).backgroundColor(Color.Transparent)
                .height(36).width('100%').id('login-forgot-password')
                .onClick(() => {
                  AppStorage.setOrCreate<string>('passwordResetMode', 'login')
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

      if (!this.isLoginMode) {
        Row() {
          Column() { this.submitButton() }
            .width('100%').constraintSize({ maxWidth: AppTheme.FORM_MAX_WIDTH })
        }.width('100%').justifyContent(FlexAlign.Center)
          .padding({ left: 24, right: 24, top: 8, bottom: 16 })
      }

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

  aboutToAppear(): void { this.pageActive = true }

  aboutToDisappear(): void {
    this.pageActive = false
    if (this.cooldownTimer !== -1) { clearInterval(this.cooldownTimer); this.cooldownTimer = -1 }
    this.emailCode = ''
  }

  @Builder
  private registrationCodeField() {
    Column({ space: 4 }) {
      Text('邮箱验证码').fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.emailCode, placeholder: '请输入 6 位验证码' })
          .attributeModifier(new AppInputStyle()).type(InputType.Number).maxLength(6)
          .height(44).layoutWeight(1).id('register-email-code')
          .onChange((value: string) => { this.emailCode = value })
        Button(this.sendingCode ? '发送中…' : this.cooldownSeconds > 0 ? this.cooldownSeconds + '秒后重发' : '获取验证码')
          .attributeModifier(new AppButtonStyle()).height(44).width(120).id('register-send-code')
          .enabled(!this.sendingCode && this.cooldownSeconds === 0 && !this.submitting)
          .onClick(() => { this.sendRegistrationCode() })
      }.width('100%')
      Text('验证码 15 分钟内有效；完成邮箱验证后才能注册。')
        .fontSize(12).fontColor(AppTheme.MUTED).width('100%')
    }.width('100%').margin({ bottom: 8 })
  }

  private async sendRegistrationCode(): Promise<void> {
    if (this.sendingCode || this.cooldownSeconds > 0 || this.submitting) { return }
    this.errorMsg = ''
    this.tipMsg = ''
    if (this.username.trim() === '') { this.errorMsg = '请输入账号名'; return }
    if (!/^1\d{10}$/.test(this.phone.trim())) { this.errorMsg = '请输入正确的 11 位手机号'; return }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email.trim())) { this.errorMsg = '请输入正确的邮箱地址'; return }
    this.sendingCode = true
    const result: EmailCodeResult = await requestEmailCodeApi(this.phone.trim(), this.email.trim(), 'register', this.username.trim())
    this.sendingCode = false
    if (!this.pageActive) { return }
    if (!result.success) {
      this.errorMsg = result.message || '验证码发送失败，请稍后重试'
      promptAction.showToast({ message: this.errorMsg, duration: 2200 })
      return
    }
    this.tipMsg = result.mock === true && result.code !== undefined
      ? `开发模式验证码：${result.code}` : '注册验证码已发送，请查看邮箱'
    promptAction.showToast({ message: this.tipMsg, duration: 1800 })
    this.cooldownSeconds = 60
    this.cooldownTimer = setInterval(() => {
      this.cooldownSeconds = Math.max(0, this.cooldownSeconds - 1)
      if (this.cooldownSeconds === 0) { clearInterval(this.cooldownTimer); this.cooldownTimer = -1 }
    }, 1000)
  }

  @Builder
  private brandHeader() {
    Row({ space: 12 }) {
      Image($r('app.media.login_brand'))
        .width(44)
        .height(44)
        .objectFit(ImageFit.Contain)
        .accessibilityLevel('no')
      Column({ space: 5 }) {
        Text('简单外卖')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
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
    .onClick(() => { this.selectedRole = role })
  }

  @Builder
  private formField(label: string, placeholder: string, value: string, icon: Resource,
    inputType: InputType, id: string, onValueChange: (value: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT)
        .width('100%')
      Row({ space: 10 }) {
        Image(icon)
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .accessibilityLevel('no')
        TextInput({ placeholder: placeholder, text: value })
          .fontSize(16)
          .fontColor(AppTheme.TEXT)
          .placeholderColor(AppTheme.MUTED)
          .caretColor(AppTheme.ACCENT)
          .layoutWeight(1)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .type(inputType)
          .id(id)
          .accessibilityText(label)
          .onChange(onValueChange)
          .onFocus(() => { this.focusedField = id })
          .onBlur(() => { this.focusedField = '' })
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .backgroundColor(AppTheme.INPUT)
      .border({ width: this.focusedField === id ? 1.5 : 1,
        color: this.focusedField === id ? AppTheme.ACCENT : AppTheme.BORDER })
      .borderRadius(AppTheme.CONTROL_RADIUS)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private formMessage(message: string, textColor: Resource, background: Resource) {
    Text(message)
      .fontSize(13)
      .fontColor(textColor)
      .width('100%')
      .padding(8)
      .backgroundColor(background)
      .borderRadius(10)
      .margin({ bottom: 10 })
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
    .margin({ top: 6 })
    .onClick(() => this.submitForm())
  }

  private switchMode(loginMode: boolean): void {
    if (this.isLoginMode === loginMode) {
      return
    }
    this.isLoginMode = loginMode
    this.emailCode = ''
    if (!this.isLoginMode) {
      this.selectedRole = UserRole.CUSTOMER
    }
    this.errorMsg = ''
    this.tipMsg = ''
    logInfo('Auth', `切换${this.isLoginMode ? '登录' : '注册'}模式`)
  }

  private async submitForm(): Promise<void> {
    if (this.submitting) {
      promptAction.showToast({ message: '正在处理，请稍候', duration: 1200 })
      return
    }
    this.submitting = true
    this.errorMsg = ''
    this.tipMsg = ''
    if (this.phone.trim() === '' || this.password === '') {
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
    if (!this.isLoginMode && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email.trim())) {
      logWarn('Auth', '注册提交失败：邮箱格式不正确')
      this.errorMsg = '请输入正确的邮箱地址'
      this.submitting = false
      return
    }
    if (!this.isLoginMode && !/^\d{6}$/.test(this.emailCode.trim())) {
      this.errorMsg = '请输入 6 位邮箱验证码'
      this.submitting = false
      return
    }
    const roleName: string = this.selectedRole === UserRole.ADMIN
      ? '管理端'
      : this.selectedRole === UserRole.MERCHANT ? '商户'
      : this.selectedRole === UserRole.RIDER ? '骑手' : '用户'
    logInfo('Auth', `用户点击${this.isLoginMode ? '登录' : '注册'} phone=${this.phone} role=${roleName}`)

    if (this.isLoginMode) {
      const user = await loginRemote(this.phone.trim(), this.password, this.loginTypeName())
      if (user !== undefined) {
        if (user.role !== this.selectedRole) {
          this.errorMsg = this.selectedRole === UserRole.ADMIN
            ? '该账号不是管理端账号'
            : this.selectedRole === UserRole.MERCHANT ? '该账号不是商户账号'
            : this.selectedRole === UserRole.RIDER ? '该账号不是骑手账号' : '该账号不是用户账号'
          logout()
          logWarn('Auth', `登录角色不匹配 phone=${this.phone} 期望角色=${this.selectedRole}`)
          this.submitting = false
          return
        }
        this.onLoginSuccess()
      } else {
        const remoteMessage: string = getLastRemoteErrorMessage()
        this.errorMsg = remoteMessage === '' ? '账号或密码错误' : remoteMessage
        this.submitting = false
      }
    } else {
      const newUser = await registerRemote(this.username.trim(), this.phone.trim(), this.email.trim(), this.emailCode.trim(), this.password, this.selectedRole)
      if (newUser !== undefined) {
        // 注册成功不自动登录：切回登录态并清空密码，由用户自己再输入一遍完成登录。
        // 保留手机号和所选角色，注册后使用手机号登录。
        this.isLoginMode = true
        this.password = ''
        this.email = ''
        this.emailCode = ''
        this.tipMsg = '注册成功，请使用该密码登录'
        promptAction.showToast({ message: '注册成功，请登录', duration: 2000 })
        logInfo('Auth', `注册成功，转入登录态等待手动登录 userId=${newUser.id} role=${newUser.role}`)
        this.submitting = false
        return
      }
      const remoteMessage: string = getLastRemoteErrorMessage()
      this.errorMsg = remoteMessage === '' ? '该账号已注册' : remoteMessage
      logWarn('Auth', `注册失败：账号已存在 phone=${this.phone}`)
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
