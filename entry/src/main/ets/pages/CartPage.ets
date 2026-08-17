/**
 * 购物车页面
 * 从“我的”页面进入，展示当前用户购物车中的真实商品，并按店铺分别结算。
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { CartItem } from '../model/Models'
import { deleteCartItemRemote, deleteCartItemsRemote, refreshCartFromServer, updateCartItemQuantityRemote } from '../service/AppStorageManager'
import { EmptyState } from '../components/EmptyState'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct CartPage {
  @State cartItems: CartItem[] = []
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State editing: boolean = false
  @State selectedGoodsIds: number[] = []
  @State processing: boolean = false
  @State cartRenderVersion: number = 0
  @State totalCount: number = 0
  @State totalPrice: number = 0

  async aboutToAppear(): Promise<void> {
    logInfo('Page', `进入购物车页面 CartPage，商品种类=${this.cartItems.length}`)
    await this.refreshFromDatabase()
  }

  async onPageShow(): Promise<void> {
    if (this.loggedIn) {
      await this.refreshFromDatabase()
    }
  }

  private async refreshFromDatabase(): Promise<boolean> {
    const remoteCart: CartItem[] | null = await refreshCartFromServer()
    if (remoteCart === null) {
      return false
    }
    this.cartItems = remoteCart.slice()
    let nextTotalCount: number = 0
    let nextTotalPrice: number = 0
    for (let i = 0; i < remoteCart.length; i++) {
      nextTotalCount += remoteCart[i].quantity
      nextTotalPrice += remoteCart[i].goods.price * remoteCart[i].quantity
    }
    this.totalCount = nextTotalCount
    this.totalPrice = nextTotalPrice
    this.cartRenderVersion += 1
    return true
  }

  private getStoreIds(): number[] {
    const storeIds: number[] = []
    const currentCart: CartItem[] = this.getCurrentCartItems()
    for (let i = 0; i < currentCart.length; i++) {
      const storeId: number = currentCart[i].storeId
      if (storeIds.indexOf(storeId) < 0) {
        storeIds.push(storeId)
      }
    }
    return storeIds
  }

  private getStoreItems(storeId: number): CartItem[] {
    return this.getCurrentCartItems().filter((item: CartItem) => item.storeId === storeId)
  }

  private getCurrentCartItems(): CartItem[] {
    return Array.isArray(this.cartItems) ? this.cartItems : []
  }

  private getCurrentQuantity(goodsId: number, storeId: number): number {
    const item: CartItem | undefined = this.getCurrentCartItems().find((cartItem: CartItem) =>
      cartItem.goods.id === goodsId && cartItem.storeId === storeId)
    return item === undefined ? 0 : item.quantity
  }

  private getStoreName(storeId: number): string {
    const items: CartItem[] = this.getStoreItems(storeId)
    return items.length > 0 ? items[0].storeName : '店铺'
  }

  private getTotalCount(): number {
    return this.totalCount
  }

  private getTotalPrice(): number {
    return this.totalPrice
  }

  private isSelected(goodsId: number): boolean {
    return this.selectedGoodsIds.indexOf(goodsId) >= 0
  }

  private toggleSelected(goodsId: number): void {
    if (this.isSelected(goodsId)) {
      this.selectedGoodsIds = this.selectedGoodsIds.filter((id: number) => id !== goodsId)
    } else {
      this.selectedGoodsIds = this.selectedGoodsIds.concat([goodsId])
    }
  }

  private async changeQuantity(item: CartItem, delta: number): Promise<void> {
    const displayedQuantity: number = this.getCurrentQuantity(item.goods.id, item.storeId)
    if (delta < 0 && displayedQuantity <= 1) {
      promptAction.showToast({ message: '\u5546\u54c1\u6570\u91cf\u6700\u5c11\u4e3a1\uff0c\u5982\u9700\u79fb\u9664\u8bf7\u70b9\u51fb\u5220\u9664', duration: 1800 })
      return
    }
    if (this.processing) {
      promptAction.showToast({ message: '购物车操作正在处理，请稍候', duration: 1500 })
      return
    }
    this.processing = true
    const synced: boolean = await this.refreshFromDatabase()
    if (!synced) {
      this.processing = false
      promptAction.showToast({ message: 'Cart sync failed, please retry', duration: 2200 })
      return
    }
    const currentCart: CartItem[] = this.getCurrentCartItems()
    const currentItem: CartItem | undefined = currentCart.find((cartItem: CartItem) =>
      cartItem.goods.id === item.goods.id && cartItem.storeId === item.storeId)
    const currentQuantity: number = currentItem === undefined ? 0 : currentItem.quantity
    const nextQuantity: number = currentQuantity + delta
    const ok: boolean = await updateCartItemQuantityRemote(item.goods.id, nextQuantity)
    await this.refreshFromDatabase()
    if (!ok) {
      await this.refreshFromDatabase()
      promptAction.showToast({ message: '修改购物车失败，请稍后重试', duration: 2200 })
    }
    this.processing = false
  }

  private async deleteOne(item: CartItem): Promise<void> {
    if (this.processing) {
      promptAction.showToast({ message: '购物车操作正在处理，请稍候', duration: 1500 })
      return
    }
    this.processing = true
    const ok: boolean = await deleteCartItemRemote(item.goods.id)
    await this.refreshFromDatabase()
    if (ok) {
      this.selectedGoodsIds = this.selectedGoodsIds.filter((id: number) => id !== item.goods.id)
      promptAction.showToast({ message: '商品已删除', duration: 1500 })
    } else {
    await this.refreshFromDatabase()
      promptAction.showToast({ message: '删除商品失败，请稍后重试', duration: 2200 })
    }
    this.processing = false
  }

  private async deleteStore(storeId: number): Promise<void> {
    const items: CartItem[] = this.getStoreItems(storeId)
    const ids: number[] = []
    for (let i = 0; i < items.length; i++) {
      ids.push(items[i].goods.id)
    }
    if (ids.length === 0) {
      return
    }
    if (this.processing) {
      promptAction.showToast({ message: '\u8d2d\u7269\u8f66\u64cd\u4f5c\u6b63\u5728\u5904\u7406\uff0c\u8bf7\u7a0d\u5019', duration: 1500 })
      return
    }
    this.processing = true
    const ok: boolean = await deleteCartItemsRemote(ids)
    await this.refreshFromDatabase()
    if (ok) {
      this.selectedGoodsIds = this.selectedGoodsIds.filter((id: number) => ids.indexOf(id) < 0)
      promptAction.showToast({ message: '\u5df2\u5220\u9664\u8be5\u5e97\u94fa\u7684\u8d2d\u7269\u8f66\u5546\u54c1', duration: 1600 })
    } else {
      promptAction.showToast({ message: '\u5220\u9664\u5e97\u94fa\u5546\u54c1\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5', duration: 2200 })
    }
    this.processing = false
  }

  private async deleteSelected(): Promise<void> {
    if (this.selectedGoodsIds.length === 0) {
      promptAction.showToast({ message: '请先选择要删除的商品', duration: 1600 })
      return
    }
    if (this.processing) {
      promptAction.showToast({ message: '购物车操作正在处理，请稍候', duration: 1500 })
      return
    }
    this.processing = true
    const ids: number[] = this.selectedGoodsIds.slice()
    const ok: boolean = await deleteCartItemsRemote(ids)
    await this.refreshFromDatabase()
    if (ok) {
      this.selectedGoodsIds = []
      promptAction.showToast({ message: `已删除 ${ids.length} 件商品`, duration: 1600 })
    } else {
    await this.refreshFromDatabase()
      promptAction.showToast({ message: '批量删除失败，请稍后重试', duration: 2200 })
    }
    this.processing = false
  }

  private checkoutAll(): void {
    const items: CartItem[] = this.getCurrentCartItems()
    if (items.length === 0) {
      promptAction.showToast({ message: '\u8bf7\u5148\u6dfb\u52a0\u5546\u54c1\u540e\u518d\u7ed3\u7b97', duration: 1600 })
      return
    }
    AppStorage.setOrCreate<number>('checkoutStoreId', 0)
    logInfo('Cart', `从购物车统一进入结算 商品数=${items.length} 总金额=${this.totalPrice.toFixed(2)}`)
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
        Text(this.editing ? '完成' : '管理')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .width(48)
          .textAlign(TextAlign.End)
          .onClick(() => {
            this.editing = !this.editing
            if (!this.editing) {
              this.selectedGoodsIds = []
            }
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
      .alignItems(VerticalAlign.Center)

      if (!this.loggedIn) {
        EmptyState({ icon: '🔒', title: '暂无登录', description: '请登录后查看购物车' })
      } else if (this.getCurrentCartItems().length === 0) {
        EmptyState({ icon: '🛒', title: '购物车是空的', description: '去首页挑选喜欢的商品吧' })
      } else {
        Scroll() {
          Column({ space: SPACING.SM }) {
            Row() {
              Text(`\u5f53\u524d\u8d2d\u7269\u8f66\u8d2d\u7269\u603b\u6570\u4e3a(${this.totalCount})\u4ef6`)
                .fontSize(FONT_SIZE.LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
                .width('100%')
            }
            .width('100%')
            .padding({ left: SPACING.SM, right: SPACING.SM, top: SPACING.SM, bottom: SPACING.XS })
            ForEach(this.getStoreIds(), (storeId: number) => {
              this.StoreCard(storeId)
            }, (storeId: number) => `${this.cartRenderVersion}-${storeId}`)
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: 96 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(COLORS.BG_PRIMARY)

        Row() {
          if (this.editing) {
            Text(`已选 ${this.selectedGoodsIds.length} 件`)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .layoutWeight(1)
            Button('删除选中')
              .height(40)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_WHITE)
              .backgroundColor(COLORS.ERROR)
              .borderRadius(BORDER_RADIUS.ROUND)
              .type(ButtonType.Capsule)
              .onClick(() => { this.deleteSelected() })
          } else {
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
            Button('\u53bb\u7ed3\u7b97')
              .height(40)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_WHITE)
              .backgroundColor(COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .type(ButtonType.Capsule)
              .onClick(() => { this.checkoutAll() })
          }
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
        Button('删除')
          .height(32)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.ERROR)
          .backgroundColor('#FFF1F0')
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .onClick(() => { this.deleteStore(storeId) })
      }
      ForEach(this.getStoreItems(storeId), (item: CartItem) => {
        this.CartItemRow(item)
      }, (item: CartItem) => `${this.cartRenderVersion}-${item.storeId}-${item.goods.id}`)
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  CartItemRow(item: CartItem) {
    Row({ space: SPACING.MD }) {
      if (true) {
        Text(this.isSelected(item.goods.id) ? '✓' : '○')
          .width(24)
          .height(24)
          .fontSize(FONT_SIZE.LG)
          .fontColor(this.isSelected(item.goods.id) ? COLORS.PRIMARY : COLORS.TEXT_HINT)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.toggleSelected(item.goods.id) })
      }
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
        Text(this.getCurrentQuantity(item.goods.id, item.storeId).toString())
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
      if (this.editing) {
        Button('删除')
          .height(30)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.ERROR)
          .backgroundColor('#FFF1F0')
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .onClick(() => { this.deleteOne(item) })
      }
    }
    .width('100%')
    .padding({ top: SPACING.XS, bottom: SPACING.XS })
  }
}
