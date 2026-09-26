/**
 * 登录/注册页面：四种身份登录，用户、商户、骑手可注册。
 */
import { UserRole } from '../model/Models'
import { loginRemote, registerRemote, logout, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { logInfo, logWarn } from '../service/AppLogger'
import { APP_CONFIG } from '../common/Constants'
import { LoginTheme } from '../common/theme/LoginTheme'
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction } from '../common/UiNavigation'

@Component
export struct LoginPage {
  @StorageLink('appReduceMotion') reduceMotion: boolean = false
  @State isLoginMode: boolean = true
  @State selectedRole: UserRole = UserRole.CUSTOMER
  @State phone: string = ''
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
      onSelectLogin: (phone: string, role: UserRole): void => {
        this.quickLogin(phone, role)
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
            Text(this.isLoginMode ? '欢迎回来' : '从一顿美味开始')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(LoginTheme.TEXT)
              .width('100%')
              .margin({ top: 16, bottom: 8 })
            Text(this.isLoginMode ? '选好身份，开启今天的美味。' : '创建账号，加入简单外卖。')
              .fontSize(14)
              .fontColor(LoginTheme.MUTED)
              .width('100%')
              .margin({ bottom: 16 })

            this.modeSelector()
            this.roleSelector()

            if (!this.isLoginMode) {
              this.formField('用户名', '请输入用户名', this.username, $r('app.media.login_user'),
                InputType.Normal, 'login-username', (value: string) => { this.username = value })
            }
            this.formField('手机号', '请输入手机号', this.phone, $r('app.media.login_phone'),
              InputType.PhoneNumber, 'login-phone', (value: string) => { this.phone = value })
            this.formField('密码', '请输入密码', this.password, $r('app.media.login_lock'),
              InputType.Password, 'login-password', (value: string) => { this.password = value })

            if (this.tipMsg) {
              this.formMessage(this.tipMsg, LoginTheme.SUCCESS, LoginTheme.SUCCESS_BG)
            }
            if (this.errorMsg) {
              this.formMessage(this.errorMsg, LoginTheme.ERROR, LoginTheme.ERROR_BG)
            }
            this.submitButton()

            Text(this.isLoginMode ? '使用所选身份对应的账号登录' : '注册成功后，请使用新账号登录')
              .fontSize(12)
              .fontColor(LoginTheme.MUTED)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: 12 })
          }
          .width('100%')
          .constraintSize({ maxWidth: LoginTheme.FORM_MAX_WIDTH })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)

      // 固定底部入口，窄屏与长表单下也可连续点击三次打开快捷登录。
      if (this.isLoginMode) {
        Button('v' + APP_CONFIG.VERSION, { type: ButtonType.Normal })
          .fontSize(12)
          .fontColor(LoginTheme.MUTED)
          .backgroundColor(Color.Transparent)
          .height(44)
          .padding({ left: 24, right: 24 })
          .borderRadius(12)
          .id('version-text')
          .margin({ top: 4, bottom: 8 })
          .onClick(() => {
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
    .backgroundColor(LoginTheme.PAGE)
  }

  @Builder
  private brandHeader() {
    Row({ space: 12 }) {
      Image($r('app.media.login_brand'))
        .width(52)
        .height(52)
        .objectFit(ImageFit.Contain)
        .accessibilityLevel('no')
      Column({ space: 5 }) {
        Text('简单外卖')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(LoginTheme.TEXT)
        Text('美味送到家')
          .fontSize(12)
          .fontColor(LoginTheme.MUTED)
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
    .backgroundColor(LoginTheme.INPUT)
    .borderRadius(LoginTheme.CONTROL_RADIUS)
    .margin({ bottom: 16 })
  }

  @Builder
  private modeButton(label: string, loginMode: boolean, id: string) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(44)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isLoginMode === loginMode ? LoginTheme.TEXT : LoginTheme.MUTED)
      .backgroundColor(this.isLoginMode === loginMode ? LoginTheme.CARD : Color.Transparent)
      .borderRadius(10)
      .animation({ duration: this.reduceMotion ? 0 : AppMotion.PRESS, curve: Curve.EaseOut })
      .id(id)
      .accessibilitySelected(this.isLoginMode === loginMode)
      .accessibilityText(label + (this.isLoginMode === loginMode ? '，已选中' : '，未选中'))
      .onClick(() => this.switchMode(loginMode))
  }

  @Builder
  private roleSelector() {
    Column({ space: 10 }) {
      Text(this.isLoginMode ? '选择登录身份' : '选择账户类型')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(LoginTheme.MUTED)
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
    .margin({ bottom: 16 })
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
            .fontColor(this.selectedRole === role ? LoginTheme.ACCENT : LoginTheme.TEXT)
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
    .height(56)
    .padding(0)
    .backgroundColor(this.selectedRole === role ? LoginTheme.ACCENT_SOFT : LoginTheme.CARD)
    .border({ width: this.selectedRole === role ? 1.5 : 1,
      color: this.selectedRole === role ? LoginTheme.ACCENT : LoginTheme.BORDER })
    .borderRadius(LoginTheme.CONTROL_RADIUS)
    .animation({ duration: this.reduceMotion ? 0 : AppMotion.PRESS, curve: Curve.EaseOut })
    .id(id)
    .accessibilitySelected(this.selectedRole === role)
    .accessibilityText(label + (this.selectedRole === role ? '，已选中' : '，未选中'))
    .onClick(() => { this.selectedRole = role })
  }

  @Builder
  private formField(label: string, placeholder: string, value: string, icon: Resource,
    inputType: InputType, id: string, onValueChange: (value: string) => void) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(LoginTheme.TEXT)
        .width('100%')
      Row({ space: 10 }) {
        Image(icon)
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .accessibilityLevel('no')
        TextInput({ placeholder: placeholder, text: value })
          .fontSize(16)
          .fontColor(LoginTheme.TEXT)
          .placeholderColor(LoginTheme.MUTED)
          .caretColor(LoginTheme.ACCENT)
          .layoutWeight(1)
          .height(LoginTheme.CONTROL_HEIGHT)
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
      .height(LoginTheme.CONTROL_HEIGHT)
      .padding({ left: 14, right: 14 })
      .backgroundColor(LoginTheme.INPUT)
      .border({ width: this.focusedField === id ? 1.5 : 1,
        color: this.focusedField === id ? LoginTheme.ACCENT : LoginTheme.BORDER })
      .borderRadius(LoginTheme.CONTROL_RADIUS)
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  private formMessage(message: string, textColor: Resource, background: Resource) {
    Text(message)
      .fontSize(13)
      .fontColor(textColor)
      .width('100%')
      .padding(12)
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
            .color(LoginTheme.PRIMARY_TEXT)
        }
        Text(this.submitting ? '提交中…' : (this.isLoginMode ? '登录' : '注册'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(LoginTheme.PRIMARY_TEXT)
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
    .height(LoginTheme.CONTROL_HEIGHT)
    .backgroundColor(LoginTheme.PRIMARY)
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
    if (!this.isLoginMode && this.selectedRole === UserRole.ADMIN) {
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
    const roleName: string = this.selectedRole === UserRole.ADMIN
      ? '管理端'
      : this.selectedRole === UserRole.MERCHANT ? '商户'
      : this.selectedRole === UserRole.RIDER ? '骑手' : '用户'
    logInfo('Auth', `用户点击${this.isLoginMode ? '登录' : '注册'} phone=${this.phone} role=${roleName}`)

    if (this.isLoginMode) {
      const user = await loginRemote(this.phone, this.password, this.loginTypeName())
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
        this.errorMsg = remoteMessage === '' ? '手机号或密码错误' : remoteMessage
        this.submitting = false
      }
    } else {
      const newUser = await registerRemote(this.username, this.phone, this.password, this.selectedRole)
      if (newUser !== undefined) {
        // 注册成功不自动登录：切回登录态并清空密码，由用户自己再输入一遍完成登录。
        // 手机号保留便于对照，selectedRole 保持注册时选择的角色，登录才能带上正确的 loginType。
        this.isLoginMode = true
        this.password = ''
        this.username = ''
        this.tipMsg = '注册成功，请使用该密码登录'
        promptAction.showToast({ message: '注册成功，请登录', duration: 2000 })
        logInfo('Auth', `注册成功，转入登录态等待手动登录 userId=${newUser.id} role=${newUser.role}`)
        this.submitting = false
        return
      }
      const remoteMessage: string = getLastRemoteErrorMessage()
      this.errorMsg = remoteMessage === '' ? '该手机号已注册' : remoteMessage
      logWarn('Auth', `注册失败：手机号已存在 phone=${this.phone}`)
      this.submitting = false
    }
  }

  private async quickLogin(phone: string, role: UserRole): Promise<void> {
    if (this.submitting) {
      promptAction.showToast({ message: '正在处理，请稍候', duration: 1200 })
      return
    }
    this.submitting = true
    this.errorMsg = ''
    this.selectedRole = role
    const user = await loginRemote(phone, '123456', this.loginTypeName())
    if (user !== undefined && user.role === role) {
      this.phone = phone
      this.password = '123456'
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
    this.submitting = false
  }

  private loginTypeName(): string {
    return this.selectedRole === UserRole.ADMIN
      ? 'ADMIN'
      : this.selectedRole === UserRole.MERCHANT ? 'MERCHANT'
      : this.selectedRole === UserRole.RIDER ? 'RIDER' : 'USER'
  }
}

/** 快捷登录选择弹窗，沿用版本号三击入口与四个测试账号。 */
@CustomDialog
export struct QuickLoginDialog {
  controller?: CustomDialogController
  onSelectLogin: (phone: string, role: UserRole) => void = () => {}

  build() {
    Column() {
      Row() {
        Text('选择登录身份')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(LoginTheme.TEXT)
        Blank()
        Button('取消', { type: ButtonType.Normal })
          .fontSize(14)
          .fontColor(LoginTheme.MUTED)
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

      Divider().color(LoginTheme.BORDER)
      Column({ space: 10 }) {
        this.quickLoginButton('用户点餐', $r('app.media.login_user'),
          '13800138000', UserRole.CUSTOMER, 'quick-login-user')
        this.quickLoginButton('商户管理', $r('app.media.login_store'),
          '13600136000', UserRole.MERCHANT, 'quick-login-merchant')
        this.quickLoginButton('管理端', $r('app.media.login_shield'),
          '13100131000', UserRole.ADMIN, 'quick-login-admin')
        this.quickLoginButton('骑手配送', $r('app.media.login_rider'),
          '13300133000', UserRole.RIDER, 'quick-login-rider')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 18, bottom: 28 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 508 })
    .backgroundColor(LoginTheme.PAGE)
    .borderRadius({ topLeft: 24, topRight: 24 })
  }

  @Builder
  quickLoginButton(label: string, icon: Resource, phone: string, role: UserRole, id: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Image(icon)
          .width(24)
          .height(24)
          .accessibilityLevel('no')
        Text(label)
          .fontSize(16)
          .fontColor(LoginTheme.TEXT)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(LoginTheme.CONTROL_HEIGHT)
    .backgroundColor(LoginTheme.INPUT)
    .border({ width: 1, color: LoginTheme.BORDER })
    .borderRadius(LoginTheme.CONTROL_RADIUS)
    .id(id)
    .accessibilityText(label)
    .onClick(() => {
      this.onSelectLogin(phone, role)
      if (this.controller !== undefined) {
        this.controller.close()
      }
    })
  }
}
