import { AppButtonStyle, AppCardStyle, AppTextAreaStyle } from '../common/theme/AppTheme'
/**
 * 管理端-退款审批页（大纲 9.7 退款处理）
 * 已送达订单退款审批：原渠道退款或拒绝并恢复已送达，不恢复餐品库存。
 */
import { AppMotion } from '../common/theme/AppMotion'
import { User, UserRole, RefundRecord, RefundPageData } from '../model/Models'
import { fetchAdminRefundsPageApi, approveRefundApi, rejectRefundApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg } from '../common/Constants'
import { StatusBadge } from '../components/StatusBadge'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'
import { getAuthSessionEpoch } from '../service/HttpClient'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { fetchAdminRefundDetailApi } from '../service/api/AdminApi'

@Entry
@Component
export struct AdminRefundPage {
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
  @StorageLink('user') @Watch('onSessionChanged') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State refunds: RefundRecord[] = []
  @State loading: boolean = false
  @State page: number = 1
  @State total: number = 0
  @State hasMore: boolean = false
  @State statusFilter: string = 'PENDING'
  @State loadFailed: boolean = false
  @State submitting: boolean = false
  @State actionError: string = ''
  @State approvingRefund: RefundRecord | null = null
  @State showRejectDialog: boolean = false
  @State rejectingRefundId: number = 0
  @State rejectReason: string = ''
  private pageActive: boolean = false
  private requestSerial: number = 0
  private ownerId: number = 0

  aboutToAppear(): void {
    logInfo('Page', '进入管理端退款审批页 AdminRefundPage')
    this.ownerId = this.user.id
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
  }

  private onSessionChanged(): void {
    if (this.loggedIn && this.user.role === UserRole.ADMIN && this.user.id === this.ownerId) { return }
    const wasActive: boolean = this.pageActive
    this.pageActive = false
    this.requestSerial += 1
    this.refunds = []
    this.total = 0
    this.hasMore = false
    this.loading = false
    this.submitting = false
    this.approvingRefund = null
    this.showRejectDialog = false
    this.rejectReason = ''
    this.rejectingRefundId = 0
    this.actionError = ''
    if (wasActive) { router.replaceUrl({ url: 'pages/Index' }) }
  }

  onPageShow(): void {
    this.pageActive = true
    if (this.loggedIn && this.user.role === UserRole.ADMIN) {
      this.refresh()
    }
  }

  onPageHide(): void {
    this.pageActive = false
    this.requestSerial += 1
    this.loading = false
    this.approvingRefund = null
    this.showRejectDialog = false
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.requestSerial += 1
  }

  onBackPress(): boolean {
    if (this.submitting) { return true }
    if (this.approvingRefund !== null || this.showRejectDialog) {
      this.approvingRefund = null
      this.showRejectDialog = false
      return true
    }
    return false
  }

  private canApplyResponse(epoch: number): boolean {
    return this.pageActive && this.loggedIn && this.user.role === UserRole.ADMIN &&
      epoch === getAuthSessionEpoch()
  }

  async refresh(): Promise<void> {
    if (!this.pageActive || !this.loggedIn || this.user.role !== UserRole.ADMIN || this.loading || this.submitting) { return }
    this.loading = true
    const epoch: number = getAuthSessionEpoch()
    const serial: number = ++this.requestSerial
    const result: RefundPageData | null = await fetchAdminRefundsPageApi(this.statusFilter, 1)
    if (!this.canApplyResponse(epoch) || serial !== this.requestSerial) { return }
    this.loading = false
    this.loadFailed = result === null
    if (result === null) { return }
    this.page = result.page
    this.refunds = result.list
    this.total = result.total
    this.hasMore = result.hasMore
  }

  private async loadMore(): Promise<void> {
    if (this.loading || this.submitting || !this.hasMore) {
      return
    }
    this.loading = true
    const epoch: number = getAuthSessionEpoch()
    const serial: number = ++this.requestSerial
    const result: RefundPageData | null = await fetchAdminRefundsPageApi(this.statusFilter, this.page + 1)
    if (!this.canApplyResponse(epoch) || serial !== this.requestSerial) { return }
    this.loading = false
    this.loadFailed = result === null
    if (result === null) { return }
    this.refunds = this.refunds.concat(result.list)
    this.page = result.page
    this.total = result.total
    this.hasMore = result.hasMore
  }

