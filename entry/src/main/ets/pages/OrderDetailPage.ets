/**
 * 订单详情页
 * 展示订单状态时间轴、店铺与商品、配送信息、金额明细、订单信息
 * 根据订单状态显示对应操作按钮（取消订单 / 确认收货 / 再来一单 / 去评价）
 */
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, getOrderStatusColor } from '../common/Constants'
import { Order, CartItem, DeliveryStep } from '../model/Models'
import { getDeliverySteps } from '../service/MockDataService'
import { cancelOrder, confirmOrder } from '../service/AppStorageManager'
import { OrderStatusTimeline } from '../components/OrderStatusTimeline'
import { ConfirmDialog } from '../components/ConfirmDialog'

@Component
export struct OrderDetailPage {
  @State order: Order | null = null
  @State showCancelDialog: boolean = false
  @State showConfirmDialog: boolean = false
  orderId: number = 0
  onBack: () => void = () => {}
  onReview: (orderId: number) => void = () => {}

  aboutToAppear() {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    this.order = orders.find(o => o.id === this.orderId) || null
  }

  private reloadOrder(): void {
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    this.order = orders.find(o => o.id === this.orderId) || null
  }

  private getDeliverySteps(): DeliveryStep[] {
    if (this.order === null) {
      return []
    }
    return getDeliverySteps(
      this.order.status,
      this.order.createTime,
      this.order.payTime,
      this.order.deliverTime,
      this.order.completeTime
    )
  }

  build() {
    Stack() {
      Column() {
        // 导航栏
        Row() {
          Text('‹')
            .fontSize(28)
            .fontColor(COLORS.TEXT_PRIMARY)
            .onClick(() => { this.onBack() })
          Text('订单详情')
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text(' ')
            .fontSize(28)
            .width(28)
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(COLORS.BG_WHITE)
        .alignItems(VerticalAlign.Center)

        if (this.order === null) {
          Column() {
            Text('📦').fontSize(60).margin({ top: 100 })
            Text('订单不存在').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: 16 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: SPACING.SM }) {
              // 订单状态卡片
              this.StatusCard()

              // 店铺与商品卡片
              this.StoreAndItemsCard()

              // 配送信息卡片
              this.DeliveryInfoCard()

              // 金额明细卡片
              this.AmountDetailCard()

              // 订单信息卡片
              this.OrderInfoCard()

              // 底部操作按钮
              this.ActionButtons()
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XL })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .backgroundColor(COLORS.BG_PRIMARY)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 取消订单确认弹窗
      if (this.showCancelDialog) {
        ConfirmDialog({
          title: '提示',
          content: '确定要取消该订单吗？',
          confirmText: '确定取消',
          cancelText: '再想想',
          onConfirm: () => {
            if (this.order !== null) {
              cancelOrder(this.order.id)
              this.reloadOrder()
            }
            this.showCancelDialog = false
          },
          onCancel: () => {
            this.showCancelDialog = false
          }
        })
      }

      // 确认收货确认弹窗
      if (this.showConfirmDialog) {
        ConfirmDialog({
          title: '提示',
          content: '确认已收到商品吗？',
          confirmText: '确认收货',
          cancelText: '取消',
          onConfirm: () => {
            if (this.order !== null) {
              confirmOrder(this.order.id)
              this.reloadOrder()
            }
            this.showConfirmDialog = false
          },
          onCancel: () => {
            this.showConfirmDialog = false
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  StatusCard() {
    Column({ space: SPACING.MD }) {
      Text(getOrderStatusText(this.order!.status))
        .fontSize(FONT_SIZE.BIG_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(getOrderStatusColor(this.order!.status))
        .width('100%')

      OrderStatusTimeline({ steps: this.getDeliverySteps() })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  StoreAndItemsCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('🏪')
          .fontSize(FONT_SIZE.LG)
        Text(this.order!.storeName)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      ForEach(this.order!.items, (item: CartItem) => {
        Row() {
          Text(item.goods.name)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
          Text(`x${item.quantity}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ right: SPACING.MD })
          Text(`¥${(item.goods.price * item.quantity).toFixed(2)}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width('100%')
        .padding({ top: SPACING.XS, bottom: SPACING.XS })
      }, (item: CartItem) => `${item.goods.id}`)
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  DeliveryInfoCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('配送信息')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      Row() {
        Text(this.order!.address.name)
          .fontSize(FONT_SIZE.MD)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text(this.order!.address.phone)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ left: SPACING.MD })
      }
      .width('100%')

      Row() {
        Text('收货地址')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(`${this.order!.address.address} ${this.order!.address.detail}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  AmountDetailCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('金额明细')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      Row() {
        Text('商品总价')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(`¥${this.order!.totalPrice.toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')

      Row() {
        Text('配送费')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
        Text(`¥${this.order!.deliveryFee.toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')

      if (this.order!.discountAmount > 0) {
        Row() {
          Text('优惠')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .layoutWeight(1)
          Text(`-¥${this.order!.discountAmount.toFixed(2)}`)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
        }
        .width('100%')
      }

      Divider()
        .color(COLORS.DIVIDER)
        .margin({ top: SPACING.SM, bottom: SPACING.SM })

      Row() {
        Text('实付')
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.TEXT_PRIMARY)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text(`¥${this.order!.payAmount.toFixed(2)}`)
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.PRICE_RED)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  OrderInfoCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('订单信息')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ bottom: SPACING.SM })

      Row() {
        Text('订单号')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(this.order!.id.toString())
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row() {
        Text('下单时间')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_SECONDARY)
        Text(this.order!.createTime)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      if (this.order!.remark !== '') {
        Row() {
          Text('备注')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text(this.order!.remark)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  ActionButtons() {
    if (this.order!.status === 1 || this.order!.status === 3 || this.order!.status === 4) {
      Row({ space: SPACING.MD }) {
        // status===1 (待接单): 取消订单
        if (this.order!.status === 1) {
          Button('取消订单')
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
            .backgroundColor('#F5F5F5')
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .onClick(() => { this.showCancelDialog = true })
        }

        // status===3 (配送中): 确认收货
        if (this.order!.status === 3) {
          Button('确认收货')
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .onClick(() => { this.showConfirmDialog = true })
        }

        // status===4 (已完成): 再来一单 + 去评价
        if (this.order!.status === 4) {
          Button('再来一单')
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
            .backgroundColor(Color.Transparent)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .borderWidth(1)
            .borderColor(COLORS.PRIMARY)
            .onClick(() => { this.onBack() })
          Button('去评价')
            .layoutWeight(1)
            .height(44)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .onClick(() => { this.onReview(this.order!.id) })
        }
      }
      .width('100%')
      .margin({ top: SPACING.MD })
    }
  }
}
