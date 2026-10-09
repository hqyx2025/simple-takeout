import { PageHeader } from '../components/PageHeader'
import { AppTheme, AppButtonStyle } from '../common/theme/AppTheme'
import { FloatingTabBarTheme } from '../common/theme/FloatingTabBarTheme'
/**
 * AI 智能助手聊天页。
 *
 * 服务端提供真实业务查询、页面导航和管理员配置的模型问答。
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { askAssistantApi, AssistantReply, AssistantAction, AssistantHistoryMessage } from '../service/ApiService'
import { getAuthToken, getLastApiErrorMessage } from '../service/HttpClient'
import { User, UserRole } from '../model/Models'
import { logInfo, logWarn } from '../service/AppLogger'

/** 一条聊天消息（role：'user' 用户提问 / 'assistant' 助手回答）。 */
class ChatMessage {
  id: number = 0
  role: string = 'assistant'
  text: string = ''
  actions: AssistantAction[] = []

  static create(id: number, role: string, text: string, actions: AssistantAction[] = []): ChatMessage {
    const message: ChatMessage = new ChatMessage()
    message.id = id
    message.role = role
    message.text = text
    message.actions = actions
    return message
  }
}

/** 首屏快捷问题：点一下就问，避免用户不知道能问什么。 */
const QUICK_QUESTIONS: string[] = [
  '我的订单到哪了',
  '余额还有多少',
  '推荐几家店',
  '退款怎么申请'
]

/** 输入长度上限：与后端"纯文本问答"的定位匹配，避免超长文本打爆请求体。 */
const MAX_QUESTION_LENGTH = 1000

@Component
export struct AssistantPage {
  @Prop bottomInset: number = 0
  // 消息 id 递增，保证 ForEach key 唯一且稳定（禁直接用 index）
  private nextMessageId: number = 1
  private history: AssistantHistoryMessage[] = []
  private requestSequence: number = 0
  @StorageLink('authToken') @Watch('resetConversation') authToken: string = ''
  @State messages: ChatMessage[] = []
  @State input: string = ''
  @State sending: boolean = false
  @State quickQuestions: string[] = QUICK_QUESTIONS
  @State composerHeight: number = 124
  private scroller: Scroller = new Scroller()
  onNavigateTab: (index: number) => void = (_: number): void => {}

  aboutToAppear() {
    logInfo('Page', '进入 AI 智能助手页 AssistantPage')
    this.resetConversation()
  }

  resetConversation(): void {
    this.requestSequence += 1
    this.history = []
    this.input = ''
    this.sending = false
    this.quickQuestions = QUICK_QUESTIONS.slice()
    this.messages = [ChatMessage.create(
      this.nextMessageId++,
      'assistant',
      '你好，我是简单外卖的智能助手。可以帮你查订单、余额，推荐店铺，也能带你去订单、钱包、地址和优惠券页面。管理员启用 AI 后，还可以回答更多问题。\n例如：“打开我的订单”或“午餐怎么搭配？”'
    )]
  }

  aboutToDisappear(): void {
    this.requestSequence += 1
    this.sending = false
  }

  /** 追问建议去重后合并进快捷问题（最多保留 4 个，避免按钮换行挤压输入区）。 */
  private mergeSuggestions(suggestions: string[]): void {
    const merged: string[] = []
    for (let i = 0; i < suggestions.length; i++) {
      const suggestion: string = suggestions[i]
      if (suggestion.trim() !== '' && merged.indexOf(suggestion) < 0) {
        merged.push(suggestion)
      }
    }
    for (let i = 0; i < QUICK_QUESTIONS.length; i++) {
      if (merged.indexOf(QUICK_QUESTIONS[i]) < 0) { merged.push(QUICK_QUESTIONS[i]) }
    }
    this.quickQuestions = merged.slice(0, 4)
  }

