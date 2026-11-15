import { AppButtonStyle, AppCardStyle, AppTheme } from '../../common/theme/AppTheme'
import { COLORS, FONT_SIZE, SPACING } from '../../common/Constants'
import { PageHeader } from '../../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../../common/UiNavigation'
import { changePasswordRemote, getLastRemoteErrorMessage } from '../../service/AppStorageManager'
import { setPaymentPasswordApi, PaymentPasswordResult } from '../../service/ApiService'
import { ApiResponse, getAuthToken, getAuthSessionEpoch } from '../../service/HttpClient'
import { closeAccountApi } from '../../service/api/AuthApi'
import { User } from '../../model/Models'
import { logout } from '../../service/AppStorageManager'
import { FormInput } from '../../components/FormInput'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import { newPasswordError } from '../../common/PasswordPolicy'

@Component
export struct AccountSecurityTask {
  @Prop task: string = 'login'
  @Prop @Watch('onVisibility') visible: boolean = true
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
  @State closurePassword: string = ''
  @State closureConfirmed: boolean = false
  @State closingAccount: boolean = false
  private active: boolean = false
  private sessionEpoch: number = 0
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET
  private keyboardModeChanged: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.sessionEpoch = getAuthSessionEpoch()
    this.onPageShow()
    if (!this.hasSession()) { router.replaceUrl({ url: 'pages/Index' }) }
  }

  onVisibility(): void {
    this.active = this.visible
    if (this.visible) { this.onPageShow() }
    else { this.clearFields(); this.restoreKeyboardAvoidMode() }
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
    return this.loggedIn && getAuthToken() !== '' && this.sessionEpoch === getAuthSessionEpoch()
      && this.user.id > 0
  }

  private clearFields(): void {
    this.oldPassword = ''
    this.newPassword = ''
    this.confirmPassword = ''
    this.loginPassword = ''
    this.paymentPassword = ''
    this.paymentConfirm = ''
    this.closurePassword = ''
    this.closureConfirmed = false
  }

  private restoreKeyboardAvoidMode(): void {
    if (!this.keyboardModeChanged) { return }
    try {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode)
      this.keyboardModeChanged = false
    } catch (_) {}
  }

  private async saveLoginPassword(): Promise<void> {
    if (this.savingPassword || this.savingPayment || this.closingAccount || !this.hasSession()) { return }
    if (this.oldPassword === '' || this.newPassword === '' || this.confirmPassword === '') {
      promptAction.showToast({ message: '请填写登录密码的完整信息', duration: 1800 })
      return
    }
    if (newPasswordError(this.newPassword)) {
      promptAction.showToast({ message: newPasswordError(this.newPassword), duration: 1800 })
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
    const epoch: number = this.sessionEpoch
    this.savingPassword = true
    const ok: boolean = await changePasswordRemote(this.oldPassword, this.newPassword)
    this.savingPassword = false
    this.clearFields()
    if (!this.active || epoch !== getAuthSessionEpoch()) { return }
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
    if (this.savingPayment || this.savingPassword || this.closingAccount || !this.hasSession()) { return }
    if (this.loginPassword === '' || !/^[0-9]{6}$/.test(this.paymentPassword)) {
      promptAction.showToast({ message: '请输入登录密码和 6 位数字支付密码', duration: 1800 })
      return
    }
    if (this.paymentPassword !== this.paymentConfirm) {
      promptAction.showToast({ message: '两次输入的支付密码不一致', duration: 1800 })
      return
    }
    const epoch: number = this.sessionEpoch
    const userId: number = this.user.id
    this.savingPayment = true
    const result: PaymentPasswordResult = await setPaymentPasswordApi(this.loginPassword, this.paymentPassword)
    this.savingPayment = false
    this.loginPassword = ''
    this.paymentPassword = ''
    this.paymentConfirm = ''
    if (!this.active || epoch !== getAuthSessionEpoch() || userId !== this.user.id) { return }
    promptAction.showToast({ message: result.success ? '支付密码已保存，请重新登录' : (result.message || '支付密码保存失败'), duration: 2000 })
    if (result.success) {
      logout()
      router.replaceUrl({ url: 'pages/Index' })
    }
  }

  private async closeAccount(): Promise<void> {
    if (this.closingAccount || this.savingPassword || this.savingPayment || !this.hasSession() || this.user.role !== 0) { return }
    if (!this.closureConfirmed || !this.closurePassword) {
      promptAction.showToast({ message: '请填写当前登录密码并确认注销' }); return
    }
    const epoch: number = this.sessionEpoch
    this.closingAccount = true
    try {
      const response: ApiResponse<string> = await closeAccountApi(this.closurePassword)
      if (!this.active || epoch !== getAuthSessionEpoch()) { return }
      if (response.code !== 200) {
        promptAction.showToast({ message: response.message || '注销未完成，请稍后重试' }); return
      }
      this.clearFields()
      logout()
      promptAction.showToast({ message: '账号已注销' })
      router.replaceUrl({ url: 'pages/Index' })
    } finally { if (this.active) { this.closingAccount = false } }
  }

  private async confirmClosure(): Promise<void> {
    if (!this.hasSession() || this.user.role !== 0 || !this.closureConfirmed || this.closingAccount) { return }
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '确认注销账号', message: '注销后无法恢复，确认继续？',
        buttons: [{ text: '继续保留', color: COLORS.TEXT_SECONDARY }, { text: '确认注销', color: COLORS.ERROR }]
      })
      if (choice.index === 1) { await this.closeAccount() }
    } catch (_) {}
  }

  build() {
    Column() {
      PageHeader({ title: this.task === 'login' ? '修改登录密码' : this.task === 'payment' ? '支付密码' : '注销账号',
        backId: 'account-security-back', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.LG }) {
          if (this.task === 'login') {
          Column({ space: SPACING.MD }) {
            Text('修改登录密码').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT).width('100%')
            Text('修改成功后当前登录会失效，需要重新登录。').fontSize(FONT_SIZE.SM)
              .fontColor(AppTheme.MUTED).width('100%')
            FormInput({ required: true, label: '当前登录密码', value: this.oldPassword, placeholder: '请输入当前密码',
              fieldId: 'account-old-password', inputType: InputType.Password, maxLength: 64,
              isEnabled: !this.savingPassword && !this.savingPayment, onChange: (value: string) => { this.oldPassword = value } })
            FormInput({ required: true, label: '新登录密码', value: this.newPassword, placeholder: '请输入 6 至 64 位密码', passwordRules: true,
              fieldId: 'account-new-password', inputType: InputType.Password, maxLength: 64,
              isEnabled: !this.savingPassword && !this.savingPayment, onChange: (value: string) => { this.newPassword = value } })
            FormInput({ required: true, label: '确认新登录密码', value: this.confirmPassword, validator: (value: string): string => value === this.newPassword ? '' : '两次输入的密码不一致', placeholder: '再次输入新密码',
              fieldId: 'account-confirm-password', inputType: InputType.Password, maxLength: 64,
              isEnabled: !this.savingPassword && !this.savingPayment, onChange: (value: string) => { this.confirmPassword = value } })
            Button('忘记登录密码')
              .fontSize(FONT_SIZE.SM).fontColor(AppTheme.ACCENT).backgroundColor(Color.Transparent)
              .height(40).width('100%').id('account-forgot-login-password')
              .onClick(() => {
                router.pushUrl({ url: 'pages/PasswordResetPage', params: { resetMode: 'login' } })
              })
          }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')

          } else if (this.task === 'payment') {
          Column({ space: SPACING.MD }) {
            Text('支付密码').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT).width('100%')
            Text('用于余额支付和查看完整卡号，与登录密码独立。').fontSize(FONT_SIZE.SM)
              .fontColor(AppTheme.MUTED).width('100%')
            FormInput({ required: true, label: '当前登录密码', value: this.loginPassword, placeholder: '请输入当前密码',
              fieldId: 'account-payment-login-password', inputType: InputType.Password, maxLength: 64,
              isEnabled: !this.savingPassword && !this.savingPayment, onChange: (value: string) => { this.loginPassword = value } })
            FormInput({ required: true, label: '支付密码', value: this.paymentPassword, placeholder: '6 位数字',
              fieldId: 'account-payment-password', inputType: InputType.Password, maxLength: 6,
              isEnabled: !this.savingPassword && !this.savingPayment, onChange: (value: string) => { this.paymentPassword = value.replace(/[^0-9]/g, '') } })
            FormInput({ required: true, label: '确认支付密码', value: this.paymentConfirm, validator: (value: string): string => value === this.paymentPassword ? '' : '两次输入的密码不一致', placeholder: '再次输入 6 位数字',
              fieldId: 'account-payment-confirm', inputType: InputType.Password, maxLength: 6,
              isEnabled: !this.savingPassword && !this.savingPayment, onChange: (value: string) => { this.paymentConfirm = value.replace(/[^0-9]/g, '') } })
            Button('忘记支付密码')
              .fontSize(FONT_SIZE.SM).fontColor(AppTheme.ACCENT).backgroundColor(Color.Transparent)
              .height(40).width('100%').id('account-forgot-payment-password')
              .onClick(() => {
                router.pushUrl({ url: 'pages/PasswordResetPage', params: { resetMode: 'payment' } })
              })
          }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')

          } else if (this.user.role === 0) {
            Column({ space: SPACING.MD }) {
              Text('注销账号').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT).width('100%')
              Text('注销后无法恢复。请先处理余额、未完成订单和售后；联系方式与地址会清除，订单和资金记录保留。')
                .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
              FormInput({ label: '当前登录密码', value: this.closurePassword, placeholder: '请输入当前密码',
                fieldId: 'account-close-password', inputType: InputType.Password, maxLength: 64,
                isEnabled: !this.closingAccount && !this.savingPassword && !this.savingPayment,
                onChange: (value: string) => { this.closurePassword = value } })
              Row({ space: 8 }) {
                Checkbox({ name: 'close-account' }).select(this.closureConfirmed).id('account-close-confirm')
                  .enabled(!this.closingAccount).onChange((checked: boolean) => { this.closureConfirmed = checked })
                Text('我确认注销此账号').fontSize(FONT_SIZE.MD).fontColor(AppTheme.TEXT)
              }.width('100%')

            }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')

          }
        }.width('100%').padding(SPACING.LG)
      }.align(Alignment.Top).layoutWeight(1).width('100%').scrollBar(BarState.Off)
      Button(this.savingPassword || this.savingPayment || this.closingAccount ? '处理中…'
        : this.task === 'login' ? '保存登录密码' : this.task === 'payment' ? '保存支付密码' : '确认注销账号')
        .attributeModifier(new AppButtonStyle()).height(AppTheme.CONTROL_HEIGHT).width('100%')
        .id(this.task === 'login' ? 'account-save-password' : this.task === 'payment' ? 'account-save-payment' : 'account-close-submit')
        .enabled(this.hasSession() && !this.savingPassword && !this.savingPayment && !this.closingAccount
          && (this.task !== 'closure' || (this.closureConfirmed && this.user.role === 0)))
        .onClick(() => {
          if (this.task === 'login') { this.saveLoginPassword() }
          else if (this.task === 'payment') { this.savePaymentPassword() }
          else { this.confirmClosure() }
        }).margin({ bottom: SPACING.LG })
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
