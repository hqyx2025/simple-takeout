import { AppTheme, AppButtonStyle, AppCardStyle, AppInputStyle } from '../common/theme/AppTheme'
/**
 * 我的钱包页（余额 + 已绑定银行卡）。
 *
 * 从「我的」页资产卡片的「余额」进入。
 *
 * 口径：
 *   - 余额的权威来源是 users.balance，统一走 /auth/me（fetchCurrentUserApi），
 *     本页不再自己算余额，避免出现第二个口径；
 *   - 银行卡走 GET /api/wallet/bank-cards，默认只下发掩码卡号；完整卡号必须经支付密码
 *     校验后按需短暂返回，页面和复制完成后立即清除本地明文；
 *   - 充值使用 rechargeBalanceRemote（写库后回读最新余额）。
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { BankCard, User } from '../model/Models'
import { fetchBankCardsApi, fetchCurrentUserApi, deleteBankCardApi, revealBankCardApi,
  RevealBankCardResult } from '../service/ApiService'
import { rechargeBalanceRemote } from '../service/AppStorageManager'
import { getAuthToken } from '../service/HttpClient'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { logInfo } from '../service/AppLogger'
import { pasteboard } from '@kit.BasicServicesKit'

@Entry
@Component
export struct BalancePage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
  }

  @StorageLink('isLoggedIn') @Watch('onSessionChanged') loggedIn: boolean = false
  @StorageLink('authToken') @Watch('onSessionChanged') authToken: string = ''
  @State balance: number = 0
  @State cards: BankCard[] = []
  @State loading: boolean = true
  @State cardsLoadFailed: boolean = false
  @State showRechargeDialog: boolean = false
  @State rechargeAmount: string = ''
  @State recharging: boolean = false
  @State deletingCardId: number = 0
  @State pendingDeleteId: number = 0
  @State pendingDeleteDescription: string = ''
  @State revealedCardId: number = 0
  @State revealedCardNumber: string = ''
  @State revealingCardId: number = 0
  private active: boolean = false
  private requestSequence: number = 0
  private sessionToken: string = ''
  private revealSequence: number = 0
  private revealClearTimer: number = -1
  private revealDialog: CustomDialogController = new CustomDialogController({
    cancel: () => { this.closeRevealDialog() },
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true,
    builder: RevealCardDialog({
      onSubmit: (password: string): void => { this.revealCard(password) },
      onClose: (): void => { this.closeRevealDialog() }
    })
  })

  aboutToAppear(): void {
    logInfo('Page', '进入我的钱包页 BalancePage')
    this.active = true
    this.sessionToken = getAuthToken()
    if (!this.loggedIn) {
      this.loading = false
    } else if (!this.hasWalletSession(this.sessionToken)) {
      this.loading = false
      router.replaceUrl({ url: 'pages/Index' })
    }
  }

  onPageShow(): void {
    this.active = true
    if (this.hasWalletSession(this.sessionToken)) { this.loadWallet() }
  }

  onPageHide(): void {
    this.active = false
    this.revealSequence += 1
    this.clearRevealedCard()
    this.revealingCardId = 0
    try { this.revealDialog.close() } catch (_) {}
  }

  aboutToDisappear(): void {
    this.active = false
    this.revealSequence += 1
    this.requestSequence += 1
    this.rechargeAmount = ''
    this.showRechargeDialog = false
    this.pendingDeleteId = 0
    this.clearRevealedCard()
    try { this.revealDialog.close() } catch (_) {}
  }

  private onSessionChanged(): void {
    const hadSession: boolean = this.sessionToken !== ''
    this.sessionToken = ''
    this.requestSequence += 1
    this.revealSequence += 1
    this.balance = 0
    this.cards = []
    this.loading = false
    this.cardsLoadFailed = false
    this.rechargeAmount = ''
    this.showRechargeDialog = false
    this.pendingDeleteId = 0
    this.pendingDeleteDescription = ''
    this.deletingCardId = 0
    this.recharging = false
    this.clearRevealedCard()
    try { this.revealDialog.close() } catch (_) {}
    if (this.active && hadSession) { router.replaceUrl({ url: 'pages/Index' }) }
  }

  private hasWalletSession(token: string): boolean {
    const user: User | undefined = AppStorage.get<User>('user')
    return this.active && this.loggedIn && token !== '' && token === getAuthToken()
      && token === this.sessionToken && (user?.id ?? 0) > 0
  }

  private async loadWallet(): Promise<void> {
    const token: string = this.sessionToken
    if (!this.hasWalletSession(token) || this.deletingCardId > 0) { return }
    const sequence: number = ++this.requestSequence
    this.loading = true
    // 余额与银行卡相互独立：任一失败都不应该让另一块空白
    const user: User | undefined = await fetchCurrentUserApi()
    if (!this.hasWalletSession(token) || sequence !== this.requestSequence) { return }
    if (user !== undefined && user !== null) {
      // 响应缺 balance 时显示 ¥NaN 是明显的坏体验；与 AppStorageManager/Index 统一兜底口径
      this.balance = Number.isFinite(user.balance) ? user.balance : 0
    }
    const cards: BankCard[] | null = await fetchBankCardsApi()
    if (!this.hasWalletSession(token) || sequence !== this.requestSequence) { return }
    this.cardsLoadFailed = cards === null
    if (cards !== null) { this.cards = cards }
    this.loading = false
  }

  private openAddCard(): void {
    if (!this.hasWalletSession(this.sessionToken)) {
      promptAction.showToast({ message: '请先登录后管理银行卡', duration: 1800 })
      return
    }
    router.pushUrl({ url: 'pages/AddBankCardPage' })
  }

  private confirmDelete(card: BankCard): void {
    if (this.loading || this.deletingCardId > 0 || !this.hasWalletSession(this.sessionToken)) { return }
    this.pendingDeleteId = card.id
    this.pendingDeleteDescription = `${card.bankName}（${card.cardNoMasked}）`
  }

  private openReveal(card: BankCard): void {
    if (this.loading || this.revealingCardId > 0 || !this.hasWalletSession(this.sessionToken)) { return }
    this.revealedCardId = 0
    this.revealedCardNumber = ''
    this.revealSequence += 1
    this.revealingCardId = card.id
    this.revealDialog.open()
  }

  private closeRevealDialog(): void {
    this.revealSequence += 1
    this.revealingCardId = 0
  }

  private async revealCard(paymentPassword: string): Promise<void> {
    const cardId: number = this.revealingCardId
    if (cardId <= 0 || !this.hasWalletSession(this.sessionToken)) { return }
    if (!/^[0-9]{6}$/.test(paymentPassword)) {
      promptAction.showToast({ message: '请输入 6 位数字支付密码', duration: 1800 })
      return
    }
    const token: string = this.sessionToken
    const sequence: number = this.revealSequence
    this.revealDialog.close()
    const result: RevealBankCardResult = await revealBankCardApi(cardId, paymentPassword)
    if (!this.hasWalletSession(token) || sequence !== this.revealSequence || cardId !== this.revealingCardId) { return }
    this.revealingCardId = 0
    if (result.cardNumber === null) {
      if (result.message.indexOf('未设置支付密码') >= 0) {
        promptAction.showToast({ message: '请先设置支付密码', duration: 2000 })
        router.pushUrl({ url: 'pages/SettingsPage' })
      } else {
        promptAction.showToast({ message: result.message || '支付密码错误，无法显示卡号', duration: 2000 })
      }
      return
    }
    this.clearRevealedCard()
    this.revealedCardId = cardId
    this.revealedCardNumber = result.cardNumber
    this.revealClearTimer = setTimeout(() => { this.clearRevealedCard() }, 30000)
    promptAction.showToast({ message: '完整卡号已显示，可点击复制', duration: 1800 })
  }

  private async copyRevealedCard(): Promise<void> {
    const token: string = this.sessionToken
    const cardId: number = this.revealedCardId
    if (!this.hasWalletSession(token) || cardId <= 0) { return }
    const cardNumber: string = this.revealedCardNumber
    if (!/^[0-9]{16,19}$/.test(cardNumber)) { return }
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard()
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cardNumber)
      const property: pasteboard.PasteDataProperty = data.getProperty()
      property.shareOption = pasteboard.ShareOption.LOCALDEVICE
      data.setProperty(property)
      await systemPasteboard.setData(data)
      if (!this.hasWalletSession(token) || cardId !== this.revealedCardId) { return }
      promptAction.showToast({ message: '完整卡号已复制', duration: 1600 })
      // 完整卡号只保留至复制完成，避免在页面状态中长期驻留。
      this.clearRevealedCard()
    } catch (_) {
      promptAction.showToast({ message: '复制失败，请稍后重试', duration: 1800 })
    }
  }

  private clearRevealedCard(): void {
    if (this.revealClearTimer >= 0) {
      clearTimeout(this.revealClearTimer)
      this.revealClearTimer = -1
    }
    this.revealedCardId = 0
    this.revealedCardNumber = ''
  }

  private async deleteCard(): Promise<void> {
    const cardId: number = this.pendingDeleteId
    this.pendingDeleteId = 0
    if (cardId <= 0 || this.deletingCardId > 0 || !this.hasWalletSession(this.sessionToken)) { return }
    const token: string = this.sessionToken
    this.deletingCardId = cardId
    const deleted: boolean = await deleteBankCardApi(cardId)
    if (!this.hasWalletSession(token)) { return }
    this.deletingCardId = 0
    if (deleted) {
      promptAction.showToast({ message: '银行卡已删除', duration: 1800 })
      await this.loadWallet()
    }
  }

  private openRecharge(): void {
    if (!this.hasWalletSession(this.sessionToken)) {
      promptAction.showToast({ message: '请先登录后再充值', duration: 1800 })
      return
    }
    this.rechargeAmount = ''
    this.showRechargeDialog = true
  }

  private async submitRecharge(): Promise<void> {
    if (!this.hasWalletSession(this.sessionToken)) { return }
    if (this.recharging) {
      promptAction.showToast({ message: '充值正在处理，请稍候', duration: 1500 })
      return
    }
    const amount: number = Number.parseFloat(this.rechargeAmount.trim())
    if (!Number.isFinite(amount) || amount < 0.01 || amount > 10000) {
      promptAction.showToast({ message: '请输入 0.01～10000 元的充值金额', duration: 1800 })
      return
    }
    this.recharging = true
    const token: string = this.sessionToken
    const updated: User | undefined = await rechargeBalanceRemote(amount)
    if (!this.hasWalletSession(token)) { return }
    this.recharging = false
    if (updated === undefined || updated === null) {
      return
    }
    this.showRechargeDialog = false
    this.rechargeAmount = ''
    // 以服务端返回的最新余额为准，避免前端自己加减算错
    const nextBalance: number = Number.isFinite(updated.balance) ? updated.balance : 0
    this.balance = nextBalance
    promptAction.showToast({ message: `充值成功，当前余额 ¥${nextBalance.toFixed(2)}`, duration: 2000 })
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航
        PageHeader({ title: '我的钱包', backId: 'balance-back', onBack: () => { router.back() } })

        if (!this.loggedIn) {
          Column() {
            EmptyState({ icon: $r('app.media.login_lock'), title: '暂无登录', description: '请登录后查看钱包' })
          }.layoutWeight(1).width('100%')
        } else {
          Scroll() {
            Column({ space: SPACING.MD }) {
              this.BalanceCard()
              this.BankCardSection()
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XXL })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        Column() {
          Button('添加银行卡')
            .attributeModifier(new AppButtonStyle()).height(AppTheme.CONTROL_HEIGHT).width('100%')
            .enabled(this.loggedIn && !this.loading && this.deletingCardId === 0 && !this.recharging)
            .id('wallet-add-card').onClick(() => { this.openAddCard() })
        }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
        .backgroundColor(AppTheme.PAGE).border({ width: { top: 1 }, color: AppTheme.BORDER })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 充值浮层（与「我的」页同一套做法：条件渲染 + Stack 承载，保证在最上层）
      if (this.showRechargeDialog) {
        this.RechargeOverlay()
      }
      if (this.pendingDeleteId > 0) {
        ConfirmDialog({
          title: '删除银行卡', content: `确定删除${this.pendingDeleteDescription}吗？`,
          confirmText: '删除', cancelText: '取消',
          onConfirm: () => { this.deleteCard() },
          onCancel: () => { this.pendingDeleteId = 0 }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  BalanceCard() {
    Column({ space: SPACING.SM }) {
      Text('账户余额')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.ON_PRIMARY)
        .width('100%')
      Text(`¥${this.balance.toFixed(2)}`)
        .id('balance-amount')
        .fontSize(FONT_SIZE.BIG_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.ON_PRIMARY)
        .width('100%')
      Row() {
        Text('余额为账户可用金额，下单支付时直接抵扣')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.ON_PRIMARY)
          .layoutWeight(1)
        Button('立即充值')
          .attributeModifier(new AppButtonStyle()).height(40)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.PRIMARY)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.ROUND)
          .onClick(() => { this.openRecharge() })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(SPACING.XL)
    .linearGradient({
      direction: GradientDirection.RightBottom,
      colors: [[COLORS.PRIMARY, 0.0], [COLORS.PRIMARY_LIGHT, 1.0]]
    })
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  BankCardSection() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('已绑定的银行卡')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(`${this.cards.length} 张`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
      }
      .width('100%')

      if (this.loading) {
        Text('正在加载…')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: SPACING.XL, bottom: SPACING.XL })
      } else if (this.cardsLoadFailed) {
        Text('银行卡暂时无法加载，请重试')
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        Button('重新加载银行卡')
          .attributeModifier(new AppButtonStyle()).height(44).width('100%')
          .fontColor(AppTheme.ACCENT).backgroundColor(AppTheme.ACCENT_SOFT)
          .id('wallet-reload-cards').onClick(() => { this.loadWallet() })
      } else if (this.cards.length === 0) {
        Column({ space: SPACING.XS }) {
          Text('暂无已绑定的银行卡')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('点击下方“添加银行卡”，记录卡片信息')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_HINT)
        }
        .width('100%')
        .padding({ top: SPACING.XL, bottom: SPACING.XL })
        .alignItems(HorizontalAlign.Center)
      } else {
        ForEach(this.cards, (card: BankCard, index: number) => {
          this.BankCardItem(card, index)
        }, (card: BankCard, index: number) => `${card.id}-${card.isDefault}-${index}`)
      }

      Text('出于安全考虑，仅展示卡号后四位')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
        .width('100%')
    }
      .attributeModifier(new AppCardStyle())
    .width('100%')
    .padding(SPACING.LG)
  }

  @Builder
  BankCardItem(card: BankCard, index: number) {
    Row({ space: SPACING.MD }) {
      // 银行首字色块占位（不编造银行 Logo）
      Text(card.bankName.length > 0 ? card.bankName.charAt(0) : '银')
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRIMARY)
        .width(44)
        .height(44)
        .borderRadius(BORDER_RADIUS.MD)
        .textAlign(TextAlign.Center)

      Column({ space: SPACING.XS }) {
        Row({ space: SPACING.SM }) {
          Text(card.bankName)
            .fontSize(FONT_SIZE.MD)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(card.cardType)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.BG_PRIMARY)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(BORDER_RADIUS.SM)
          if (card.isDefault) {
            Text('默认')
              .fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TAG_TEXT)
              .backgroundColor(COLORS.TAG_BG)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(BORDER_RADIUS.SM)
          }
        }.width('100%').alignItems(VerticalAlign.Center)
        Text(card.cardNoMasked)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        if (this.revealedCardId === card.id && this.revealedCardNumber !== '') {
          Text(this.revealedCardNumber)
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
            .id(`wallet-full-card-number-${card.id}`)
          Button('复制完整卡号')
            .attributeModifier(new AppButtonStyle()).height(40)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY).backgroundColor(COLORS.TAG_BG)
            .enabled(this.revealingCardId === 0)
            .id(`wallet-copy-card-${card.id}`).onClick(() => { this.copyRevealedCard() })
        }
        Row({ space: SPACING.SM }) {
          Button('显示完整卡号')
            .attributeModifier(new AppButtonStyle()).height(40)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY).backgroundColor(COLORS.TAG_BG)
            .enabled(!this.loading && this.deletingCardId === 0 && this.revealingCardId === 0 && !this.recharging)
            .id(`wallet-reveal-card-${card.id}`).onClick(() => { this.openReveal(card) })
          Button(this.deletingCardId === card.id ? '删除中…' : '删除银行卡')
            .attributeModifier(new AppButtonStyle()).height(40)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR).backgroundColor(COLORS.ERROR_LIGHT)
            .enabled(!this.loading && this.deletingCardId === 0 && this.revealingCardId === 0 && !this.recharging)
            .id(`wallet-delete-card-${card.id}`).onClick(() => { this.confirmDelete(card) })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: SPACING.SM, bottom: SPACING.SM })
    .alignItems(VerticalAlign.Center)
    .id(`bank-card-${index}`)
  }

  @Builder
  RechargeOverlay() {
    Column() {
      Column({ space: SPACING.MD }) {
        Text('充值余额')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text('充值金额会直接写入数据库，仅用于开发测试')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
        Text('充值金额（必填）')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
        TextInput({ placeholder: '请输入金额，如：100', text: this.rechargeAmount })
          .attributeModifier(new AppInputStyle())
          .width('100%').type(InputType.Number)
          .onChange((value: string) => { this.rechargeAmount = value })
        Row({ space: SPACING.SM }) {
          Button('取消')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1).height(42)
            .backgroundColor(COLORS.BG_PRIMARY).fontColor(COLORS.TEXT_SECONDARY)
            .onClick(() => { this.showRechargeDialog = false })
          Button(this.recharging ? '充值中…' : '确认充值')
            .attributeModifier(new AppButtonStyle())
            .layoutWeight(1).height(42)
            .backgroundColor(COLORS.PRIMARY).fontColor(COLORS.ON_PRIMARY)
            .enabled(!this.recharging)
            .onClick(() => { this.submitRecharge() })
        }.width('100%')
      }
        .attributeModifier(new AppCardStyle())
      .width('86%').constraintSize({ maxWidth: 460 }).padding(SPACING.XL)
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.OVERLAY)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}

/** 显示完整银行卡号前的支付密码校验弹窗。密码仅存在于弹窗状态，提交后立即清空。 */
@CustomDialog
export struct RevealCardDialog {
  controller?: CustomDialogController
  onSubmit: (password: string) => void = () => {}
  onClose: () => void = () => {}
  @State paymentPassword: string = ''

