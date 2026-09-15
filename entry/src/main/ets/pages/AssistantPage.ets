/**
 * AI 智能助手聊天页。
 *
 * 助手能力来自后端 /api/assistant/chat：规则问答，按关键词命中意图后用库里的真实数据组装回答
 * （订单进度、余额、附近推荐店铺、退款/支付/优惠券/评价/地址等常见问题），不接外部大模型，
 * 因此没有密钥与额度依赖。
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction } from '../common/UiNavigation'
import { askAssistantApi, AssistantReply } from '../service/ApiService'
import { logInfo, logWarn } from '../service/AppLogger'

/** 一条聊天消息（role：'user' 用户提问 / 'assistant' 助手回答）。 */
class ChatMessage {
  id: number = 0
  role: string = 'assistant'
  text: string = ''

  static create(id: number, role: string, text: string): ChatMessage {
    const message: ChatMessage = new ChatMessage()
    message.id = id
    message.role = role
    message.text = text
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
const MAX_QUESTION_LENGTH = 200

@Component
export struct AssistantPage {
  // 消息 id 递增，保证 ForEach key 唯一且稳定（禁直接用 index）
  private nextMessageId: number = 1
  @State messages: ChatMessage[] = []
  @State input: string = ''
  @State sending: boolean = false
  @State quickQuestions: string[] = QUICK_QUESTIONS
  private scroller: Scroller = new Scroller()

  aboutToAppear() {
    logInfo('Page', '进入 AI 智能助手页 AssistantPage')
    this.messages = [ChatMessage.create(
      this.nextMessageId++,
      'assistant',
      '你好，我是简单外卖的智能助手。我能查订单进度、余额，也能推荐店铺和回答退款、优惠券、评价这些常见问题。\n试试下面的问题，或者直接打字问我。'
    )]
  }

  /** 追问建议去重后合并进快捷问题（最多保留 4 个，避免按钮换行挤压输入区）。 */
  private mergeSuggestions(suggestions: string[]): void {
    const merged: string[] = QUICK_QUESTIONS.slice()
    for (let i = 0; i < suggestions.length; i++) {
      const suggestion: string = suggestions[i]
      if (suggestion.trim() !== '' && merged.indexOf(suggestion) < 0) {
        merged.push(suggestion)
      }
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
    this.sending = true
    this.input = ''
    this.messages = this.messages.concat([ChatMessage.create(this.nextMessageId++, 'user', text)])
    this.scrollToBottom()

    const reply: AssistantReply | null = await askAssistantApi(text)
    if (reply === null) {
      logWarn('Assistant', `助手请求失败 question=${text}`)
      this.messages = this.messages.concat([ChatMessage.create(
        this.nextMessageId++,
        'assistant',
        '没能拿到回答，请检查网络或登录状态后重试。'
      )])
    } else {
      logInfo('Assistant', `助手回答长度=${reply.answer.length} 建议数=${reply.suggestions.length}`)
      this.messages = this.messages.concat([ChatMessage.create(this.nextMessageId++, 'assistant', reply.answer)])
      this.mergeSuggestions(reply.suggestions)
    }
    this.sending = false
    this.scrollToBottom()
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
      Row() {
        Text('AI 智能助手')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1).textAlign(TextAlign.Center)
      }
      .width('100%').height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
      .backgroundColor(COLORS.BG_WHITE)

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
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })

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
      .backgroundColor(COLORS.BG_WHITE)

      // 输入区
      Row({ space: SPACING.SM }) {
        TextInput({ placeholder: '想问点什么？例如：我的订单到哪了', text: this.input })
          .layoutWeight(1).height(42)
          .maxLength(MAX_QUESTION_LENGTH)
          .onChange((value: string) => { this.input = value })
          .onSubmit(() => { this.send(this.input) })
        Button(this.sending ? '发送中' : '发送')
          .height(42).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(this.sending ? COLORS.TEXT_HINT : COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .onClick(() => { this.send(this.input) })
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
      .backgroundColor(COLORS.BG_WHITE)
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
      Text(message.text)
        .fontSize(FONT_SIZE.MD)
        .fontColor(message.role === 'user' ? COLORS.TEXT_WHITE : COLORS.TEXT_PRIMARY)
        .backgroundColor(message.role === 'user' ? COLORS.PRIMARY : COLORS.BG_WHITE)
        .padding(SPACING.MD)
        .borderRadius(BORDER_RADIUS.LG)
        .constraintSize({ maxWidth: '78%' })
        .textAlign(TextAlign.Start)
        .id(`assistant-message-${message.id}`)
      if (message.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
  }
}