  private async send(question: string): Promise<void> {
    const text: string = question.trim()
    if (text === '') {
      promptAction.showToast({ message: '请先输入想问的问题', duration: 1500 })
      return
    }
    if (this.sending) {
      promptAction.showToast({ message: '助手正在回答，请稍候', duration: 1500 })
      return
    }
    const user: User | undefined = AppStorage.get<User>('user')
    if (!(AppStorage.get<boolean>('isLoggedIn') ?? false) || getAuthToken() === '') {
      promptAction.showToast({ message: '请先登录后使用助手', duration: 1500 })
      return
    }
    if (user?.role !== UserRole.CUSTOMER) {
      promptAction.showToast({ message: '请使用用户端账号访问助手', duration: 1500 })
      return
    }
    const token: string = getAuthToken()
    const sequence: number = ++this.requestSequence
    this.sending = true
    this.input = ''
    this.messages = this.messages.concat([ChatMessage.create(this.nextMessageId++, 'user', text)])
    this.scrollToBottom()

    const reply: AssistantReply | null = await askAssistantApi(text, this.history)
    if (sequence !== this.requestSequence || token !== getAuthToken()) { return }
    if (reply === null) {
      logWarn('Assistant', '助手请求失败')
      this.messages = this.messages.concat([ChatMessage.create(
        this.nextMessageId++,
        'assistant',
        getLastApiErrorMessage() || '没能拿到回答，请检查网络或登录状态后重试。'
      )])
    } else {
      logInfo('Assistant', `助手回答长度=${reply.answer.length} 建议数=${reply.suggestions.length}`)
      this.messages = this.messages.concat([ChatMessage.create(this.nextMessageId++, 'assistant', reply.answer, reply.actions)])
      if (reply.source === 'AI') {
        const questionMessage: AssistantHistoryMessage = { role: 'user', content: text }
        const answerMessage: AssistantHistoryMessage = { role: 'assistant', content: reply.answer.slice(0, 1000) }
        this.history = this.history.concat([questionMessage, answerMessage]).slice(-10)
      } else {
        this.history = []
      }
      this.mergeSuggestions(reply.suggestions)
    }
    this.sending = false
    this.scrollToBottom()
  }

  private openAction(action: AssistantAction): void {
    const user: User | undefined = AppStorage.get<User>('user')
    if (!(AppStorage.get<boolean>('isLoggedIn') ?? false) || user?.role !== UserRole.CUSTOMER) {
      promptAction.showToast({ message: '请先登录用户端账号', duration: 1500 })
      return
    }
    switch (action.target) {
      case 'ORDERS':
        AppStorage.setOrCreate<number>('orderFilterStatus', -1)
        router.pushUrl({ url: 'pages/OrderListPage' })
        break
      case 'WALLET': router.pushUrl({ url: 'pages/BalancePage' }); break
      case 'ADDRESSES': router.pushUrl({ url: 'pages/AddressListPage' }); break
      case 'COUPONS': router.pushUrl({ url: 'pages/CouponCenterPage' }); break
      case 'SEARCH': router.pushUrl({ url: 'pages/SearchPage' }); break
      case 'FAVORITES': router.pushUrl({ url: 'pages/FavoriteListPage' }); break
      case 'HOME': this.onNavigateTab(0); break
      case 'PROFILE': this.onNavigateTab(3); break
      case 'CART': this.onNavigateTab(2); break
      case 'SETTINGS': router.pushUrl({ url: 'pages/SettingsPage' }); break
      case 'LOCATION': router.pushUrl({ url: 'pages/LocationPage' }); break
      case 'SUPPORT': router.pushUrl({ url: 'pages/ContactCustomerServicePage' }); break
      case 'STORE': {
        const value: string = action.value ?? ''
        const storeId: number = Number(value)
        if (!/^\d+$/.test(value) || !Number.isSafeInteger(storeId) || storeId <= 0) { return }
        AppStorage.setOrCreate<number>('selectedStoreId', storeId)
        AppStorage.setOrCreate<string>('selectedStoreName', action.label)
        router.pushUrl({ url: 'pages/StoreDetailPage' })
        break
      }
      default: promptAction.showToast({ message: '暂不支持这个页面入口', duration: 1500 })
    }
  }

