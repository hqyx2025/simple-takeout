/**
 * 购物车页面。
 *
 * 只作为首页底部 Tab 的「购物车」标签内容承载（Tab 内嵌，标题栏不放返回键）。
 * 「我的」页的购物车入口已删除，因此这里不再需要 showNavBar 开关与路由返回。
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, merchantImageSource, DEFAULT_MERCHANT_IMAGE } from '../common/Constants'
import { CartItem, BundleInfo, GoodsItem } from '../model/Models'
import { deleteCartItemRemote, deleteCartItemsRemote, refreshCartFromServer, updateCartItemQuantityRemote, fetchBundleRemote } from '../service/AppStorageManager'
import { EmptyState } from '../components/EmptyState'
import { logInfo } from '../service/AppLogger'

/** 凑单提示：某店铺还差多少钱起送 + 可凑单的便宜菜品 */
class BundleHint {
  storeId: number = 0
  storeName: string = ''
  minOrder: number = 0
  gap: number = 0
  suggestions: GoodsItem[] = []

  static create(info: BundleInfo): BundleHint {
    const hint: BundleHint = new BundleHint()
    hint.storeId = info.storeId
    hint.storeName = info.storeName
    hint.minOrder = info.minOrder
    hint.gap = info.gap
    hint.suggestions = info.suggestions
    return hint
  }
}

/**
 * 购物车页面。
 *
 * 只作为首页底部 Tab 的「购物车」标签内容承载（Tab 内嵌，标题栏不放返回键）。
 * 「我的」页的购物车入口已删除，因此这里不再需要 showNavBar 开关与路由返回。
 */
