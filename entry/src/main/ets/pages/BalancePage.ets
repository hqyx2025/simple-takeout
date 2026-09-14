/**
 * 我的钱包页（余额 + 已绑定银行卡）。
 *
 * 从「我的」页资产卡片的「余额」进入。
 *
 * 口径：
 *   - 余额的权威来源是 users.balance，统一走 /auth/me（fetchCurrentUserApi），
 *     本页不再自己算余额，避免出现第二个口径；
 *   - 银行卡走 GET /api/wallet/bank-cards，服务端**只存卡号后四位**并下发掩码卡号，
 *     客户端拿不到完整卡号；
 *   - 充值复用与「我的」页同一个 rechargeBalanceRemote（写库后回读最新余额）。
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { BankCard, User } from '../model/Models'
import { fetchBankCardsApi, fetchCurrentUserApi } from '../service/ApiService'
import { rechargeBalanceRemote } from '../service/AppStorageManager'
import { EmptyState } from '../components/EmptyState'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct BalancePage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State balance: number = 0
  @State cards: BankCard[] = []
  @State loading: boolean = true
  @State showRechargeDialog: boolean = false
  @State rechargeAmount: string = ''
  @State recharging: boolean = false

  aboutToAppear() {
    logInfo('Page', '进入我的钱包页 BalancePage')
    if (!this.loggedIn) {
      this.loading = false
      return
    }
    this.loadWallet()
  }

  private async loadWallet(): Promise<void> {
    this.loading = true
    // 余额与银行卡相互独立：任一失败都不应该让另一块空白
    const user: User | undefined = await fetchCurrentUserApi()
    if (user !== undefined && user !== null) {
      this.balance = user.balance
    }
    this.cards = await fetchBankCardsApi()
    this.loading = false
  }

  private openRecharge(): void {
    if (!this.loggedIn) {
      promptAction.showToast({ message: '请先登录后再充值', duration: 1800 })
      return
    }
    this.rechargeAmount = ''
    this.showRechargeDialog = true
  }

  private async submitRecharge(): Promise<void> {
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
    const updated: User | undefined = await rechargeBalanceRemote(amount)
    this.recharging = false
    if (updated === undefined || updated === null) {
      promptAction.showToast({ message: '充值失败，请稍后重试', duration: 2200 })
      return
    }
    this.showRechargeDialog = false
    this.rechargeAmount = ''
    // 以服务端返回的最新余额为准，避免前端自己加减算错
    this.balance = updated.balance
    promptAction.showToast({ message: `充值成功，当前余额 ¥${updated.balance.toFixed(2)}`, duration: 2000 })
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航
        Row() {
          Text('‹ 返回')
            .id('balance-back')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
            .onClick(() => { router.back() })
          Text('我的钱包')
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text(' ')
            .fontSize(FONT_SIZE.MD)
            .width(28)
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(COLORS.BG_WHITE)
        .alignItems(VerticalAlign.Center)

        if (!this.loggedIn) {
          EmptyState({ icon: '🔒', title: '暂无登录', description: '请登录后查看钱包' })
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 充值浮层（与「我的」页同一套做法：条件渲染 + Stack 承载，保证在最上层）
      if (this.showRechargeDialog) {
        this.RechargeOverlay()
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
        .fontColor(COLORS.TEXT_WHITE)
        .width('100%')
      Text(`¥${this.balance.toFixed(2)}`)
        .id('balance-amount')
        .fontSize(FONT_SIZE.BIG_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_WHITE)
        .width('100%')
      Row() {
        Text('余额为账户可用金额，下单支付时直接抵扣')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_WHITE)
          .layoutWeight(1)
        Button('立即充值')
          .height(34)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.PRIMARY)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
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
      } else if (this.cards.length === 0) {
        Column({ space: SPACING.XS }) {
          Text('暂无已绑定的银行卡')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text('绑定银行卡功能暂未开放')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_HINT)
        }
        .width('100%')
        .padding({ top: SPACING.XL, bottom: SPACING.XL })
        .alignItems(HorizontalAlign.Center)
      } else {
        ForEach(this.cards, (card: BankCard, index: number) => {
          this.BankCardItem(card, index)
        }, (card: BankCard) => card.id.toString())
      }

      Text('出于安全考虑，仅展示卡号后四位')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
        .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  BankCardItem(card: BankCard, index: number) {
    Row({ space: SPACING.MD }) {
      // 银行首字色块占位（不编造银行 Logo）
      Text(card.bankName.length > 0 ? card.bankName.charAt(0) : '银')
        .fontSize(FONT_SIZE.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_WHITE)
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
        }
        Text(card.cardNoMasked)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
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
          .width('100%').height(44).type(InputType.Number)
          .fontSize(FONT_SIZE.MD).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.SM)
          .onChange((value: string) => { this.rechargeAmount = value })
        Row({ space: SPACING.SM }) {
          Button('取消')
            .layoutWeight(1).height(42)
            .backgroundColor(COLORS.BG_PRIMARY).fontColor(COLORS.TEXT_SECONDARY)
            .onClick(() => { this.showRechargeDialog = false })
          Button(this.recharging ? '充值中…' : '确认充值')
            .layoutWeight(1).height(42)
            .backgroundColor(COLORS.PRIMARY).fontColor(COLORS.TEXT_WHITE)
            .enabled(!this.recharging)
            .onClick(() => { this.submitRecharge() })
        }.width('100%')
      }
      .width('86%').padding(SPACING.XL)
      .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.OVERLAY)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}