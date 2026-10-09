import { AppButtonStyle, AppCardStyle, AppInputStyle, AppTheme } from '../common/theme/AppTheme'
import { COLORS, FONT_SIZE, SPACING } from '../common/Constants'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { changePasswordRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { setPaymentPasswordApi, PaymentPasswordResult } from '../service/ApiService'
import { getAuthToken } from '../service/HttpClient'
import { User } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { KeyboardAvoidMode } from '@kit.ArkUI'

@Entry
@Component
export struct AccountSecurityPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('authToken') authToken: string = ''
  @StorageLink('user') user: User = {
    id: 0, username: '', avatar: '', phone: '', password: '', role: 0,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State oldPassword: string = ''
  @State newPassword: string = ''
  @State confirmPassword: string = ''
  @State loginPassword: string = ''
  @State paymentPassword: string = ''
  @State paymentConfirm: string = ''
  @State savingPassword: boolean = false
  @State savingPayment: boolean = false
  private active: boolean = false
  private sessionToken: string = ''
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET
  private keyboardModeChanged: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.sessionToken = getAuthToken()
    if (!this.hasSession()) { router.replaceUrl({ url: 'pages/Index' }) }
  }

  onPageShow(): void {
    if (this.keyboardModeChanged) { return }
    try {
      this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode()
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
      this.keyboardModeChanged = true
    } catch (_) {}
  }

  aboutToDisappear(): void {
    this.active = false
    this.clearFields()
    this.restoreKeyboardAvoidMode()
  }

  private hasSession(): boolean {
    return this.loggedIn && this.sessionToken !== '' && this.sessionToken === getAuthToken()
      && this.user.id > 0
  }

  private clearFields(): void {
    this.oldPassword = ''
    this.newPassword = ''
    this.confirmPassword = ''
    this.loginPassword = ''
    this.paymentPassword = ''
    this.paymentConfirm = ''
  }

  private restoreKeyboardAvoidMode(): void {
    if (!this.keyboardModeChanged) { return }
    try {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode)
      this.keyboardModeChanged = false
    } catch (_) {}
  }

  private async saveLoginPassword(): Promise<void> {
    if (this.savingPassword || !this.hasSession()) { return }
    if (this.oldPassword === '' || this.newPassword === '' || this.confirmPassword === '') {
      promptAction.showToast({ message: '请填写登录密码的完整信息', duration: 1800 })
      return
    }
    if (this.newPassword.length < 6) {
      promptAction.showToast({ message: '新密码长度至少 6 位', duration: 1800 })
      return
    }
    if (this.newPassword !== this.confirmPassword) {
      promptAction.showToast({ message: '两次输入的新密码不一致', duration: 1800 })
      return
    }
    if (this.oldPassword === this.newPassword) {
      promptAction.showToast({ message: '新密码不能与原密码相同', duration: 1800 })
      return
    }
    const token: string = this.sessionToken
    this.savingPassword = true
    const ok: boolean = await changePasswordRemote(this.oldPassword, this.newPassword)
    this.savingPassword = false
    this.clearFields()
    if (!this.active || token !== getAuthToken()) { return }
    if (!ok) {
      const reason: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: reason || '修改登录密码失败，请重试', duration: 2200 })
      return
    }
    promptAction.showToast({ message: '登录密码已修改，请重新登录', duration: 2200 })
    logout()
    router.replaceUrl({ url: 'pages/Index' })
  }

  private async savePaymentPassword(): Promise<void> {
    if (this.savingPayment || !this.hasSession()) { return }
    if (this.loginPassword === '' || !/^[0-9]{6}$/.test(this.paymentPassword)) {
      promptAction.showToast({ message: '请输入登录密码和 6 位数字支付密码', duration: 1800 })
      return
    }
    if (this.paymentPassword !== this.paymentConfirm) {
      promptAction.showToast({ message: '两次输入的支付密码不一致', duration: 1800 })
      return
    }
    const token: string = this.sessionToken
    const userId: number = this.user.id
    this.savingPayment = true
    const result: PaymentPasswordResult = await setPaymentPasswordApi(this.loginPassword, this.paymentPassword)
    this.savingPayment = false
    this.loginPassword = ''
    this.paymentPassword = ''
    this.paymentConfirm = ''
    if (!this.active || token !== getAuthToken() || userId !== this.user.id) { return }
    promptAction.showToast({ message: result.success ? '支付密码已保存' : (result.message || '支付密码保存失败'), duration: 2000 })
  }

  build() {
    Column() {
      PageHeader({ title: '账号安全', showBack: true, backId: 'account-security-back', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.LG }) {
          Column({ space: SPACING.MD }) {
            Text('修改登录密码').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT).width('100%')
            Text('修改成功后当前登录会失效，需要重新登录。').fontSize(FONT_SIZE.SM)
              .fontColor(AppTheme.MUTED).width('100%')
            TextInput({ text: this.oldPassword, placeholder: '请输入当前登录密码' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).width('100%')
              .id('account-old-password').onChange((value: string) => { this.oldPassword = value })
            TextInput({ text: this.newPassword, placeholder: '请输入新密码，至少 6 位' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).width('100%')
              .id('account-new-password').onChange((value: string) => { this.newPassword = value })
            TextInput({ text: this.confirmPassword, placeholder: '请再次输入新密码' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).width('100%')
              .id('account-confirm-password').onChange((value: string) => { this.confirmPassword = value })
            Button(this.savingPassword ? '保存中…' : '保存登录密码')
              .attributeModifier(new AppButtonStyle()).height(AppTheme.CONTROL_HEIGHT).width('100%')
              .enabled(!this.savingPassword && !this.savingPayment).id('account-save-password')
              .onClick(() => { this.saveLoginPassword() })
            Button('忘记登录密码')
              .fontSize(FONT_SIZE.SM).fontColor(AppTheme.ACCENT).backgroundColor(Color.Transparent)
              .height(40).width('100%').id('account-forgot-login-password')
              .onClick(() => {
                AppStorage.setOrCreate<string>('passwordResetMode', 'login')
                router.pushUrl({ url: 'pages/PasswordResetPage' })
              })
          }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')

          Column({ space: SPACING.MD }) {
            Text('支付密码').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT).width('100%')
            Text('用于查看完整银行卡号，与登录密码独立。').fontSize(FONT_SIZE.SM)
              .fontColor(AppTheme.MUTED).width('100%')
            TextInput({ text: this.loginPassword, placeholder: '请输入当前登录密码' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).width('100%')
              .id('account-payment-login-password').onChange((value: string) => { this.loginPassword = value })
            TextInput({ text: this.paymentPassword, placeholder: '请输入 6 位数字支付密码' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).maxLength(6).width('100%')
              .id('account-payment-password').onChange((value: string) => { this.paymentPassword = value.replace(/[^0-9]/g, '') })
            TextInput({ text: this.paymentConfirm, placeholder: '请再次输入 6 位数字支付密码' })
              .attributeModifier(new AppInputStyle()).type(InputType.Password).maxLength(6).width('100%')
              .id('account-payment-confirm').onChange((value: string) => { this.paymentConfirm = value.replace(/[^0-9]/g, '') })
            Button(this.savingPayment ? '保存中…' : '保存支付密码')
              .attributeModifier(new AppButtonStyle()).height(AppTheme.CONTROL_HEIGHT).width('100%')
              .enabled(!this.savingPayment && !this.savingPassword).id('account-save-payment')
              .onClick(() => { this.savePaymentPassword() })
            Button('忘记支付密码')
              .fontSize(FONT_SIZE.SM).fontColor(AppTheme.ACCENT).backgroundColor(Color.Transparent)
              .height(40).width('100%').id('account-forgot-payment-password')
              .onClick(() => {
                AppStorage.setOrCreate<string>('passwordResetMode', 'payment')
                router.pushUrl({ url: 'pages/PasswordResetPage' })
              })
          }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')
        }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