  aboutToDisappear(): void { this.paymentPassword = '' }

  private close(): void {
    this.paymentPassword = ''
    this.onClose()
    if (this.controller !== undefined) { this.controller.close() }
  }

  private submit(): void {
    const password: string = this.paymentPassword
    if (!/^[0-9]{6}$/.test(password)) {
      promptAction.showToast({ message: '请输入 6 位数字支付密码', duration: 1800 })
      return
    }
    this.paymentPassword = ''
    this.onSubmit(password)
  }

  build() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text('显示完整卡号')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT)
          .layoutWeight(1)
        Button('取消', { type: ButtonType.Normal })
          .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).backgroundColor(Color.Transparent)
          .height(40).onClick(() => { this.close() })
      }.width('100%')
      Text('请输入支付密码验证身份，验证通过后仅临时显示完整卡号。')
        .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
      TextInput({ text: this.paymentPassword, placeholder: '6 位数字支付密码' })
        .attributeModifier(new AppInputStyle()).width('100%').maxLength(6).type(InputType.Password)
        .id('wallet-reveal-payment-password')
        .onChange((value: string) => { this.paymentPassword = value.replace(/[^0-9]/g, '') })
      Button('确认显示')
        .attributeModifier(new AppButtonStyle()).width('100%').height(AppTheme.CONTROL_HEIGHT)
        .id('wallet-reveal-submit').onClick(() => { this.submit() })
    }
    .attributeModifier(new AppCardStyle()).width('86%').constraintSize({ maxWidth: 460 }).padding(SPACING.XL)
  }
}
