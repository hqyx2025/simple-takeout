/**
 * 购物车页面
 * 从“我的”页面进入，展示当前用户购物车中的真实商品，并按店铺分别结算。
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { CartItem } from '../model/Models'
import { updateCartItemQuantity } from '../service/AppStorageManager'
import { EmptyState } from '../components/EmptyState'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct CartPage {
  @StorageLink('cartItems') cartItems: CartItem[] = []
  @StorageLink('isLoggedIn') loggedIn: boolean = false

  aboutToAppear() {
    logInfo('Page', `进入购物车页面 CartPage，商品种类=${this.cartItems.length}`)
  }

  private getStoreIds(): number[] {
    const storeIds: number[] = []
    for (let i = 0; i < this.cartItems.length; i++) {
      const storeId: number = this.cartItems[i].storeId
      if (storeIds.indexOf(storeId) < 0) {
        storeIds.push(storeId)
      }
    }
    return storeIds
  }

  private getStoreItems(storeId: number): CartItem[] {
    return this.cartItems.filter((item: CartItem) => item.storeId === storeId)
  }

  private getStoreName(storeId: number): string {
    const items: CartItem[] = this.getStoreItems(storeId)
    return items.length > 0 ? items[0].storeName : '店铺'
  }

  private getTotalCount(): number {
    return this.cartItems.reduce((total: number, item: CartItem) => total + item.quantity, 0)
  }

  private getTotalPrice(): number {
    return this.cartItems.reduce((total: number, item: CartItem) => total + item.goods.price * item.quantity, 0)
  }

  private changeQuantity(item: CartItem, delta: number): void {
    const nextQuantity: number = item.quantity + delta
    updateCartItemQuantity(item.goods.id, item.storeId, nextQuantity)
    this.cartItems = AppStorage.get<CartItem[]>('cartItems') || []
  }

  private checkoutStore(storeId: number): void {
    const items: CartItem[] = this.getStoreItems(storeId)
    if (items.length === 0) {
      return
    }
    AppStorage.setOrCreate<number>('checkoutStoreId', storeId)
    logInfo('Cart', `从购物车进入结算 storeId=${storeId} 商品数=${items.length}`)
    router.pushUrl({ url: 'pages/CheckoutPage' })
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(FONT_SIZE.BIG_TITLE)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('购物车')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
          .fontSize(FONT_SIZE.BIG_TITLE)
          .width(FONT_SIZE.BIG_TITLE)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
      .alignItems(VerticalAlign.Center)

      if (!this.loggedIn) {
        EmptyState({ icon: '🔒', title: '暂无登录', description: '请登录后查看购物车' })
      } else if (this.cartItems.length === 0) {
        EmptyState({ icon: '🛒', title: '购物车是空的', description: '去首页挑选喜欢的商品吧' })
      } else {
        Scroll() {
          Column({ space: SPACING.SM }) {
            ForEach(this.getStoreIds(), (storeId: number) => {
              this.StoreCard(storeId)
            }, (storeId: number) => storeId.toString())
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: 96 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(COLORS.BG_PRIMARY)

        Row() {
          Column({ space: SPACING.XS }) {
            Text(`共${this.getTotalCount()}件`)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
            Text(`¥${this.getTotalPrice().toFixed(2)}`)
              .fontSize(FONT_SIZE.XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.PRICE_RED)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('请选择店铺结算')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_HINT)
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  StoreCard(storeId: number) {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('🏪').fontSize(FONT_SIZE.XL)
        Text(this.getStoreName(storeId))
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Button('去结算')
          .height(32)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .onClick(() => { this.checkoutStore(storeId) })
      }
      ForEach(this.getStoreItems(storeId), (item: CartItem) => {
        this.CartItemRow(item)
      }, (item: CartItem) => `${item.storeId}-${item.goods.id}`)
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  CartItemRow(item: CartItem) {
    Row({ space: SPACING.MD }) {
      if (item.goods.image !== '') {
        Image(item.goods.image)
          .width(64)
          .height(64)
          .borderRadius(BORDER_RADIUS.MD)
          .objectFit(ImageFit.Cover)
      } else {
        Text('🍽️')
          .width(64)
          .height(64)
          .fontSize(FONT_SIZE.XXL)
          .textAlign(TextAlign.Center)
          .backgroundColor(COLORS.TAG_BG)
          .borderRadius(BORDER_RADIUS.MD)
      }
      Column({ space: SPACING.XS }) {
        Text(item.goods.name)
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`¥${item.goods.price.toFixed(2)}`)
          .fontSize(FONT_SIZE.MD)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRICE_RED)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Row({ space: SPACING.SM }) {
        Text('−')
          .width(30)
          .height(30)
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.TEXT_SECONDARY)
          .backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.CIRCLE)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.changeQuantity(item, -1) })
        Text(item.quantity.toString())
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .width(24)
          .textAlign(TextAlign.Center)
        Text('+')
          .width(30)
          .height(30)
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.CIRCLE)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.changeQuantity(item, 1) })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: SPACING.XS, bottom: SPACING.XS })
  }
}
