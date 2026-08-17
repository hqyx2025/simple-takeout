/**
 * 管理端-订单管理页（大纲 9.6 订单管理）
 * 全平台托管订单：按状态筛选、查看托管资金状态、异常订单退款（未完成订单可直接退款）
 * 已送达订单（status=4）需走退款审批流程，不在此直接退款
 */
import { User, UserRole } from '../model/Models'
import { ApiResponse, get, put } from '../service/HttpClient'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { logInfo } from '../service/AppLogger'
import { adminOrderActionApi } from '../service/ApiService'

interface AdminOrder {
  id: number
  orderNo: string
  storeName: string
  status: number
  payAmount: number
  escrowStatus?: number
}

class OrderTabItem {
  title: string = ''
  status: number = -1

  static create(title: string, status: number): OrderTabItem {
    const item: OrderTabItem = new OrderTabItem()
    item.title = title
    item.status = status
    return item
  }
}

@Entry
@Component
export struct AdminOrderPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State orders: AdminOrder[] = []
  // 当前筛选结果：避免 build 阶段依赖 getter 计算属性（ArkUI 对 getter 求值存在时序问题，曾导致渲染崩溃）
  @State displayOrders: AdminOrder[] = []
  @State currentStatus: number = -1
  // 退款二次确认（资金操作必须确认，防止误点）
  @State refundingOrderId: number = 0
  @State showRefundConfirm: boolean = false
  @State actioningOrderId: number = 0

  aboutToAppear(): void {
    logInfo('Page', '进入管理端订单管理页 AdminOrderPage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  async refresh(): Promise<void> {
    const resp: ApiResponse<AdminOrder[]> = await get<AdminOrder[]>('/api/admin/orders')
    this.orders = resp.code === 200 && resp.data !== null ? resp.data : []
    this.applyFilter()
  }

  /** 按当前状态筛选并写入 displayOrders（显式计算，避免渲染期 getter 求值）。 */
  private applyFilter(): void {
    if (!Array.isArray(this.orders)) {
      this.displayOrders = []
      return
    }
    if (this.currentStatus === -1) {
      this.displayOrders = this.orders
      return
    }
    this.displayOrders = this.orders.filter(o => o !== null && typeof o === 'object' && o.status === this.currentStatus)
  }

  /** 切换筛选 Tab。 */
  private onStatusChange(status: number): void {
    this.currentStatus = status
    this.applyFilter()
  }

  /** 托管资金状态文本：0 托管中 / 1 已结算 / 2 已退款。 */
  private getEscrowText(escrowStatus?: number): string {
    if (escrowStatus === 1) {
      return '已结算'
    }
    if (escrowStatus === 2) {
      return '已退款'
    }
    return '托管中'
  }

  private getEscrowColor(escrowStatus?: number): string {
    if (escrowStatus === 1) {
      return COLORS.SUCCESS
    }
    if (escrowStatus === 2) {
      return COLORS.TEXT_HINT
    }
    return COLORS.WARNING
  }

  /** 管理端取消异常订单并退款（仅未完成订单；已送达走退款审批）。 */
  async refund(): Promise<void> {
    const resp: ApiResponse<AdminOrder> = await put<AdminOrder>(`/api/admin/orders/${this.refundingOrderId}/refund`, undefined)
    this.showRefundConfirm = false
    if (resp.code === 200) {
      this.refundingOrderId = 0
      promptAction.showToast({ message: '订单已退款并关闭', duration: 1500 })
      await this.refresh()
    }
  }

  async runOrderAction(orderId: number, action: string, successText: string): Promise<void> {
    this.actioningOrderId = orderId
    const ok: boolean = await adminOrderActionApi(orderId, action)
    this.actioningOrderId = 0
    if (ok) {
      promptAction.showToast({ message: successText, duration: 1400 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '订单操作失败，请刷新后重试', duration: 1600 })
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('‹ 返回')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .onClick(() => { router.back() })
        Text('订单管理')
          .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button('刷新').height(32).fontSize(FONT_SIZE.SM).onClick(() => { this.refresh() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
      .backgroundColor(COLORS.BG_WHITE)

      // 状态筛选 Tab
      Scroll() {
        Row({ space: 0 }) {
          ForEach([
            OrderTabItem.create('全部', -1),
            OrderTabItem.create('待接单', 1),
            OrderTabItem.create('制作中', 2),
            OrderTabItem.create('配送中', 3),
            OrderTabItem.create('已送达', 4),
            OrderTabItem.create('已取消', 5)
          ], (item: OrderTabItem) => {
            Text(item.title)
              .fontSize(FONT_SIZE.MD)
              .fontColor(this.currentStatus === item.status ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
              .fontWeight(this.currentStatus === item.status ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
              .onClick(() => { this.onStatusChange(item.status) })
          }, (item: OrderTabItem) => item.title)
        }
        .padding({ left: SPACING.LG, right: SPACING.LG })
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .width('100%').backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          Text('托管资金：下单即托管，用户确认收货后结算给商户；未完成订单可由平台直接退款')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')

          if (!Array.isArray(this.displayOrders) || this.displayOrders.length === 0) {
            Text('暂无该状态订单').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%').padding(SPACING.MD)
          }
          ForEach(this.displayOrders, (order: AdminOrder) => {
            Row({ space: SPACING.MD }) {
              Column({ space: 4 }) {
                Text(`${order.storeName}  #${order.orderNo}`).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
                Row({ space: SPACING.SM }) {
                  Text(getOrderStatusText(order.status, order.escrowStatus))
                    .fontSize(FONT_SIZE.SM).fontColor(getOrderStatusColor(order.status))
                  Text(`托管：${this.getEscrowText(order.escrowStatus)}`)
                    .fontSize(FONT_SIZE.SM).fontColor(this.getEscrowColor(order.escrowStatus))
                }
                Text(`实付 ¥${(order.payAmount ?? 0).toFixed(2)}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (order.status === 1) {
                Button('接单').height(30).fontSize(FONT_SIZE.XS)
                  .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .enabled(this.actioningOrderId !== order.id)
                  .onClick(() => { this.runOrderAction(order.id, 'accept', '订单已接单') })
                Button('取消').height(30).fontSize(FONT_SIZE.XS)
                  .fontColor(COLORS.ERROR).backgroundColor('#FFF0F0')
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.runOrderAction(order.id, 'cancel', '订单已取消并退款') })
              } else if (order.status === 2) {
                Button('出餐').height(30).fontSize(FONT_SIZE.XS)
                  .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .enabled(this.actioningOrderId !== order.id)
                  .onClick(() => { this.runOrderAction(order.id, 'deliver', '订单已进入配送中') })
                Button('取消').height(30).fontSize(FONT_SIZE.XS)
                  .fontColor(COLORS.ERROR).backgroundColor('#FFF0F0')
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.runOrderAction(order.id, 'cancel', '订单已取消并退款') })
              } else if (order.status === 3) {
                Button('确认送达').height(30).fontSize(FONT_SIZE.XS)
                  .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .enabled(this.actioningOrderId !== order.id)
                  .onClick(() => { this.runOrderAction(order.id, 'complete', '订单已标记送达') })
                Button('取消').height(30).fontSize(FONT_SIZE.XS)
                  .fontColor(COLORS.ERROR).backgroundColor('#FFF0F0')
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.runOrderAction(order.id, 'cancel', '订单已取消并退款') })
              } else if (order.status !== 4 && order.status !== 5) {
                Button('退款').height(34).fontSize(FONT_SIZE.SM)
                  .fontColor(Color.White).backgroundColor(COLORS.ERROR)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => {
                    this.refundingOrderId = order.id
                    this.showRefundConfirm = true
                  })
              }
            }
            .width('100%').padding(SPACING.MD)
            .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
          }, (order: AdminOrder) => order.id.toString())
        }
        .width('100%').padding(SPACING.LG)
      }
      .layoutWeight(1).scrollBar(BarState.Off)

      // 退款二次确认弹窗
      if (this.showRefundConfirm) {
        ConfirmDialog({
          title: '订单退款',
          content: '确定对该订单退款并关闭吗？退款将退回用户余额，商品库存同步回滚。',
          confirmText: '确定退款',
          cancelText: '取消',
          onConfirm: () => { this.refund() },
          onCancel: () => { this.showRefundConfirm = false }
        })
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
