import { FormSelect } from '../FormSelect'
import { Order } from '../../model/Models'
import { fetchOrderDetailApi } from '../../service/api/OrdersApi'
import { canOrderAction, refundDisplayText } from '../../service/OrderStatus'
import { FormInput } from '../../components/FormInput'
import { AppButtonStyle, AppCardStyle } from '../../common/theme/AppTheme'
import { COLORS, SPACING, FONT_SIZE } from '../../common/Constants'
import { PageHeader } from '../../components/PageHeader'
import { EvidenceImages } from '../../components/EvidenceImages'
import { DeliveryIssue, RefundRecord, User, UserRole, createEmptyUser } from '../../model/Models'
import { getAuthSessionEpoch, getApiBaseUrl, getLastApiErrorMessage } from '../../service/HttpClient'
import { routerCompat as router, RouterParamsCompat } from '../../common/UiNavigation'
import { DeliveryIssuePageData, IssueRequest, ResolveIssueRequest, RefundEvidenceRequest, fetchDeliveryIssuesApi, reportDeliveryIssueApi, fetchAdminDeliveryIssuesApi, resolveDeliveryIssueApi, fetchMerchantOrderRefundsApi, submitMerchantEvidenceApi } from '../../service/api/AfterSalesApi'

class IssueType {
  code: string
  label: string
  constructor(code: string, label: string) { this.code = code; this.label = label }
}

@Component
export struct OrderIssueContent {
  @Prop platform: boolean = false
  @Prop @Watch('onVisibility') visible: boolean = true
  @State selectedIssue: DeliveryIssue | null = null
  @State resolution: string = 'RESUME'
  @StorageLink('user') @Watch('onIdentityChange') user: User = createEmptyUser()
  @StorageLink('isLoggedIn') @Watch('onIdentityChange') loggedIn: boolean = false
  @State issues: DeliveryIssue[] = []
  @State refunds: RefundRecord[] = []
  @State loading: boolean = false
  @State busy: boolean = false
  @State errorText: string = ''
  @State feedback: string = ''
  @State issueType: string = 'OTHER'
  @State note: string = ''
  @State issueLocked: boolean = false
  @State evidenceRefundId: number = 0
  @State evidenceResponse: string = ''
  @State evidenceImages: string[] = []
  @State evidenceUploading: boolean = false
  @State mode: string = ''
  @State page: number = 1
  @State hasMore: boolean = false
  private orderId: number = 0
  private canReport: boolean = false
  private owner: number = 0
  private role: UserRole = UserRole.CUSTOMER
  private epoch: number = 0
  private active: boolean = true
  private pageVersion: number = 0
  private requestVersion: number = 0
  private pendingIssue: IssueRequest | null = null
  private types: IssueType[] = [new IssueType('NO_RIDER', '长时间无骑手'), new IssueType('CUSTOMER_UNREACHABLE', '无法联系用户'),
    new IssueType('ADDRESS_PROBLEM', '地址异常'), new IssueType('FOOD_DAMAGED', '餐品损坏'), new IssueType('OTHER', '其他')]

  aboutToAppear(): void {
    const params: RouterParamsCompat = router.getParams() ?? {}
    this.orderId = params.orderId ?? 0
    this.owner = this.user.id
    this.role = this.user.role
    this.epoch = getAuthSessionEpoch()
    if (!this.loggedIn || (this.platform ? this.role !== UserRole.ADMIN : this.role === UserRole.ADMIN || this.orderId <= 0)) {
      router.replaceUrl({ url: 'pages/Index' }); return
    }
    this.load()
  }

  onPageShow(): void { this.active = true; this.load() }
  onPageHide(): void { this.active = false; this.pageVersion += 1; this.requestVersion += 1; this.loading = false; this.busy = false; this.evidenceUploading = false }
  aboutToDisappear(): void { this.onPageHide() }
  onIdentityChange(): void {
    if (this.owner > 0 && (!this.loggedIn || this.owner !== this.user.id || this.role !== this.user.role)) {
      this.onPageHide()
      this.issues = []; this.refunds = []; this.evidenceImages = []; this.evidenceResponse = ''; this.note = ''
      router.back()
    }
  }