  private changeFilter(status: string): void {
    if (this.loading || this.submitting || this.statusFilter === status) { return }
    this.statusFilter = status
    this.refunds = []
    this.total = 0
    this.hasMore = false
    this.refresh()
  }

  async doApproveRefund(): Promise<void> {
    if (!this.pageActive || !this.loggedIn || this.user.role !== UserRole.ADMIN || this.submitting || this.approvingRefund === null) { return }
    const record: RefundRecord = this.approvingRefund
    const epoch: number = getAuthSessionEpoch()
    this.submitting = true
    this.actionError = ''
    const ok: boolean = await approveRefundApi(record.id)
    const latest: RefundRecord | null = !ok && this.canApplyResponse(epoch)
      ? await fetchAdminRefundDetailApi(record.id) : null
    this.submitting = false
    if (!this.canApplyResponse(epoch)) { return }
    if (ok || latest?.status === 'REFUNDED') {
      this.approvingRefund = null
      promptAction.showToast({ message: `已同意退款 ¥${record.amount.toFixed(2)}，款项已按原支付渠道退回`, duration: 1800 })
      await this.refresh()
    } else {
      this.approvingRefund = null
      this.actionError = latest?.status === 'REJECTED'
        ? `该申请已被拒绝：${latest.rejectReason ?? '请查看退款记录'}。未再次退款。`
        : '未能确认审批结果，请刷新列表核对后再操作。'
      await this.refresh()
    }
  }

  async doRejectRefund(): Promise<void> {
    if (!this.pageActive || !this.loggedIn || this.user.role !== UserRole.ADMIN || this.submitting) { return }
    if (this.rejectReason.trim() === '') {
      promptAction.showToast({ message: '请填写拒绝原因', duration: 1500 })
      return
    }
    const epoch: number = getAuthSessionEpoch()
    this.submitting = true
    this.actionError = ''
    const ok: boolean = await rejectRefundApi(this.rejectingRefundId, this.rejectReason.trim())
    const latest: RefundRecord | null = !ok && this.canApplyResponse(epoch)
      ? await fetchAdminRefundDetailApi(this.rejectingRefundId) : null
    this.submitting = false
    if (!this.canApplyResponse(epoch)) { return }
    if (ok || latest?.status === 'REJECTED') {
      this.showRejectDialog = false
      this.rejectReason = ''
      promptAction.showToast({ message: '已拒绝退款申请，订单恢复为已送达', duration: 1800 })
      await this.refresh()
    } else if (latest?.status === 'REFUNDED') {
      this.showRejectDialog = false
      this.actionError = '该申请已退款，请查看最新记录。'
      await this.refresh()
    } else {
      this.actionError = '未能确认处理结果，理由已保留。可取消后刷新核对，或重试提交。'
    }
  }

  private reasonTypeLabel(code: string): string {
    switch (code) {
      case 'NOT_RECEIVED': return '未收到餐'
      case 'QUALITY_ISSUE': return '餐品质量问题'
      case 'WRONG_ITEM': return '商品不符'
      case 'DONOT_WANT': return '不想要了'
      default: return '其他'
    }
  }

