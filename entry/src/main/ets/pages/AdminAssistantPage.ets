import { COLORS, FONT_SIZE, SPACING } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { AppButtonStyle, AppCardStyle, AppInputStyle, AppTheme } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { User, UserRole } from '../model/Models'
import { ApiResponse } from '../service/HttpClient'
import {
  AssistantAdminConfig, AssistantAdminConfigRequest, fetchAssistantAdminConfig,
  saveAssistantAdminConfig, testAssistantAdminConnection
} from '../service/AssistantAdminApi'

@Entry
@Component
export struct AdminAssistantPage {
  @StorageLink('isLoggedIn') @Watch('onSessionChanged') loggedIn: boolean = false
  @StorageLink('user') @Watch('onSessionChanged') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State aiEnabled: boolean = false
  @State endpoint: string = ''
  @State model: string = ''
  @State apiKey: string = ''
  @State hasApiKey: boolean = false
  @State clearApiKey: boolean = false
  @State loaded: boolean = false
  @State busy: boolean = false
  @State feedback: string = ''
  @State showClearConfirm: boolean = false
  private active: boolean = false

  aboutToAppear(): void {
    this.active = true
    if (this.ensureAdmin()) {
      this.loadConfig()
    }
  }

  aboutToDisappear(): void {
    this.active = false
    this.apiKey = ''
  }

  private onSessionChanged(): void {
    if (this.active && !this.ensureAdmin()) { this.loaded = false }
  }