  private current(version: number): boolean {
    return this.active && this.loggedIn && this.owner === this.user.id && this.role === this.user.role
      && this.epoch === getAuthSessionEpoch() && version === this.pageVersion
  }

  private async load(page: number = 1, append: boolean = false): Promise<void> {
    const version: number = this.pageVersion
    if (!this.current(version) || (this.loading && append)) { return }
    const request: number = ++this.requestVersion
    this.loading = true
    this.errorText = ''
    try {
      if (this.platform) {
        const result: DeliveryIssuePageData | null = await fetchAdminDeliveryIssuesApi(page)
        if (!this.current(version) || request !== this.requestVersion) { return }
        if (result === null) { this.errorText = '异常记录读取失败，已保留已有数据，请重试'; return }
        this.issues = append ? this.issues.concat(result.list) : result.list
        this.page = result.page
        this.hasMore = result.hasMore
      } else if (this.orderId > 0) {
        const order: Order | null = await fetchOrderDetailApi(this.orderId, false)
        if (!this.current(version) || request !== this.requestVersion) { return }
        if (order === null) { this.canReport = false; this.errorText = '订单读取失败或无权访问，请重试'; return }
        this.canReport = canOrderAction(order, 'REPORT_ISSUE', order.status === 2 || order.status === 3)
        const result: DeliveryIssue[] | null = await fetchDeliveryIssuesApi(this.orderId, this.role)
        if (!this.current(version) || request !== this.requestVersion) { return }
        if (result === null) { this.errorText = '配送异常读取失败，请重试' } else { this.issues = result }
        if (this.role === UserRole.MERCHANT) {
          const records: RefundRecord[] | null = await fetchMerchantOrderRefundsApi(this.orderId)
          if (!this.current(version) || request !== this.requestVersion) { return }
          if (records === null) { this.errorText = '售后记录读取失败，请重试' } else { this.refunds = records }
        }
      }
    } catch (_) {
      if (this.current(version) && request === this.requestVersion) { this.errorText = '读取失败，已保留数据，请重试' }
    } finally {
      if (this.current(version) && request === this.requestVersion) { this.loading = false }
    }
  }

  private async report(): Promise<void> {
    const version: number = this.pageVersion
    if (!this.current(version) || this.busy || !this.canReport || this.orderId <= 0) { return }
    if (this.note.trim() === '') { this.errorText = '请填写异常说明'; return }
    if (this.pendingIssue === null) {
      this.pendingIssue = { type: this.issueType, note: this.note.trim(), idempotencyKey: 'issue-' + this.orderId.toString() + '-' + Date.now().toString(36) + '-' + Math.random().toString(36).substring(2, 10) }
    }
    this.issueLocked = true
    this.busy = true
    const ok: boolean = await reportDeliveryIssueApi(this.orderId, this.role, this.pendingIssue)
    if (!this.current(version)) { return }
    this.busy = false
    if (!ok) { this.errorText = getLastApiErrorMessage() || '结果暂未确认，请重试核对同一次上报'; return }
    this.pendingIssue = null; this.issueLocked = false; this.note = ''; this.feedback = '异常已上报，平台将跟进处理'
    await this.load()
  }

  private async resolve(issue: DeliveryIssue, action: string): Promise<void> {
    const version: number = this.pageVersion
    if (!this.current(version) || this.busy || this.role !== UserRole.ADMIN) { return }
    if (this.note.trim() === '') { this.errorText = '请先填写处理说明'; return }
    this.busy = true
    const request: ResolveIssueRequest = { action: action, note: this.note.trim() }
    const ok: boolean = await resolveDeliveryIssueApi(issue.id, request)
    if (!this.current(version)) { return }
    this.busy = false
    if (!ok) { this.errorText = getLastApiErrorMessage() || '处理失败，请重试'; return }
    this.feedback = '异常已处理'; this.note = ''; this.selectedIssue = null; await this.load()
  }