  private getRefundStatusText(status: string): string {
    if (status === 'PENDING') {
      return '待审批'
    }
    if (status === 'REFUNDED') {
      return '已退款'
    }
    if (status === 'REJECTED') {
      return '已拒绝'
    }
    if (status === 'APPROVED') { return '退款处理中' }
    return '状态待确认'
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        PageHeader({
          title: '退款审批',
          backId: 'admin-refund-back',
          headerBgColor: COLORS.BG_PRIMARY,
          actionColor: MODULE_COLOR.ADMIN,
          actionLabel: this.loading ? '加载中…' : '刷新',
          onBack: () => { if (!this.submitting) { router.back() } },
          onAction: () => { this.refresh() }
        })

        Row({ space: SPACING.SM }) {
          Button('待审批')
            .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44)
            .fontColor(this.statusFilter === 'PENDING' ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
            .backgroundColor(this.statusFilter === 'PENDING' ? MODULE_COLOR.ADMIN : COLORS.BG_CARD)
            .enabled(!this.loading && !this.submitting).id('admin-refund-pending')
            .onClick(() => { this.changeFilter('PENDING') })
          Button('全部记录')
            .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(44)
            .fontColor(this.statusFilter === '' ? COLORS.ON_PRIMARY : COLORS.TEXT_PRIMARY)
            .backgroundColor(this.statusFilter === '' ? MODULE_COLOR.ADMIN : COLORS.BG_CARD)
            .enabled(!this.loading && !this.submitting).id('admin-refund-all')
            .onClick(() => { this.changeFilter('') })
        }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM })

        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
        List({ space: SPACING.MD }) {
          ListItem() {
            Text('同意后按原支付渠道退款；已送达餐品不恢复库存。拒绝理由会展示给用户，订单恢复为已送达。')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
          }

          if (this.loadFailed) {
            ListItem() {
              Column({ space: SPACING.SM }) {
                Text(this.refunds.length > 0 ? '加载失败，已保留当前列表' : '退款记录暂时未能加载')
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY)
                Button('重新加载')
                  .attributeModifier(new AppButtonStyle()).height(44)
                  .enabled(!this.loading && !this.submitting).id('admin-refund-retry')
                  .onClick(() => { this.refresh() })
              }.width('100%').padding(SPACING.MD)
            }
          } else if (this.refunds.length === 0) {
            ListItem() {
              Text(this.loading ? '正在加载退款记录…' : this.statusFilter === 'PENDING' ? '暂无待审批退款' : '暂无退款申请')
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%').padding(SPACING.MD)
            }
          }
          if (this.actionError !== '' && !this.showRejectDialog) {
            ListItem() {
              Text(this.actionError).fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR).width('100%')
            }
          }
          ForEach(this.refunds, (record: RefundRecord) => {
            ListItem() {
              Column({ space: SPACING.SM }) {
                Row({ space: SPACING.SM }) {
                  Text('退')
                    .width(36).height(36).textAlign(TextAlign.Center)
                    .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
                    .fontColor(accentFg(record.id)).backgroundColor(accentBg(record.id))
                    .borderRadius(BORDER_RADIUS.ROUND)
                  Column({ space: SPACING.XS }) {
                    Text(`退款单 #${record.id}  订单 #${record.orderId}`).fontSize(FONT_SIZE.MD)
                      .fontColor(COLORS.TEXT_PRIMARY)
                    Text(`金额 ¥${record.amount.toFixed(2)}  申请时间 ${record.applyTime}`).fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.TEXT_SECONDARY)
                    Text(`类型：${this.reasonTypeLabel(record.reasonType)}`).fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.TEXT_SECONDARY)
                    if (record.reason !== '') {
                      Text(`申请说明：${record.reason}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                    }
                    if ((record.processTime ?? '') !== '') {
                      Text(`处理时间：${record.processTime ?? ''}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                    }
                    if (record.status === 'REJECTED' && (record.rejectReason ?? '') !== '') {
                      Text(`拒绝原因：${record.rejectReason ?? ''}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
                    }
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  StatusBadge({ text: this.getRefundStatusText(record.status), mode: record.status === 'REFUNDED' ? 'success' : record.status === 'REJECTED' ? 'error' : 'warning' })
                }.width('100%')
                if (record.status === 'PENDING') {
                  Row({ space: SPACING.SM }) {
                    Button('同意退款')
                      .attributeModifier(new AppButtonStyle())
                      .layoutWeight(1).height(44).fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.ON_PRIMARY).backgroundColor(COLORS.SUCCESS)
                      .borderRadius(BORDER_RADIUS.ROUND)
                      .enabled(!this.submitting && !this.loading).id(`admin-refund-approve-${record.id}`)
                      .onClick(() => { this.actionError = ''; this.approvingRefund = record })
                    Button('拒绝')
                      .attributeModifier(new AppButtonStyle())
                      .layoutWeight(1).height(44).fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.ERROR).backgroundColor(COLORS.ERROR_LIGHT)
                      .borderRadius(BORDER_RADIUS.ROUND)
                      .enabled(!this.submitting && !this.loading).id(`admin-refund-reject-${record.id}`)
                      .onClick(() => {
                        if (this.rejectingRefundId !== record.id) { this.rejectReason = '' }
                        this.rejectingRefundId = record.id
                        this.actionError = ''
                        this.showRejectDialog = true
                      })
                  }.width('100%')
                }
              }
                .attributeModifier(new AppCardStyle())
              .width('100%').padding(SPACING.MD)
            }
          }, (record: RefundRecord) => `${record.id}-${record.status}-${record.processTime ?? ''}-${record.rejectReason ?? ''}`)
          ListItem() {
            Row({ space: SPACING.SM }) {
              Text(`已显示 ${this.refunds.length} / ${this.total}`)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
              if (this.hasMore) {
                Button(this.loading ? '加载中' : '加载更多')
                  .attributeModifier(new AppButtonStyle()).height(44).fontSize(FONT_SIZE.XS)
                  .enabled(!this.loading && !this.submitting).id('admin-refund-load-more').onClick(() => { this.loadMore() })
              }
            }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.MD })
          }
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
      }
      .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

      if (this.approvingRefund !== null) {
        ConfirmDialog({
          title: '确认同意退款',
          content: `退款单 #${this.approvingRefund.id}，订单 #${this.approvingRefund.orderId}。同意后 ¥${this.approvingRefund.amount.toFixed(2)} 将按原支付渠道退回，已送达餐品不恢复库存。请核对后确认。`,
          confirmText: '确认退款', cancelText: '暂不处理',
          onConfirm: () => { this.doApproveRefund() },
          onCancel: () => { if (!this.submitting) { this.approvingRefund = null } }
        })
      }

      // 拒绝退款原因输入弹窗
      if (this.showRejectDialog) {
        Column() {
          Column({ space: SPACING.MD }) {
            Text(`拒绝退款单 #${this.rejectingRefundId}`)
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Scroll() {
              Column({ space: SPACING.MD }) {
                Text('拒绝理由将展示给用户（必填）。请说明核实结果与处理依据，拒绝后订单恢复为已送达。')
                  .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextArea({ placeholder: '例：已核实配送记录，请补充未收到餐的具体情况后重新申请', text: this.rejectReason })
                  .attributeModifier(new AppTextAreaStyle())
                  .width('100%').height(100)
                  .maxLength(255).enabled(!this.submitting).id('admin-refund-reject-reason')
                  .onChange((value: string) => { this.rejectReason = value })
                if (this.actionError !== '') {
                  Text(this.actionError).fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
            Row({ space: SPACING.MD }) {
              Button('取消')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1).height(44).fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.submitting)
                .onClick(() => { this.showRejectDialog = false })
              Button(this.submitting ? '正在提交…' : '确认拒绝')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1).height(44).fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.ON_PRIMARY).backgroundColor(COLORS.ERROR)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.submitting && this.rejectReason.trim() !== '').id('admin-refund-reject-confirm')
                .onClick(() => { this.doRejectRefund() })
            }
          }
            .attributeModifier(new AppCardStyle())
          .width('90%').height('70%').constraintSize({ maxWidth: 460, maxHeight: 520 })
          .padding(SPACING.XL)
        }
        .width('100%').height('100%')
        .backgroundColor(COLORS.OVERLAY)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      if (this.submitting && !this.showRejectDialog) {
        Column({ space: SPACING.MD }) {
          LoadingProgress().width(40).height(40).color(COLORS.PRIMARY)
          Text('正在提交审批，请稍候…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
        }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
          .justifyContent(FlexAlign.Center).onClick(() => {})
      }
    }
    .width('100%').height('100%')
  }
}