  private scrollToBottom(): void {
    // 延迟到本帧布局完成后再滚，否则新消息还没进入列表，滚动到底会差一条
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 60)
  }

  build() {
    Column() {
      // 标题栏：本组件是首页的 Tab 内容（不是独立路由页），因此不放返回按钮
      PageHeader({ title: 'AI 智能助手', showBack: false, topPadding: 0 })

      // 消息铺满主体，操作区与首页导航一样浮在内容上方。
      Stack({ alignContent: Alignment.Bottom }) {
        // 消息区：用 List 承载，条目从顶部开始排列（Scroll 内容不足一屏时会被垂直居中）
        List({ space: SPACING.MD, scroller: this.scroller }) {
          ForEach(this.messages, (message: ChatMessage) => {
            ListItem() {
              this.MessageBubble(message)
            }
          }, (message: ChatMessage) => message.id.toString())

          if (this.sending) {
            ListItem() {
              Row({ space: SPACING.SM }) {
                LoadingProgress().width(18).height(18).color(COLORS.PRIMARY)
                Text('助手正在思考…').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)
            }
          }
        }
        .id('assistant-message-list')
        .width('100%').height('100%').scrollBar(BarState.Off)
        .clipContent(ContentClipMode.BOUNDARY)
        .contentEndOffset(FloatingTabBarTheme.CONTENT_INSET + this.bottomInset + this.composerHeight + SPACING.MD)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })
        .onAreaChange((oldArea: Area, area: Area) => {
          if (Number(oldArea.height) !== Number(area.height)) { this.scrollToBottom() }
        })

        Column() {
          // 快捷问题
          Scroll() {
            Row({ space: SPACING.SM }) {
              ForEach(this.quickQuestions, (question: string) => {
                Text(question)
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
                  .backgroundColor(COLORS.TAG_BG)
                  .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
                  .borderRadius(BORDER_RADIUS.ROUND)
                  .id(`assistant-quick-${question}`)
                  .onClick(() => { this.send(question) })
              }, (question: string) => question)
            }
            .padding({ left: SPACING.LG, right: SPACING.LG })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%').height(52)
          .backgroundColor(Color.Transparent)

          // 输入与发送共用一个悬浮容器。
          Row({ space: SPACING.SM }) {
            TextInput({ placeholder: '想问点什么？例如：我的订单到哪了', text: this.input })
              .height(AppTheme.CONTROL_HEIGHT).fontSize(16)
              .fontColor(AppTheme.TEXT).placeholderColor(AppTheme.MUTED).caretColor(AppTheme.ACCENT)
              .backgroundColor(Color.Transparent)
              .border({ width: 0 }).borderRadius(BORDER_RADIUS.CIRCLE)
              .padding({ left: SPACING.MD, right: SPACING.XS })
              .layoutWeight(1)
              .id('assistant-input')
              .maxLength(MAX_QUESTION_LENGTH)
              .onChange((value: string) => { this.input = value })
              .onSubmit(() => { this.send(this.input) })
            Button(this.sending ? '发送中' : '发送')
              .attributeModifier(new AppButtonStyle())
              .height(42).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_WHITE)
              .backgroundColor(this.sending ? COLORS.TEXT_HINT : AppTheme.ASSISTANT_SEND)
              .borderRadius(BORDER_RADIUS.ROUND)
              .id('assistant-send')
              .onClick(() => { this.send(this.input) })
          }
          .width('75%')
          .padding({ left: SPACING.XS, right: SPACING.MD, top: SPACING.XS, bottom: SPACING.XS })
          .margin({ top: SPACING.SM, bottom: SPACING.MD })
          .backgroundColor(Color.Transparent)
          .backgroundEffect({ radius: FloatingTabBarTheme.GLASS_BLUR_RADIUS,
            saturation: FloatingTabBarTheme.GLASS_SATURATION, color: FloatingTabBarTheme.GLASS_COLOR })
          .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(BORDER_RADIUS.CIRCLE)
          .id('assistant-composer')
        }
        .width('100%')
        .margin({ bottom: FloatingTabBarTheme.CONTENT_INSET + this.bottomInset })
        .hitTestBehavior(HitTestMode.Transparent)
        .onAreaChange((_: Area, area: Area) => {
          const height: number = Number(area.height)
          if (height > 0 && height !== this.composerHeight) {
            this.composerHeight = height
            this.scrollToBottom()
          }
        })
      }.width('100%').layoutWeight(1)
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  MessageBubble(message: ChatMessage) {
    Row() {
      if (message.role === 'user') {
        Blank()
      }
      Column({ space: SPACING.SM }) {
        Text(message.text)
          .fontSize(FONT_SIZE.MD)
          .fontColor(message.role === 'user' ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
          .textAlign(TextAlign.Start)
          .id(`assistant-message-${message.id}`)
        ForEach(message.actions, (action: AssistantAction) => {
          this.ActionButton(action, message.id)
        }, (action: AssistantAction) => `${action.target}-${action.value ?? ''}`)
      }
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(message.role === 'user' ? COLORS.PRIMARY : COLORS.BG_WHITE)
      .padding(SPACING.MD)
      .borderRadius(BORDER_RADIUS.LG)
      .constraintSize({ maxWidth: '78%' })
      if (message.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
  }

  @Builder
  ActionButton(action: AssistantAction, messageId: number) {
    Button(action.label)
      .attributeModifier(new AppButtonStyle())
      .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
      .backgroundColor(COLORS.TAG_BG).borderRadius(BORDER_RADIUS.ROUND)
      .id(action.target === 'STORE' ? `assistant-action-${messageId}-STORE-${action.value ?? ''}`
        : `assistant-action-${messageId}-${action.target}`)
      .onClick(() => { this.openAction(action) })
  }
}