@Component
export struct CartPage {
  @State cartItems: CartItem[] = []
  // 全局购物车变化时刷新本页（Tab 常驻内存，没有页面级 onPageShow 可依赖）
  @StorageLink('cartItems') @Watch('onGlobalCartChange') globalCartItems: CartItem[] = []
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State editing: boolean = false
  // 多规格：勾选按 (菜品, 规格) 行粒度记录，避免同菜品不同规格互相串选
  @State selectedRowKeys: string[] = []
  @State processing: boolean = false
  @State cartRenderVersion: number = 0
  @State totalCount: number = 0
  @State totalPrice: number = 0
  // 凑单提示（未达起送价的店铺）
  @State bundleHints: BundleHint[] = []
  // 上次凑单查询对应的「店铺+金额」签名，避免数量微调时重复请求
  private bundleHintSignature: string = ''
  private bundleFetching: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', `进入购物车页面 CartPage，商品种类=${this.cartItems.length}`)
    await this.refreshFromDatabase()
  }

  /**
   * 购物车作为 Tab 内容常驻内存时不会走页面级 onPageShow，
   * 因此改为监听全局购物车变化：在店铺详情/结算页改过购物车后切回来能立刻看到最新数据。
   */
  onGlobalCartChange(): void {
    if (this.loggedIn) {
      this.cartItems = AppStorage.get<CartItem[]>('cartItems') || []
      this.recomputeTotals()
      this.cartRenderVersion += 1
    }
  }

  private async refreshFromDatabase(): Promise<boolean> {
    const remoteCart: CartItem[] | null = await refreshCartFromServer()
    if (remoteCart === null) {
      return false
    }
    this.cartItems = remoteCart.slice()
    this.recomputeTotals()
    this.cartRenderVersion += 1
    await this.refreshBundleHints()
    return true
  }

  /** 按当前 cartItems 重算总件数与总价（与后端返回的购物车、以及全局购物车变化共用）。 */
  private recomputeTotals(): void {
    let nextTotalCount: number = 0
    let nextTotalPrice: number = 0
    for (let i = 0; i < this.cartItems.length; i++) {
      nextTotalCount += this.cartItems[i].quantity
      nextTotalPrice += (this.cartItems[i].price ?? this.cartItems[i].goods.price) * this.cartItems[i].quantity
    }
    this.totalCount = nextTotalCount
    this.totalPrice = nextTotalPrice
  }

  /** 凑单提示：对未达起送价的店铺查询还差多少元并给出可凑单菜品。 */
  private async refreshBundleHints(): Promise<void> {
    const storeIds: number[] = this.getStoreIds()
    // 数量增减会让 refreshFromDatabase 被连续调用多次，这里按「店铺+金额」签名去重，避免重复请求凑单接口
    const signature: string = storeIds.map((storeId: number) => `${storeId}:${this.getStoreTotal(storeId)}`).join('|')
    if (signature === this.bundleHintSignature || this.bundleFetching) {
      return
    }
    this.bundleFetching = true
    const hints: BundleHint[] = []
    try {
      for (let i = 0; i < storeIds.length && i < 3; i++) {
        const storeId: number = storeIds[i]
        const info: BundleInfo | null = await fetchBundleRemote(storeId, this.getStoreTotal(storeId))
        if (info !== null && info.gap > 0) {
          hints.push(BundleHint.create(info))
        }
      }
      this.bundleHints = hints
      this.bundleHintSignature = signature
    } finally {
      this.bundleFetching = false
    }
  }

  /** 某店铺已选商品金额（按行实际单价计算）。 */
  private getStoreTotal(storeId: number): number {
    const items: CartItem[] = this.getStoreItems(storeId)
    let total: number = 0
    for (let i = 0; i < items.length; i++) {
      total += (items[i].price ?? items[i].goods.price) * items[i].quantity
    }
    return Math.round(total * 100) / 100
  }

  private getBundleHint(storeId: number): BundleHint | null {
    const matched: BundleHint[] = this.bundleHints.filter((hint: BundleHint) => hint.storeId === storeId)
    return matched.length > 0 ? matched[0] : null
  }

  /** 去凑单：打开该店铺详情页继续加购。 */
  private goBundle(hint: BundleHint): void {
    AppStorage.setOrCreate<number>('selectedStoreId', hint.storeId)
    AppStorage.setOrCreate<string>('selectedStoreName', hint.storeName)
    logInfo('Cart', `凑单跳转店铺 storeId=${hint.storeId} 还差=${hint.gap}`)
    router.pushUrl({ url: 'pages/StoreDetailPage' })
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

  /** 购物车行唯一键（菜品 + 规格）。 */
  private rowKey(item: CartItem): string {
    return `${item.goods.id}_${item.specId ?? 0}`
  }

  private getRowQuantity(item: CartItem): number {
    const matched: CartItem | undefined = this.getCurrentCartItems().find((cartItem: CartItem) =>
      this.rowKey(cartItem) === this.rowKey(item) && cartItem.storeId === item.storeId)
    return matched === undefined ? item.quantity : matched.quantity
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

  private isSelected(item: CartItem): boolean {
    return this.selectedRowKeys.indexOf(this.rowKey(item)) >= 0
  }

  private toggleSelected(item: CartItem): void {
    const key: string = this.rowKey(item)
    if (this.selectedRowKeys.indexOf(key) >= 0) {
      this.selectedRowKeys = this.selectedRowKeys.filter((item0: string) => item0 !== key)
    } else {
      this.selectedRowKeys = this.selectedRowKeys.concat([key])
    }
  }

  private async changeQuantity(item: CartItem, delta: number): Promise<void> {
    const displayedQuantity: number = this.getRowQuantity(item)
    if (delta < 0 && displayedQuantity <= 1) {
      promptAction.showToast({ message: '商品数量最少为1，如需移除请点击删除', duration: 1800 })
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
      promptAction.showToast({ message: '购物车同步失败，请重试', duration: 2200 })
      return
    }
    const currentCart: CartItem[] = this.getCurrentCartItems()
    const currentItem: CartItem | undefined = currentCart.find((cartItem: CartItem) =>
      this.rowKey(cartItem) === this.rowKey(item) && cartItem.storeId === item.storeId)
    const currentQuantity: number = currentItem === undefined ? 0 : currentItem.quantity
    const nextQuantity: number = currentQuantity + delta
    const ok: boolean = await updateCartItemQuantityRemote(item.goods.id, nextQuantity, item.specId ?? 0)
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
    const ok: boolean = await deleteCartItemRemote(item.goods.id, item.specId ?? 0)
    await this.refreshFromDatabase()
    if (ok) {
      this.selectedRowKeys = this.selectedRowKeys.filter((key: string) => key !== this.rowKey(item))
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
      // 勾选按 (菜品, 规格) 行记录，删除整店时清掉该店所有行的勾选
      const storeKeys: string[] = items.map((item: CartItem) => this.rowKey(item))
      this.selectedRowKeys = this.selectedRowKeys.filter((key: string) => storeKeys.indexOf(key) < 0)
      promptAction.showToast({ message: '\u5df2\u5220\u9664\u8be5\u5e97\u94fa\u7684\u8d2d\u7269\u8f66\u5546\u54c1', duration: 1600 })
    } else {
      promptAction.showToast({ message: '\u5220\u9664\u5e97\u94fa\u5546\u54c1\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5', duration: 2200 })
    }
    this.processing = false
  }

  private async deleteSelected(): Promise<void> {
    if (this.selectedRowKeys.length === 0) {
      promptAction.showToast({ message: '请先选择要删除的商品', duration: 1600 })
      return
    }
    if (this.processing) {
      promptAction.showToast({ message: '购物车操作正在处理，请稍候', duration: 1500 })
      return
    }
    this.processing = true
    const keys: string[] = this.selectedRowKeys.slice()
    const rows: CartItem[] = this.getCurrentCartItems().filter((item: CartItem) => keys.indexOf(this.rowKey(item)) >= 0)
    let allDeleted: boolean = true
    for (let i = 0; i < rows.length; i++) {
      const ok: boolean = await deleteCartItemRemote(rows[i].goods.id, rows[i].specId ?? 0)
      if (!ok) {
        allDeleted = false
      }
    }
    await this.refreshFromDatabase()
    if (allDeleted) {
      this.selectedRowKeys = []
      promptAction.showToast({ message: `已删除 ${rows.length} 件商品`, duration: 1600 })
    } else {
      await this.refreshFromDatabase()
      promptAction.showToast({ message: '批量删除失败，请稍后重试', duration: 2200 })
    }
    this.processing = false
  }

  private checkoutAll(): void {
    const items: CartItem[] = this.getCurrentCartItems()
    if (items.length === 0) {
      promptAction.showToast({ message: '请先添加商品后再结算', duration: 1600 })
      return
    }
    AppStorage.setOrCreate<number>('checkoutStoreId', 0)
    logInfo('Cart', `从购物车统一进入结算 商品数=${items.length} 总金额=${this.totalPrice.toFixed(2)}`)
    router.pushUrl({ url: 'pages/CheckoutPage' })
  }

  build() {
    Column() {
      Row() {
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
              this.selectedRowKeys = []
            }
          })
      }      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
      .alignItems(VerticalAlign.Center)

      if (!this.loggedIn) {
        EmptyState({ icon: '🔒', title: '暂无登录', description: '请登录后查看购物车' })
      } else if (this.getCurrentCartItems().length === 0) {
        EmptyState({ icon: '🛒', title: '购物车是空的', description: '去首页挑选喜欢的商品吧' })
      } else {
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
        List({ space: SPACING.SM }) {
          ListItem() {
            Row() {
              Text(`\u5f53\u524d\u8d2d\u7269\u8f66\u8d2d\u7269\u603b\u6570\u4e3a(${this.totalCount})\u4ef6`)
                .fontSize(FONT_SIZE.LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
                .width('100%')
            }
            .width('100%')
            .padding({ left: SPACING.SM, right: SPACING.SM, top: SPACING.SM, bottom: SPACING.XS })
          }
          ForEach(this.getStoreIds(), (storeId: number) => {
            ListItem() {
              this.StoreCard(storeId)
            }
          }, (storeId: number) => `${this.cartRenderVersion}-${storeId}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(COLORS.BG_PRIMARY)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: 96 })

        Row() {
          if (this.editing) {
            Text(`已选 ${this.selectedRowKeys.length} 件`)
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
              .id('cart-checkout')
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
          .backgroundColor(COLORS.ERROR_LIGHT)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .onClick(() => { this.deleteStore(storeId) })
      }
      ForEach(this.getStoreItems(storeId), (item: CartItem) => {
        this.CartItemRow(item)
      }, (item: CartItem) => `${this.cartRenderVersion}-${item.storeId}-${item.goods.id}-${item.specId ?? 0}`)

      // 凑单提示：未达起送价时给出差额与店内可凑单菜品
      if (this.getBundleHint(storeId) !== null) {
        this.BundleTipCard(this.getBundleHint(storeId)!)
      }
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  CartItemRow(item: CartItem) {
    Row({ space: SPACING.MD }) {
      if (this.editing) {
        Text(this.isSelected(item) ? '✓' : '○')
          .width(24)
          .height(24)
          .fontSize(FONT_SIZE.LG)
          .fontColor(this.isSelected(item) ? COLORS.PRIMARY : COLORS.TEXT_HINT)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.toggleSelected(item) })
      }
      Image(merchantImageSource(item.goods.image))
        .alt(DEFAULT_MERCHANT_IMAGE)
        .width(64)
        .height(64)
        .borderRadius(BORDER_RADIUS.MD)
        .objectFit(ImageFit.Cover)
      Column({ space: SPACING.XS }) {
        Text(item.goods.name)
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 多规格：展示所选规格，库存与价格都按规格计算
        if ((item.specName ?? '') !== '') {
          Text(`规格：${item.specName}`)
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_HINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(`¥${(item.price ?? item.goods.price).toFixed(2)}`)
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
          .id(`cart-minus-${item.goods.id}-${item.specId ?? 0}`)
          .onClick(() => { this.changeQuantity(item, -1) })
        Text(this.getRowQuantity(item).toString())
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .width(24)
          .textAlign(TextAlign.Center)
          .id(`cart-qty-${item.goods.id}-${item.specId ?? 0}`)
        Text('+')
          .width(30)
          .height(30)
          .fontSize(FONT_SIZE.LG)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.CIRCLE)
          .textAlign(TextAlign.Center)
          .id(`cart-plus-${item.goods.id}-${item.specId ?? 0}`)
          .onClick(() => { this.changeQuantity(item, 1) })
      }
      .alignItems(VerticalAlign.Center)
      Button('删除')
        .height(30)
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.ERROR)
        .backgroundColor(COLORS.ERROR_LIGHT)
        .borderRadius(BORDER_RADIUS.ROUND)
        .type(ButtonType.Capsule)
        .onClick(() => { this.deleteOne(item) })
    }
    .width('100%')
    .padding({ top: SPACING.XS, bottom: SPACING.XS })
  }

  /** 凑单提示卡：还差多少元起送 + 店内可凑单菜品 + 去凑单入口。 */
  @Builder
  BundleTipCard(hint: BundleHint) {
    Column({ space: SPACING.SM }) {
      Row() {
        Text(`还差 ¥${hint.gap.toFixed(2)} 起送`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.PRICE_RED)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .id('cart-bundle-gap')
        Text('去凑单 ›')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.PRIMARY)
          .onClick(() => { this.goBundle(hint) })
      }
      .width('100%')

      if (hint.suggestions.length > 0) {
        Text(`推荐凑单：${this.bundleSuggestionText(hint)}`)
          .fontSize(FONT_SIZE.XS)
          .fontColor(COLORS.TEXT_SECONDARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(SPACING.SM)
    .margin({ top: SPACING.SM })
    .backgroundColor(COLORS.TAG_BG)
    .borderRadius(BORDER_RADIUS.MD)
  }

  /** 凑单推荐文案：菜品名 + 价格（最多 3 个）。 */
  private bundleSuggestionText(hint: BundleHint): string {
    const parts: string[] = []
    for (let i = 0; i < hint.suggestions.length && i < 3; i++) {
      const goods: GoodsItem = hint.suggestions[i]
      parts.push(`${goods.name} ¥${goods.price.toFixed(2)}`)
    }
    return parts.join('、')
  }
}
