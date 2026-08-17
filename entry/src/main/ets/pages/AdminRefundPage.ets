/**
 * 管理端-退款审批页（大纲 9.7 退款处理）
 * 用户申请退款（已送达订单）的审批：同意退款（escrow 0→2 + 退用户余额 + 回滚库存）或拒绝（订单恢复已送达）
 */
import { User, UserRole, RefundRecord } from '../model/Models'
import { fetchAdminRefundsApi, approveRefundApi, rejectRefundApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct AdminRefundPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State refunds: RefundRecord[] = []
  @State loading: boolean = false
  // 拒绝退款原因输入
  @State showRejectDialog: boolean = false
  @State rejectingRefundId: number = 0
  @State rejectReason: string = ''

  aboutToAppear(): void {
    logInfo('Page', '进入管理端退款审批页 AdminRefundPage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  async refresh(): Promise<void> {
    if (this.loading) {
      promptAction.showToast({ message: '退款数据正在刷新，请稍候', duration: 1200 })
      return
    }
    this.loading = true
    this.refunds = await fetchAdminRefundsApi()
    this.loading = false
  }

  async doApproveRefund(record: RefundRecord): Promise<void> {
    const ok: boolean = await approveRefundApi(record.id)
    if (ok) {
      promptAction.showToast({ message: `已同意退款 ¥${record.amount.toFixed(2)}，金额退回用户余额`, duration: 1800 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '退款审批失败，请刷新后重试', duration: 1800 })
    }
  }

  async doRejectRefund(): Promise<void> {
    if (this.rejectReason.trim() === '') {
      promptAction.showToast({ message: '请填写拒绝原因', duration: 1500 })
      return
    }
    const ok: boolean = await rejectRefundApi(this.rejectingRefundId, this.rejectReason.trim())
    this.showRejectDialog = false
    this.rejectReason = ''
    if (ok) {
      promptAction.showToast({ message: '已拒绝退款申请，订单恢复为已送达', duration: 1800 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '拒绝退款失败，请刷新后重试', duration: 1800 })
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
    return status
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text('‹ 返回')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
            .onClick(() => { router.back() })
          Text('退款审批')
            .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
          Button(this.loading ? '加载中…' : '刷新').height(32).fontSize(FONT_SIZE.SM)
            .onClick(() => { this.refresh() })
        }
        .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
        .backgroundColor(COLORS.BG_WHITE)

        Scroll() {
          Column({ space: SPACING.MD }) {
            Text('同意退款后：托管款退回用户余额、商品库存回滚；拒绝后订单恢复为已送达')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')

            if (this.refunds.length === 0) {
              Text('暂无退款申请').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%').padding(SPACING.MD)
            }
            ForEach(this.refunds, (record: RefundRecord) => {
              Column({ space: SPACING.SM }) {
                Row() {
                  Column({ space: 4 }) {
                    Text(`退款单 #${record.id}  订单 #${record.orderId}`).fontSize(FONT_SIZE.MD)
                      .fontColor(COLORS.TEXT_PRIMARY)
                    Text(`金额 ¥${record.amount.toFixed(2)}  申请时间 ${record.applyTime}`).fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.TEXT_SECONDARY)
                    if (record.reason !== '') {
                      Text(`原因：${record.reason}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                    }
                    if (record.status === 'REJECTED' && record.rejectReason !== '') {
                      Text(`拒绝原因：${record.rejectReason}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
                    }
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text(this.getRefundStatusText(record.status)).fontSize(FONT_SIZE.SM)
                    .fontColor(record.status === 'REFUNDED' ? COLORS.SUCCESS
                      : record.status === 'REJECTED' ? COLORS.ERROR : COLORS.WARNING)
                }.width('100%')
                if (record.status === 'PENDING') {
                  Row({ space: SPACING.SM }) {
                    Button('同意退款')
                      .layoutWeight(1).height(34).fontSize(FONT_SIZE.SM)
                      .fontColor(Color.White).backgroundColor(COLORS.SUCCESS)
                      .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                      .onClick(() => { this.doApproveRefund(record) })
                    Button('拒绝')
                      .layoutWeight(1).height(34).fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.ERROR).backgroundColor('#FFF0F0')
                      .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                      .onClick(() => {
                        this.rejectingRefundId = record.id
                        this.rejectReason = ''
                        this.showRejectDialog = true
                      })
                  }.width('100%')
                }
              }
              .width('100%').padding(SPACING.MD)
              .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
            }, (record: RefundRecord) => record.id.toString())
          }
          .width('100%').padding(SPACING.LG)
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

      // 拒绝退款原因输入弹窗
      if (this.showRejectDialog) {
        Column() {
          Column({ space: SPACING.MD }) {
            Text('拒绝退款')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Text('请填写拒绝原因（必填），拒绝后订单将恢复为已送达状态')
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
            TextArea({ placeholder: '如：商品已送达且无质量问题', text: this.rejectReason })
              .width('100%').height(80).fontSize(FONT_SIZE.MD)
              .borderRadius(BORDER_RADIUS.MD).backgroundColor(COLORS.BG_PRIMARY)
              .onChange((value: string) => { this.rejectReason = value })
            Row({ space: SPACING.MD }) {
              Button('取消')
                .layoutWeight(1).height(42).fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY).backgroundColor('#F5F5F5')
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .onClick(() => { this.showRejectDialog = false })
              Button('确认拒绝')
                .layoutWeight(1).height(42).fontSize(FONT_SIZE.MD)
                .fontColor(Color.White).backgroundColor(COLORS.ERROR)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .onClick(() => { this.doRejectRefund() })
            }
          }
          .width('90%')
          .padding(SPACING.XL)
          .backgroundColor(Color.White)
          .borderRadius(BORDER_RADIUS.XL)
        }
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%')
  }
}