  private ensureAdmin(): boolean {
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      this.apiKey = ''
      router.replaceUrl({ url: 'pages/Index' })
      return false
    }
    return true
  }

  private applyConfig(config: AssistantAdminConfig): void {
    this.aiEnabled = config.enabled
    this.endpoint = config.endpoint
    this.model = config.model
    this.hasApiKey = config.hasApiKey
    this.apiKey = ''
    this.clearApiKey = false
  }

  private async loadConfig(): Promise<void> {
    if (this.busy || !this.ensureAdmin()) { return }
    this.busy = true
    this.loaded = false
    const accountId: number = this.user.id
    const response: ApiResponse<AssistantAdminConfig> = await fetchAssistantAdminConfig()
    if (this.active && this.ensureAdmin() && this.user.id === accountId) {
      if (response.code === 200 && response.data !== undefined && response.data !== null) {
        this.applyConfig(response.data)
        this.loaded = true
        this.feedback = ''
      } else {
        this.feedback = response.message || '配置加载失败，请重试'
      }
    }
    this.busy = false
  }

  private validateConfig(testConnection: boolean): boolean {
    const endpoint: string = this.endpoint.trim()
    const model: string = this.model.trim()
    const hasKey: boolean = this.apiKey.trim() !== '' || (this.hasApiKey && !this.clearApiKey)
    if (endpoint !== '' && (!endpoint.startsWith('https://') || !endpoint.endsWith('/chat/completions') || /\s/.test(endpoint))) {
      promptAction.showToast({ message: '请填写完整的 HTTPS chat/completions 接口地址', duration: 2000 })
      return false
    }
    if ((this.aiEnabled || testConnection) && (endpoint === '' || model === '' || !hasKey)) {
      promptAction.showToast({ message: '请先填写接口地址、模型和 API Key', duration: 2000 })
      return false
    }
    return true
  }

  private async saveConfig(testConnection: boolean = false): Promise<void> {
    if (this.busy || !this.loaded || !this.ensureAdmin() || !this.validateConfig(testConnection)) { return }
    this.busy = true
    this.feedback = testConnection ? '正在保存并测试连接…' : '正在保存…'
    const accountId: number = this.user.id
    const request: AssistantAdminConfigRequest = {
      enabled: this.aiEnabled,
      endpoint: this.endpoint.trim(),
      model: this.model.trim(),
      apiKey: this.apiKey.trim(),
      clearApiKey: this.clearApiKey
    }
    const response: ApiResponse<AssistantAdminConfig> = await saveAssistantAdminConfig(request)
    // 密钥只用于本次请求，失败后也不留在输入框中。
    this.apiKey = ''
    if (!this.active || !this.ensureAdmin() || this.user.id !== accountId) {
      this.busy = false
      return
    }
    if (response.code !== 200 || response.data === undefined || response.data === null) {
      this.feedback = response.message || '保存失败，请重试'
      this.busy = false
      return
    }
    this.applyConfig(response.data)
    this.feedback = '配置已保存'
    if (testConnection) {
      this.feedback = '配置已保存，正在测试连接…'
      const testResponse: ApiResponse<string> = await testAssistantAdminConnection()
      if (this.active && this.ensureAdmin() && this.user.id === accountId) {
        this.feedback = testResponse.code === 200 ? (testResponse.data || '连接成功') : '配置已保存，' + (testResponse.message || '连接测试失败')
        if (testResponse.code === 200) {
          promptAction.showToast({ message: this.feedback, duration: 1800 })
        }
      }
    } else {
      promptAction.showToast({ message: 'AI 助手配置已保存', duration: 1800 })
    }
    this.busy = false
  }

  build() {
    Stack() {
      Column() {
        PageHeader({
          title: 'AI 助手设置', showBack: true, backId: 'admin-assistant-back',
          onBack: () => { router.back() }
        })
        Scroll() {
          Column({ space: SPACING.LG }) {
            if (!this.loaded) {
              Text(this.busy ? '正在读取服务端配置…' : this.feedback)
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                .id('admin-assistant-load-status')
              Button('重新加载')
                .attributeModifier(new AppButtonStyle()).height(44).enabled(!this.busy)
                .id('admin-assistant-reload').onClick(() => { this.loadConfig() })
            } else {
              Column({ space: SPACING.MD }) {
                Row({ space: SPACING.MD }) {
                  Column({ space: SPACING.XS }) {
                    Text('启用 AI 问答').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT)
                    Text('由服务端调用管理员配置的 API')
                      .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.aiEnabled })
                    .selectedColor(AppTheme.PRIMARY).enabled(!this.busy)
                    .id('admin-assistant-enabled')
                    .onChange((value: boolean) => { this.aiEnabled = value })
                }.width('100%')
                Text('支持兼容 Chat Completions 的接口。关闭 AI 问答后，用户仍可通过助手入口进入相应页面。')
                  .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
              }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')

              Column({ space: SPACING.MD }) {
                Text('接口地址').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
                TextInput({ text: this.endpoint, placeholder: 'https://api.example.com/v1/chat/completions' })
                  .attributeModifier(new AppInputStyle()).width('100%').maxLength(500)
                  .enabled(!this.busy).id('admin-assistant-endpoint')
                  .onChange((value: string) => { this.endpoint = value })
                Text('填写服务商提供的完整 HTTPS 请求地址。')
                  .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
                Text('模型名称').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
                TextInput({ text: this.model, placeholder: '例如：服务商提供的模型 ID' })
                  .attributeModifier(new AppInputStyle()).width('100%').maxLength(100)
                  .enabled(!this.busy).id('admin-assistant-model')
                  .onChange((value: string) => { this.model = value })
                Text('API Key').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT).width('100%')
                Text(this.clearApiKey ? '待清除密钥，保存后生效' : (this.hasApiKey ? '服务端已保存密钥，留空可保留' : '尚未配置密钥'))
                  .fontSize(FONT_SIZE.SM).fontColor(this.clearApiKey ? COLORS.ERROR : AppTheme.MUTED)
                  .width('100%').id('admin-assistant-key-status')
                TextInput({ text: this.apiKey, placeholder: this.hasApiKey ? '输入新密钥以替换，留空保留' : '请输入 API Key' })
                  .attributeModifier(new AppInputStyle()).type(InputType.Password)
                  .showPasswordIcon(false).width('100%').maxLength(4096)
                  .enabled(!this.busy).id('admin-assistant-api-key')
                  .onChange((value: string) => {
                    this.apiKey = value
                    if (value.trim() !== '') { this.clearApiKey = false }
                  })
                Text('密钥仅发送到服务端保存，不在设备上缓存或回显。保存完成后输入框会清空。')
                  .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
                if (this.hasApiKey) {
                  Button(this.clearApiKey ? '取消清除密钥' : '清除已保存密钥')
                    .attributeModifier(new AppButtonStyle()).height(44).width('100%')
                    .fontColor(COLORS.ERROR).backgroundColor(COLORS.ERROR_LIGHT)
                    .enabled(!this.busy).id('admin-assistant-clear-key')
                    .onClick(() => {
                      if (this.clearApiKey) { this.clearApiKey = false }
                      else { this.showClearConfirm = true }
                    })
                }
              }.attributeModifier(new AppCardStyle()).padding(SPACING.LG).width('100%')

              Column({ space: SPACING.MD }) {
                Button('保存并测试连接')
                  .attributeModifier(new AppButtonStyle()).height(48).width('100%')
                  .fontColor(AppTheme.ACCENT).backgroundColor(AppTheme.ACCENT_SOFT)
                  .enabled(!this.busy).id('admin-assistant-test')
                  .onClick(() => { this.saveConfig(true) })
                Text('测试会先保存当前配置，再由服务端请求 API；测试请求可能产生服务商费用。')
                  .fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED).width('100%')
                if (this.feedback !== '') {
                  Text(this.feedback).fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED)
                    .width('100%').id('admin-assistant-feedback')
                }
              }.width('100%')
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XL })
        }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)

        Column() {
          Button(this.busy ? '处理中…' : '保存配置')
            .attributeModifier(new AppButtonStyle()).height(AppTheme.CONTROL_HEIGHT).width('100%')
            .enabled(this.loaded && !this.busy).id('admin-assistant-save')
            .onClick(() => { this.saveConfig() })
        }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
        .backgroundColor(AppTheme.PAGE).border({ width: { top: 1 }, color: AppTheme.BORDER })
      }.width('100%').height('100%').backgroundColor(AppTheme.PAGE)

      if (this.showClearConfirm) {
        ConfirmDialog({
          title: '清除 API Key',
          content: '清除密钥会关闭 AI 问答，保存配置后生效。确定清除吗？',
          confirmText: '确认清除', cancelText: '取消',
          onConfirm: () => {
            this.showClearConfirm = false
            this.clearApiKey = true
            this.apiKey = ''
            this.aiEnabled = false
          },
          onCancel: () => { this.showClearConfirm = false }
        })
      }
    }.width('100%').height('100%')
  }
}
