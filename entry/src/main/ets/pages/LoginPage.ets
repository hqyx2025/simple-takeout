/**
 * 登录/注册页面
 * 支持商户账户和普通用户账户
 */
import { UserRole } from '../model/Models'
import { loginRemote, registerRemote, logout, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { logInfo, logWarn } from '../service/AppLogger'
import { APP_CONFIG, COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction } from '../common/UiNavigation'

@Component
export struct LoginPage {
  @State isLoginMode: boolean = true  // true=登录 false=注册
  @State selectedRole: UserRole = UserRole.CUSTOMER
  @State phone: string = ''
  @State password: string = ''
  @State username: string = ''
  @State errorMsg: string = ''
  @State tipMsg: string = ''
  @State submitting: boolean = false
  @State versionClickCount: number = 0
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
    Scroll() {
    Column() {
      // 顶部Logo区域
      Column({ space: SPACING.SM }) {
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
            .layoutWeight(1)
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
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(this.selectedRole === UserRole.MERCHANT ? Color.White : COLORS.PRIMARY)
            .backgroundColor(this.selectedRole === UserRole.MERCHANT ? COLORS.PRIMARY : Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .borderWidth(this.selectedRole === UserRole.MERCHANT ? 0 : 1)
            .borderColor(COLORS.PRIMARY)
            .onClick(() => { this.selectedRole = UserRole.MERCHANT })

          Button('我是骑手')
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(this.selectedRole === UserRole.RIDER ? Color.White : COLORS.PRIMARY)
            .backgroundColor(this.selectedRole === UserRole.RIDER ? COLORS.PRIMARY : Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .borderWidth(this.selectedRole === UserRole.RIDER ? 0 : 1)
            .borderColor(COLORS.PRIMARY)
            .onClick(() => { this.selectedRole = UserRole.RIDER })
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
        Column({ space: SPACING.SM }) {
          Row({ space: SPACING.SM }) {
            Text('👤 用户点餐')
              .fontSize(FONT_SIZE.SM)
              .fontColor(this.selectedRole === UserRole.CUSTOMER ? COLORS.PRIMARY : COLORS.TEXT_HINT)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(this.selectedRole === UserRole.CUSTOMER ? COLORS.TAG_BG : COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.selectedRole = UserRole.CUSTOMER })
            Text('🏪 商户管理')
              .fontSize(FONT_SIZE.SM)
              .fontColor(this.selectedRole === UserRole.MERCHANT ? COLORS.PRIMARY : COLORS.TEXT_HINT)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(this.selectedRole === UserRole.MERCHANT ? COLORS.TAG_BG : COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.selectedRole = UserRole.MERCHANT })
          }
          .width('100%')
          Row({ space: SPACING.SM }) {
            Text('🛠 管理端')
              .fontSize(FONT_SIZE.SM)
              .fontColor(this.selectedRole === UserRole.ADMIN ? COLORS.PRIMARY : COLORS.TEXT_HINT)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(this.selectedRole === UserRole.ADMIN ? COLORS.TAG_BG : COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.selectedRole = UserRole.ADMIN })
            Text('🛵 骑手配送')
              .fontSize(FONT_SIZE.SM)
              .fontColor(this.selectedRole === UserRole.RIDER ? COLORS.PRIMARY : COLORS.TEXT_HINT)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(this.selectedRole === UserRole.RIDER ? COLORS.TAG_BG : COLORS.BG_PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.selectedRole = UserRole.RIDER })
          }
          .width('100%')
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

      // 成功提示（注册成功后需自行登录）
      if (this.tipMsg) {
        Text(this.tipMsg)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.SUCCESS)
          .width('100%')
          .margin({ bottom: SPACING.SM })
      }

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
        .margin({ top: SPACING.SM })
        .onClick(async () => {
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
        })

      // 切换登录/注册
      Row({ space: SPACING.XS }) {
        Text(this.isLoginMode ? '还没有账号？' : '已有账号？')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
        Text(this.isLoginMode ? '立即注册' : '去登录')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .fontWeight(FontWeight.Bold)
          .onClick(() => {
            this.isLoginMode = !this.isLoginMode
            if (!this.isLoginMode && this.selectedRole === UserRole.ADMIN) {
              this.selectedRole = UserRole.CUSTOMER
            }
            this.errorMsg = ''
            this.tipMsg = ''
            logInfo('Auth', `切换${this.isLoginMode ? '登录' : '注册'}模式`)
          })
      }
      .margin({ top: SPACING.LG })

      // 版本号（点击3次触发快捷登录选择弹窗）
      if (this.isLoginMode) {
        Column() {
          Text('v' + APP_CONFIG.VERSION)
            .fontSize(FONT_SIZE.XS)
            .fontColor(COLORS.TEXT_HINT)
            .id('version-text')
            .onClick(() => {
              this.versionClickCount = this.versionClickCount + 1
              if (this.versionClickCount >= 3) {
                this.versionClickCount = 0
                this.quickLoginDialog.open()
              }
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: SPACING.LG })
      }
    }
    .width('100%')
    .padding({ left: SPACING.XL, right: SPACING.XL })
    .backgroundColor(COLORS.BG_WHITE)
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_WHITE)
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

/**
 * 快捷登录选择弹窗（点击版本号3次后触发）
 */
@CustomDialog
export struct QuickLoginDialog {
  controller?: CustomDialogController
  onSelectLogin: (phone: string, role: UserRole) => void = () => {}

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('选择登录身份')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Blank()
        Text('取消')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close()
            }
          })
      }
      .width('100%')
      .padding({ left: SPACING.XL, right: SPACING.XL, top: SPACING.LG, bottom: SPACING.MD })

      // 分隔线
      Divider().color(COLORS.DIVIDER)

      // 快捷登录按钮列表
      Column({ space: SPACING.SM }) {
        this.quickLoginButton('👤 用户点餐', '13800138000', UserRole.CUSTOMER, 'quick-login-user')
        this.quickLoginButton('🏪 商户管理', '13600136000', UserRole.MERCHANT, 'quick-login-merchant')
        this.quickLoginButton('🛠 管理端', '13100131000', UserRole.ADMIN, 'quick-login-admin')
        this.quickLoginButton('🛵 骑手配送', '13300133000', UserRole.RIDER, 'quick-login-rider')
      }
      .width('100%')
      .padding({ left: SPACING.XL, right: SPACING.XL, top: SPACING.MD, bottom: SPACING.XL })
    }
    .width('100%')
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius({ topLeft: BORDER_RADIUS.XL, topRight: BORDER_RADIUS.XL })
  }

  @Builder
  quickLoginButton(label: string, phone: string, role: UserRole, id: string) {
    Button(label)
      .width('100%')
      .height(48)
      .fontSize(FONT_SIZE.LG)
      .fontColor(COLORS.PRIMARY)
      .backgroundColor(COLORS.WARM_BG)
      .borderRadius(BORDER_RADIUS.ROUND)
      .type(ButtonType.Capsule)
      .id(id)
      .onClick(() => {
        this.onSelectLogin(phone, role)
        if (this.controller !== undefined) {
          this.controller.close()
        }
      })
  }
}
