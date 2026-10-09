import { COLORS, FONT_SIZE, SPACING } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { AppTheme, AppButtonStyle, AppCardStyle, AppInputStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { BankCard, User } from '../model/Models'
import { addBankCardApi } from '../service/ApiService'
import { getAuthToken } from '../service/HttpClient'
import { KeyboardAvoidMode } from '@kit.ArkUI'

@Entry
@Component
export struct AddBankCardPage {
  @StorageLink('isLoggedIn') @Watch('onSessionChanged') loggedIn: boolean = false
  @StorageLink('authToken') @Watch('onSessionChanged') authToken: string = ''
  @State bankName: string = ''
  @State cardType: string = '储蓄卡'
  // 完整卡号只在本页输入期间存在于内存，离开页面或保存后立即清除。
  @State fullCardNumber: string = ''
  @State saving: boolean = false
  @State feedback: string = ''
  private active: boolean = false
  private sessionToken: string = ''
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET
  private keyboardModeChanged: boolean = false

  aboutToAppear(): void {
    this.active = true
    this.sessionToken = getAuthToken()
    if (!this.hasAccountSession()) { router.replaceUrl({ url: 'pages/Index' }) }
  }

  aboutToDisappear(): void {
    this.active = false
    this.clearForm()
    this.restoreKeyboardAvoidMode()
  }

  onPageShow(): void {
    if (this.keyboardModeChanged) { return }
    try {
      this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode()
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
      this.keyboardModeChanged = true
    } catch (_) {}
  }

  onPageHide(): void {
    this.restoreKeyboardAvoidMode()
  }

  private restoreKeyboardAvoidMode(): void {
    if (!this.keyboardModeChanged) { return }
    try {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode)
      this.keyboardModeChanged = false
    } catch (_) {}
  }

  private hasAccountSession(): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.loggedIn && getAuthToken() !== '' && (user?.id ?? 0) > 0
  }

  private clearForm(): void {
    this.bankName = ''
    this.fullCardNumber = ''
    this.cardType = '储蓄卡'
    this.feedback = ''
  }

  private onSessionChanged(): void {
    const hadSession: boolean = this.sessionToken !== ''
    this.sessionToken = ''
    this.clearForm()
    this.saving = false
    if (this.active && hadSession) { router.replaceUrl({ url: 'pages/Index' }) }
  }

  private async saveCard(): Promise<void> {
    if (this.saving) { return }
    if (!this.hasAccountSession() || this.sessionToken !== getAuthToken()) {
      this.clearForm()
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    const name: string = this.bankName.trim()
    const fullCardNumber: string = this.fullCardNumber.replace(/\s/g, '').trim()
    if (name === '' || name.length > 64) {
      promptAction.showToast({ message: '请填写 1～64 个字符的银行名称', duration: 1800 })
      return
    }
    if (!/^[0-9]{16,19}$/.test(fullCardNumber)) {
      promptAction.showToast({ message: '请输入 16～19 位完整银行卡号，仅限数字', duration: 1800 })
      return
    }
    this.saving = true
    this.feedback = ''
    const token: string = getAuthToken()
    const card: BankCard | null = await addBankCardApi(name, this.cardType, fullCardNumber)
    if (!this.active || token !== getAuthToken() || token !== this.sessionToken || !this.hasAccountSession()) { return }
    this.saving = false
    if (card === null) {
      this.feedback = '银行卡未保存，请检查网络或填写内容后重试'
      return
    }
    this.clearForm()
    promptAction.showToast({ message: '银行卡已添加', duration: 1800 })
    router.back()
  }

  build() {
    Column() {
      PageHeader({ title: '添加银行卡', backId: 'bank-card-back', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.LG }) {
          Column({ space: SPACING.MD }) {
            Text('银行名称').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
            TextInput({ text: this.bankName, placeholder: '例如：中国工商银行' })
              .attributeModifier(new AppInputStyle()).width('100%').maxLength(64)
              .enabled(!this.saving).id('bank-card-bank-name')
              .onChange((value: string) => { this.bankName = value })
            Text('卡片类型').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
            Row({ space: SPACING.MD }) {
              Button('储蓄卡')
                .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44)
                .fontColor(this.cardType === '储蓄卡' ? AppTheme.PRIMARY_TEXT : AppTheme.MUTED)
                .backgroundColor(this.cardType === '储蓄卡' ? AppTheme.PRIMARY : AppTheme.INPUT)
                .enabled(!this.saving).id('bank-card-type-debit')
                .onClick(() => { this.cardType = '储蓄卡' })
              Button('信用卡')
                .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44)
                .fontColor(this.cardType === '信用卡' ? AppTheme.PRIMARY_TEXT : AppTheme.MUTED)
                .backgroundColor(this.cardType === '信用卡' ? AppTheme.PRIMARY : AppTheme.INPUT)
                .enabled(!this.saving).id('bank-card-type-credit')
                .onClick(() => { this.cardType = '信用卡' })
            }.width('100%')
            Text('完整卡号').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
              .id('bank-card-full-number')
            TextInput({ text: this.fullCardNumber, placeholder: '请输入 16～19 位银行卡号' })
              .attributeModifier(new AppInputStyle()).width('100%').type(InputType.Number).maxLength(19)
              .enabled(!this.saving).id('bank-card-last4')
              .onChange((value: string) => { this.fullCardNumber = value.replace(/[^0-9]/g, '') })
          }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')
          Text('完整卡号仅用于安全绑定，服务端加密保存；钱包页默认只展示卡号后四位。')
            .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
          if (this.feedback !== '') {
            Text(this.feedback).fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
              .width('100%').id('bank-card-feedback')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XL })
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
      .id('bank-card-form-scroll')
      Column() {
        Button(this.saving ? '保存中…' : '保存银行卡')
          .attributeModifier(new AppButtonStyle()).height(AppTheme.CONTROL_HEIGHT).width('100%')
          .enabled(this.loggedIn && !this.saving).id('bank-card-save')
          .onClick(() => { this.saveCard() })
      }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
      .backgroundColor(AppTheme.PAGE).border({ width: { top: 1 }, color: AppTheme.BORDER })
    }.width('100%').height('100%').backgroundColor(AppTheme.PAGE)
  }
}