  private async submitEvidence(): Promise<void> {
    const version: number = this.pageVersion
    if (!this.current(version) || this.busy || this.evidenceUploading || this.evidenceRefundId <= 0) { return }
    if (this.evidenceResponse.trim() === '') { this.errorText = '请填写商家说明'; return }
    this.busy = true
    const request: RefundEvidenceRequest = { response: this.evidenceResponse.trim(), evidenceImages: this.evidenceImages }
    const ok: boolean = await submitMerchantEvidenceApi(this.evidenceRefundId, request)
    if (!this.current(version)) { return }
    this.busy = false
    if (!ok) { this.errorText = getLastApiErrorMessage() || '举证提交失败，请重试'; return }
    this.feedback = '举证已提交，由平台审核'; this.evidenceRefundId = 0; this.evidenceImages = []; this.evidenceResponse = ''; await this.load()
  }

  private issueTypeLabel(code: string): string {
    return this.types.find((item: IssueType) => item.code === code)?.label ?? '其他'
  }

  private refundStatusLabel(status: string): string {
    return refundDisplayText(status)
  }

  private resolutionOptions: SelectOption[] = [{ value: '恢复配送' }, { value: '重新分配骑手' }, { value: '取消订单并退款' }]
  private resolutionLabel(): string { return this.resolution === 'CANCEL' ? '取消订单并退款' : this.resolution === 'REASSIGN' ? '重新分配骑手' : '恢复配送' }
  onVisibility(): void { if (this.visible) { this.onPageShow() } else { this.onPageHide() } }
  private async confirmResolve(): Promise<void> {
    if (this.selectedIssue === null || this.busy || this.note.trim() === '') { this.errorText = '请选择异常并填写处理说明'; return }
    const issue: DeliveryIssue = this.selectedIssue
    const action: string = this.resolution
    const version: number = this.pageVersion
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '确认处理异常',
        message: '#' + issue.orderId + '：' + this.resolutionLabel(),
        buttons: [{ text: '取消', color: COLORS.TEXT_SECONDARY }, { text: '确认处理', color: COLORS.PRIMARY }] })
      if (choice.index === 1 && this.current(version)) { await this.resolve(issue, action) }
    } catch (_) {}
  }

  build() {
    Column() {
      PageHeader({ title: this.platform ? '平台异常处理' : '订单异常与记录',
        onBack: () => { router.back() }, actionLabel: '刷新', onAction: () => { if (!this.busy) { this.load() } } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          if (this.errorText !== '') {
            Text(this.errorText).fontColor(COLORS.ERROR).fontSize(FONT_SIZE.SM)
            Button('重试加载').attributeModifier(new AppButtonStyle()).enabled(!this.loading && !this.busy).onClick(() => { this.load() })
          }
          if (this.feedback !== '') { Text(this.feedback).fontColor(COLORS.SUCCESS).fontSize(FONT_SIZE.SM) }
            if (this.canReport || this.role === UserRole.ADMIN) {
              if (this.role !== UserRole.ADMIN) {
                ForEach(this.types, (item: IssueType) => { this.TypeButton(item) }, (item: IssueType) => item.code)
              }
              if (this.platform && this.selectedIssue !== null) {
                Text('处理订单 #' + this.selectedIssue.orderId).fontColor(COLORS.TEXT_PRIMARY)
                FormSelect({ label: '处理方式', options: this.resolutionOptions, selected: this.resolutionOptions.findIndex((item: SelectOption) => item.value === this.resolutionLabel()),
                  isEnabled: !this.busy, onSelect: (index: number) => { this.resolution = ['RESUME', 'REASSIGN', 'CANCEL'][index] } })
              }
              Text(this.role === UserRole.ADMIN ? '处理说明（必填）' : '异常说明（必填）').fontColor(COLORS.TEXT_PRIMARY)
              FormInput({ label: '情况说明',
                value: this.note,
                placeholder: '请说明实际情况，最多500字',
                maxLength: 500,
                isEnabled: !this.busy && !this.issueLocked,
                onChange: (value: string) => { this.note = value },
                fieldId: 'OrderSupportPage-note',
                multiline: true,
                inputHeight: 100,
                required: true })
            }
            Text('配送异常历史').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
            if (!this.loading && this.errorText === '' && this.issues.length === 0) { Text('暂无配送异常记录').fontColor(COLORS.TEXT_HINT) }
            ForEach(this.issues, (issue: DeliveryIssue) => { this.IssueCard(issue) }, (issue: DeliveryIssue) => issue.id.toString() + '-' + issue.status)
            if (this.hasMore) {
              Button('加载更多异常').attributeModifier(new AppButtonStyle()).enabled(!this.loading && !this.busy).onClick(() => { this.load(this.page + 1, true) })
            }
            ForEach(this.refunds, (record: RefundRecord) => { this.RefundCard(record) }, (record: RefundRecord) => record.id.toString() + '-' + record.status + '-' + (record.merchantResponse ?? ''))
            if (this.evidenceRefundId > 0) {

              FormInput({ label: '举证说明',
                value: this.evidenceResponse,
                placeholder: '例如：已补送餐品，并附实际照片',
                maxLength: 500,
                isEnabled: !this.busy,
                onChange: (value: string) => { this.evidenceResponse = value },
                fieldId: 'OrderSupportPage-evidenceResponse',
                multiline: true,
                inputHeight: 100,
                required: true })
              EvidenceImages({ images: $evidenceImages, uploading: $evidenceUploading, disabled: this.busy, contextVersion: (): number => this.pageVersion })
            }
        }.width('100%').padding(SPACING.LG).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
      if (this.evidenceRefundId > 0) {
        Button('提交商家举证').attributeModifier(new AppButtonStyle()).width('100%').height(44)
          .enabled(!this.busy && !this.evidenceUploading).onClick(() => { this.submitEvidence() })
      } else if (this.platform && this.selectedIssue !== null) {
        Button(this.busy ? '处理中…' : '确认处理').attributeModifier(new AppButtonStyle()).width('100%').height(44)
          .enabled(!this.busy).id('admin-issue-resolve').onClick(() => { this.confirmResolve() })
      } else if (this.canReport) {
        Button(this.busy ? '提交中…' : this.issueLocked ? '重试核对上报' : '上报配送异常').attributeModifier(new AppButtonStyle()).width('100%').height(44)
          .enabled(!this.busy).id('delivery-issue-submit').onClick(() => { this.report() })
      }
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  TypeButton(item: IssueType) {
    Button((this.issueType === item.code ? '✓ ' : '') + item.label).attributeModifier(new AppButtonStyle())
      .enabled(!this.busy && !this.issueLocked).onClick(() => { this.issueType = item.code })
  }

  @Builder
  IssueCard(issue: DeliveryIssue) {
    Column({ space: SPACING.SM }) {
      Text('#' + issue.orderId.toString() + ' ' + this.issueTypeLabel(issue.type) + ' · ' + (issue.status === 'OPEN' ? '处理中' : '已处理')).fontColor(COLORS.TEXT_PRIMARY)
      Text(issue.note).fontColor(COLORS.TEXT_SECONDARY)
      Text(issue.createTime).fontColor(COLORS.TEXT_HINT)
      if ((issue.resolveNote ?? '') !== '') { Text(issue.resolveNote ?? '').fontColor(COLORS.TEXT_SECONDARY) }
      if (this.role === UserRole.ADMIN && issue.status === 'OPEN') {
        Button('处理此异常').attributeModifier(new AppButtonStyle()).enabled(!this.busy)
          .onClick(() => { this.selectedIssue = issue; this.note = '' })

      }
    }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD).alignItems(HorizontalAlign.Start)
  }

  @Builder
  RefundCard(record: RefundRecord) {
    Column({ space: SPACING.SM }) {
      Text('售后 #' + record.id.toString() + ' ¥' + record.amount.toFixed(2) + ' · ' + this.refundStatusLabel(record.status)).fontColor(COLORS.TEXT_PRIMARY)
      Text(record.reason).fontColor(COLORS.TEXT_SECONDARY)
      Text('商家说明：' + (record.merchantResponse ?? '未提交')).fontColor(COLORS.TEXT_SECONDARY)
      ForEach(record.evidenceImages ?? [], (url: string) => {
        Image(getApiBaseUrl() + url).width(80).height(80).objectFit(ImageFit.Cover)
      }, (url: string) => url)
      if (record.status === 'PENDING') {
        Button('为此申请举证').attributeModifier(new AppButtonStyle()).enabled(!this.busy && !this.evidenceUploading)
          .onClick(() => { this.evidenceRefundId = record.id; this.evidenceResponse = record.merchantResponse ?? ''; this.evidenceImages = record.merchantEvidenceImages ?? [] })
      }
    }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD).alignItems(HorizontalAlign.Start)
  }
}
