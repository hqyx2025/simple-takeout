import { AppMotion } from '../common/theme/AppMotion'
import { FloatingTabBarTheme } from '../common/theme/FloatingTabBarTheme'
import { PageHeader } from '../components/PageHeader'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { ConfirmDialog } from '../components/ConfirmDialog'
/**
 * 购物车页面。
 *
 * 只作为首页底部 Tab 的「购物车」标签内容承载（Tab 内嵌，标题栏不放返回键）。
 * 「我的」页的购物车入口已删除，因此这里不再需要 showNavBar 开关与路由返回。
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, merchantImageSource, DEFAULT_MERCHANT_IMAGE, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { CartItem, BundleInfo, GoodsItem } from '../model/Models'
import { addCartItemRemote, deleteCartItemRemote, deleteCartItemsRemote, refreshCartFromServer, updateCartItemQuantityRemote, fetchBundleRemote } from '../service/AppStorageManager'
import { EmptyState } from '../components/EmptyState'
import { logInfo } from '../service/AppLogger'

class CartStoreCard {
  storeId: number = 0
  items: CartItem[] = []
  visibleItems: CartItem[] = []
  expanded: boolean = false
}

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
  onBrowse: () => void = () => {}
  @Prop bottomInset: number = 0
  @State actionBarHeight: number = 72
  @State cartItems: CartItem[] = []
  @State expandedStoreIds: number[] = []
  @State storeCards: CartStoreCard[] = []
  // 全局购物车变化时刷新本页（Tab 常驻内存，没有页面级 onPageShow 可依赖）
  @StorageLink('cartItems') @Watch('onGlobalCartChange') globalCartItems: CartItem[] = []
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State editing: boolean = false
  // 多规格：勾选按 (菜品, 规格) 行粒度记录，避免同菜品不同规格互相串选
  @State selectedRowKeys: string[] = []
  @State processing: boolean = false
  @State totalCount: number = 0
  @State totalPrice: number = 0
  @State undoMessage: string = ''
  @State showDeleteConfirm: boolean = false
  @State deleteConfirmTitle: string = ''
  @State deleteConfirmContent: string = ''
  private pendingUndoItem: CartItem | null = null
  private undoTimer: number = -1
  private pendingDeleteMode: number = 0
  private pendingDeleteStoreId: number = 0
  private pendingDeleteRowKeys: string[] = []
  // 凑单提示（未达起送价的店铺）
  @State bundleHints: BundleHint[] = []
  // 上次凑单查询对应的「店铺+金额」签名，避免数量微调时重复请求
  private bundleHintSignature: string = ''
  private bundleFetching: boolean = false
  private bundleRefreshPending: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', `进入购物车页面 CartPage，商品种类=${this.cartItems.length}`)
    await this.refreshFromDatabase()
  }

  aboutToDisappear(): void {
    this.clearUndo()
    this.cancelPendingDelete()
  }

  /**
   * 购物车作为 Tab 内容常驻内存时不会走页面级 onPageShow，
   * 因此改为监听全局购物车变化：在店铺详情/结算页改过购物车后切回来能立刻看到最新数据。
   */
  onGlobalCartChange(): void {
    if (this.loggedIn) {
      this.cartItems = AppStorage.get<CartItem[]>('cartItems') || []
      this.recomputeTotals()
    }
  }

  private async refreshFromDatabase(showErrorToast: boolean = true): Promise<boolean> {
    const remoteCart: CartItem[] | null = await refreshCartFromServer(showErrorToast)
    if (remoteCart === null) {
      return false
    }
    this.cartItems = remoteCart.slice()
    this.recomputeTotals()
    await this.refreshBundleHints(showErrorToast)
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
    this.rebuildCards()
  }

  private rebuildCards(): void {
    const ids: number[] = this.getStoreIds()
    this.expandedStoreIds = this.expandedStoreIds.filter((id: number) => ids.indexOf(id) >= 0)
    this.storeCards = ids.map((id: number) => {
      const card: CartStoreCard = new CartStoreCard()
      card.storeId = id
      card.items = this.getStoreItems(id)
      card.expanded = this.expandedStoreIds.indexOf(id) >= 0
      card.visibleItems = card.expanded ? card.items : card.items.slice(0, 2)
      return card
    })
  }

  private toggleStore(storeId: number): void {
    this.getUIContext().animateTo({ duration: AppMotion.duration(220), curve: Curve.EaseOut }, () => {
      this.expandedStoreIds = this.expandedStoreIds.indexOf(storeId) >= 0
        ? this.expandedStoreIds.filter((id: number) => id !== storeId)
        : this.expandedStoreIds.concat(storeId)
      this.rebuildCards()
    })
  }

  /** 凑单提示：对未达起送价的店铺查询还差多少元并给出可凑单菜品。 */
  private async refreshBundleHints(showErrorToast: boolean = true): Promise<void> {
    const storeIds: number[] = this.getStoreIds()
    // 数量增减会让 refreshFromDatabase 被连续调用多次，这里按「店铺+金额」签名去重，避免重复请求凑单接口
    const signature: string = storeIds.map((storeId: number) => `${storeId}:${this.getStoreTotal(storeId)}`).join('|')
    if (signature === this.bundleHintSignature) {
      return
    }
    if (this.bundleFetching) {
      this.bundleRefreshPending = true
      return
    }
    this.bundleFetching = true
    const hints: BundleHint[] = []
    try {
      for (let i = 0; i < storeIds.length && i < 3; i++) {
        const storeId: number = storeIds[i]
        const info: BundleInfo | null = await fetchBundleRemote(storeId, this.getStoreTotal(storeId), showErrorToast)
        if (info !== null && info.gap > 0) {
          hints.push(BundleHint.create(info))
        }
      }
      this.bundleHints = hints
      this.bundleHintSignature = signature
    } finally {
      this.bundleFetching = false
      if (this.bundleRefreshPending) {
        this.bundleRefreshPending = false
        await this.refreshBundleHints(false)
      }
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

  private findCurrentItem(item: CartItem): CartItem | undefined {
    return this.getCurrentCartItems().find((cartItem: CartItem) =>
      cartItem.storeId === item.storeId && this.rowKey(cartItem) === this.rowKey(item))
  }

  private getCurrentRowQuantity(item: CartItem): number {
    const matched: CartItem | undefined = this.findCurrentItem(item)
    return matched === undefined ? 0 : matched.quantity
  }

  private async useStoredCart(): Promise<void> {
    this.cartItems = (AppStorage.get<CartItem[]>('cartItems') || []).slice()
    this.recomputeTotals()
    await this.refreshBundleHints(false)
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
    if (this.processing) {
      promptAction.showToast({ message: '购物车操作正在处理，请稍候', duration: 1500 })
      return
    }
    this.processing = true
    try {
      if (!await this.refreshFromDatabase(false)) {
        promptAction.showToast({ message: '购物车同步失败，请重试', duration: 2200 })
        return
      }
      const currentQuantity: number = this.getCurrentRowQuantity(item)
      if (currentQuantity <= 0 && delta < 0) {
        promptAction.showToast({ message: '商品已不在购物车', duration: 1600 })
        return
      }
      if (delta < 0 && currentQuantity <= 1) {
        promptAction.showToast({ message: '商品数量最少为1，如需移除请点击删除', duration: 1800 })
        return
      }
      const nextQuantity: number = currentQuantity + delta
      let ok: boolean = false
      try {
        ok = await updateCartItemQuantityRemote(item.goods.id, nextQuantity, item.specId ?? 0, false)
      } catch (_) {
        ok = false
      }
      let reconciled: boolean = ok
      if (ok) {
        await this.useStoredCart()
      } else {
        reconciled = await this.refreshFromDatabase(false)
      }
      if (!reconciled) {
        promptAction.showToast({ message: '修改结果待确认，请稍后刷新购物车', duration: 2400 })
        return
      }
      const afterQuantity: number = this.getCurrentRowQuantity(item)
      if (afterQuantity === nextQuantity) {
        return
      }
      if (afterQuantity !== currentQuantity) {
        promptAction.showToast({ message: '商品数量已变化，请以当前购物车为准', duration: 2400 })
      } else {
        promptAction.showToast({ message: '修改购物车失败，请稍后重试', duration: 2200 })
      }
    } finally {
      this.processing = false
    }
  }

  private async deleteOne(item: CartItem): Promise<void> {
    if (this.processing) {
      promptAction.showToast({ message: '购物车操作正在处理，请稍候', duration: 1500 })
      return
    }
    this.processing = true
    try {
      if (!await this.refreshFromDatabase(false)) {
        promptAction.showToast({ message: '购物车同步失败，请检查网络后重试', duration: 2200 })
        return
      }
      const currentItem: CartItem | undefined = this.findCurrentItem(item)
      if (currentItem === undefined) {
        this.selectedRowKeys = this.selectedRowKeys.filter((key: string) => key !== this.rowKey(item))
        promptAction.showToast({ message: '商品已不在购物车', duration: 1600 })
        return
      }
      const deletedItem: CartItem = {
        goods: currentItem.goods,
        quantity: currentItem.quantity,
        storeId: currentItem.storeId,
        storeName: currentItem.storeName,
        specId: currentItem.specId ?? 0,
        specName: currentItem.specName ?? '',
        price: currentItem.price ?? currentItem.goods.price,
        stock: currentItem.stock ?? currentItem.goods.stock ?? 0
      }
      let ok: boolean = false
      try {
        ok = await deleteCartItemRemote(currentItem.goods.id, currentItem.specId ?? 0, false)
      } catch (_) {
        ok = false
      }
      let reconciled: boolean = ok
      if (ok) {
        await this.useStoredCart()
      } else {
        reconciled = await this.refreshFromDatabase(false)
      }
      const afterQuantity: number = this.getCurrentRowQuantity(currentItem)
      if (reconciled && afterQuantity === 0) {
        this.selectedRowKeys = this.selectedRowKeys.filter((key: string) => key !== this.rowKey(currentItem))
        this.showUndo(deletedItem)
      } else if (!reconciled) {
        promptAction.showToast({ message: '删除结果待确认，请稍后刷新购物车', duration: 2400 })
      } else if (afterQuantity !== deletedItem.quantity) {
        promptAction.showToast({ message: '商品数量已变化，请以当前购物车为准', duration: 2400 })
      } else {
        promptAction.showToast({ message: '删除商品失败，请稍后重试', duration: 2200 })
      }
    } finally {
      this.processing = false
    }
  }

  private showUndo(item: CartItem): void {
    this.clearUndo()
    this.pendingUndoItem = item
    this.undoMessage = `已移除「${item.goods.name}」`
    this.armUndoTimer()
  }

  private armUndoTimer(): void {
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer)
    }
    this.undoTimer = setTimeout(() => { this.clearUndo() }, 6000)
  }

  private clearUndo(): void {
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer)
      this.undoTimer = -1
    }
    this.pendingUndoItem = null
    this.undoMessage = ''
  }

  private async undoDelete(): Promise<void> {
    if (this.processing || this.pendingUndoItem === null) {
      return
    }
    const item: CartItem = this.pendingUndoItem
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer)
      this.undoTimer = -1
    }
    this.processing = true
    let keepUndo: boolean = false
    try {
      if (!await this.refreshFromDatabase(false)) {
        keepUndo = true
        this.armUndoTimer()
        promptAction.showToast({ message: '购物车同步失败，可再次撤销', duration: 2200 })
        return
      }
      const beforeQuantity: number = this.getCurrentRowQuantity(item)
      if (beforeQuantity >= item.quantity) {
        promptAction.showToast({ message: `「${item.goods.name}」已在购物车`, duration: 1600 })
        return
      }
      const restoreItem: CartItem = {
        goods: item.goods,
        quantity: item.quantity - beforeQuantity,
        storeId: item.storeId,
        storeName: item.storeName,
        specId: item.specId ?? 0,
        specName: item.specName ?? '',
        price: item.price ?? item.goods.price,
        stock: item.stock ?? item.goods.stock ?? 0
      }
      let ok: boolean = false
      try {
        ok = await addCartItemRemote(restoreItem, false)
      } catch (_) {
        ok = false
      }
      let reconciled: boolean = ok
      if (ok) {
        await this.useStoredCart()
      } else {
        reconciled = await this.refreshFromDatabase(false)
      }
      const afterQuantity: number = this.getCurrentRowQuantity(item)
      if (reconciled && afterQuantity >= item.quantity) {
        promptAction.showToast({ message: `已恢复「${item.goods.name}」`, duration: 1600 })
      } else if (!reconciled) {
        promptAction.showToast({ message: '恢复结果待确认，请稍后查看购物车', duration: 2400 })
      } else if (afterQuantity !== beforeQuantity) {
        promptAction.showToast({ message: '商品数量已变化，请以当前购物车为准', duration: 2400 })
      } else {
        promptAction.showToast({ message: '恢复失败，商品可能已下架、规格失效或库存不足', duration: 2400 })
      }
    } finally {
      if (!keepUndo) {
        this.clearUndo()
      }
      this.processing = false
    }
  }

  private requestDeleteStore(storeId: number): void {
    const items: CartItem[] = this.getStoreItems(storeId)
    if (items.length === 0) {
      return
    }
    if (this.processing) {
      promptAction.showToast({ message: '\u8d2d\u7269\u8f66\u64cd\u4f5c\u6b63\u5728\u5904\u7406\uff0c\u8bf7\u7a0d\u5019', duration: 1500 })
      return
    }
    const quantity: number = items.reduce((sum: number, item: CartItem) => sum + item.quantity, 0)
    this.pendingDeleteMode = 1
    this.pendingDeleteStoreId = storeId
    this.pendingDeleteRowKeys = []
    this.deleteConfirmTitle = '删除店铺商品？'
    this.deleteConfirmContent = `确认删除「${this.getStoreName(storeId)}」的 ${items.length} 项商品（共 ${quantity} 件）？`
    this.showDeleteConfirm = true
  }

  private async deleteStore(storeId: number): Promise<void> {
    if (this.processing) {
      return
    }
    this.processing = true
    try {
      if (!await this.refreshFromDatabase(false)) {
        promptAction.showToast({ message: '\u8d2d\u7269\u8f66\u540c\u6b65\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u7f51\u7edc\u540e\u91cd\u8bd5', duration: 2200 })
        return
      }
      const items: CartItem[] = this.getStoreItems(storeId)
      const ids: number[] = items.map((current: CartItem) => current.goods.id)
      if (ids.length === 0) {
        return
      }
      let ok: boolean = false
      try {
        ok = await deleteCartItemsRemote(ids, false)
      } catch (_) {
        ok = false
      }
      let reconciled: boolean = ok
      if (ok) {
        await this.useStoredCart()
      } else {
        reconciled = await this.refreshFromDatabase(false)
      }
      const remaining: CartItem[] = items.filter((current: CartItem) => this.findCurrentItem(current) !== undefined)
      if (reconciled && remaining.length === 0) {
        const storeKeys: string[] = items.map((item: CartItem) => this.rowKey(item))
        this.selectedRowKeys = this.selectedRowKeys.filter((key: string) => storeKeys.indexOf(key) < 0)
        this.clearUndo()
        promptAction.showToast({ message: '\u5df2\u5220\u9664\u8be5\u5e97\u94fa\u7684\u8d2d\u7269\u8f66\u5546\u54c1', duration: 1600 })
      } else if (!reconciled) {
        promptAction.showToast({ message: '\u5220\u9664\u7ed3\u679c\u5f85\u786e\u8ba4\uff0c\u8bf7\u7a0d\u540e\u5237\u65b0\u8d2d\u7269\u8f66', duration: 2400 })
      } else {
        promptAction.showToast({ message: `部分商品未删除，仍有 ${remaining.length} 项保留在购物车`, duration: 2400 })
      }
    } finally {
      this.processing = false
    }
  }

  private requestDeleteSelected(): void {
    if (this.selectedRowKeys.length === 0) {
      promptAction.showToast({ message: '请先选择要删除的商品', duration: 1600 })
      return
    }
    if (this.processing) {
      promptAction.showToast({ message: '购物车操作正在处理，请稍候', duration: 1500 })
      return
    }
    const keys: string[] = this.selectedRowKeys.slice()
    const rows: CartItem[] = this.getCurrentCartItems().filter((item: CartItem) => keys.indexOf(this.rowKey(item)) >= 0)
    if (rows.length === 0) {
      this.selectedRowKeys = []
      return
    }
    const storeNames: string[] = []
    let quantity: number = 0
    for (let i = 0; i < rows.length; i++) {
      quantity += rows[i].quantity
      if (storeNames.indexOf(rows[i].storeName) < 0) {
        storeNames.push(rows[i].storeName)
      }
    }
    this.pendingDeleteMode = 2
    this.pendingDeleteStoreId = 0
    this.pendingDeleteRowKeys = keys
    this.deleteConfirmTitle = '删除选中商品？'
    this.deleteConfirmContent = `确认删除 ${rows.length} 项商品（共 ${quantity} 件）？涉及店铺：${storeNames.join('、')}`
    this.showDeleteConfirm = true
  }

  private async deleteSelected(keys: string[]): Promise<void> {
    if (keys.length === 0 || this.processing) {
      return
    }
    this.processing = true
    try {
      if (!await this.refreshFromDatabase(false)) {
        promptAction.showToast({ message: '购物车同步失败，请检查网络后重试', duration: 2200 })
        return
      }
      const rows: CartItem[] = this.getCurrentCartItems().filter((item: CartItem) => keys.indexOf(this.rowKey(item)) >= 0)
      if (rows.length === 0) {
        this.selectedRowKeys = this.selectedRowKeys.filter((key: string) => keys.indexOf(key) < 0)
        return
      }
      let allResponsesReceived: boolean = true
      for (let i = 0; i < rows.length; i++) {
        let ok: boolean = false
        try {
          ok = await deleteCartItemRemote(rows[i].goods.id, rows[i].specId ?? 0, false)
        } catch (_) {
          ok = false
        }
        if (!ok) {
          allResponsesReceived = false
        }
      }
      let reconciled: boolean = allResponsesReceived
      if (allResponsesReceived) {
        await this.useStoredCart()
      } else {
        reconciled = await this.refreshFromDatabase(false)
      }
      const currentKeys: string[] = this.getCurrentCartItems().map((item: CartItem) => this.rowKey(item))
      this.selectedRowKeys = this.selectedRowKeys.filter((key: string) => currentKeys.indexOf(key) >= 0)
      const remaining: CartItem[] = rows.filter((item: CartItem) => this.findCurrentItem(item) !== undefined)
      const deletedCount: number = rows.length - remaining.length
      if (reconciled && remaining.length === 0) {
        this.clearUndo()
        promptAction.showToast({ message: `已删除 ${rows.length} 项商品`, duration: 1600 })
      } else if (!reconciled) {
        promptAction.showToast({ message: '删除结果待确认，请稍后刷新购物车', duration: 2400 })
      } else {
        promptAction.showToast({ message: deletedCount > 0
          ? `已删除 ${deletedCount} 项，${remaining.length} 项仍保留` : '选中商品未删除，请稍后重试', duration: 2400 })
      }
    } finally {
      this.processing = false
    }
  }

  private cancelPendingDelete(): void {
    this.showDeleteConfirm = false
    this.pendingDeleteMode = 0
    this.pendingDeleteStoreId = 0
    this.pendingDeleteRowKeys = []
  }

  private async confirmPendingDelete(): Promise<void> {
    const mode: number = this.pendingDeleteMode
    const storeId: number = this.pendingDeleteStoreId
    const keys: string[] = this.pendingDeleteRowKeys.slice()
    this.cancelPendingDelete()
    if (mode === 1) {
      await this.deleteStore(storeId)
    } else if (mode === 2) {
      await this.deleteSelected(keys)
    }
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
    Stack() {
      Column() {
        PageHeader({ title: '购物车', showBack: false, topPadding: 0, actionLabel: this.editing ? '完成' : '管理',
          onAction: () => {
            this.editing = !this.editing
            if (!this.editing) { this.selectedRowKeys = [] }
          } })

        if (this.undoMessage !== '') {
          Row({ space: SPACING.SM }) {
            Text(this.undoMessage)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_PRIMARY)
              .maxLines(2)
              .layoutWeight(1)
            Button(this.processing ? '恢复中' : '撤销')
              .attributeModifier(new AppButtonStyle())
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.PRIMARY)
              .backgroundColor(Color.Transparent)
              .enabled(!this.processing)
              .id('cart-undo')
              .onClick(() => { this.undoDelete() })
          }
          .width('100%')
          .padding({ left: SPACING.MD, right: SPACING.SM })
          .margin({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM })
          .backgroundColor(COLORS.BG_WHITE)
          .border({ width: 1, color: COLORS.DIVIDER })
          .borderRadius(BORDER_RADIUS.MD)
        }

        if (!this.loggedIn) {
          EmptyState({ icon: $r('app.media.login_lock'), title: '暂无登录', actionLabel: '去登录', actionUrl: 'pages/Index' })
        } else if (this.getCurrentCartItems().length === 0) {
          EmptyState({ icon: $r('app.media.home_nav_cart'), title: '购物车是空的', actionLabel: '去逛店铺', onAction: () => { this.onBrowse() } })
        } else {
          Stack({ alignContent: Alignment.Bottom }) {
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
          ForEach(this.storeCards, (card: CartStoreCard) => {
            ListItem() {
              this.StoreCard(card)
            }
          }, (card: CartStoreCard) => `${card.storeId}`)
        }
        .width('100%')
        .height('100%')
        .clipContent(ContentClipMode.BOUNDARY)
        .contentEndOffset(FloatingTabBarTheme.CONTENT_INSET + this.bottomInset + 4 + this.actionBarHeight + SPACING.MD)
        .scrollBar(BarState.Off)
        .backgroundColor(COLORS.BG_PRIMARY)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.MD })

        Row() {
          if (this.editing) {
            Text(`已选 ${this.selectedRowKeys.length} 件`)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_SECONDARY)
              .layoutWeight(1)
            Button('删除选中')
              .attributeModifier(new AppButtonStyle())
              .height(44)
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.ON_PRIMARY)
              .backgroundColor(COLORS.ERROR)
              .borderRadius(BORDER_RADIUS.ROUND)
              .onClick(() => { this.requestDeleteSelected() })
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
              .attributeModifier(new AppButtonStyle())
              .height(44)
              .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
              .backgroundColor(MODULE_COLOR.CART)
              .borderRadius(BORDER_RADIUS.ROUND)
              .id('cart-checkout')
              .onClick(() => { this.checkoutAll() })
          }
        }
        .width('75%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
        .backgroundColor(Color.Transparent)
        .backgroundEffect({ radius: FloatingTabBarTheme.GLASS_BLUR_RADIUS,
          saturation: FloatingTabBarTheme.GLASS_SATURATION, color: FloatingTabBarTheme.GLASS_COLOR })
        .borderRadius(22)
        .border({ width: 1, color: COLORS.DIVIDER })
        .margin({ bottom: FloatingTabBarTheme.CONTENT_INSET + this.bottomInset + 4 })
        .id('cart-action-bar')
        .onAreaChange((_: Area, area: Area) => {
          const height: number = Number(area.height)
          if (height > 0 && height !== this.actionBarHeight) { this.actionBarHeight = height }
        })
          }.width('100%').layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      if (this.showDeleteConfirm) {
        ConfirmDialog({
          title: this.deleteConfirmTitle,
          content: this.deleteConfirmContent,
          confirmText: '确认删除',
          cancelText: '取消',
          onConfirm: () => { this.confirmPendingDelete() },
          onCancel: () => { this.cancelPendingDelete() }
        })
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  StoreCard(card: CartStoreCard) {
    Column({ space: SPACING.SM }) {
      Row() {
        Image($r('app.media.login_store')).width(32).height(32).padding(5).objectFit(ImageFit.Contain)
          .backgroundColor(accentBg(accentIndexFromText(this.getStoreName(card.storeId))))
          .borderRadius(BORDER_RADIUS.SM)
        Text(this.getStoreName(card.storeId))
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(MODULE_COLOR.CART)
          .layoutWeight(1)
        Button('删除')
          .attributeModifier(new AppButtonStyle()).height(44)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.ERROR)
          .backgroundColor(COLORS.ERROR_LIGHT)
          .borderRadius(BORDER_RADIUS.ROUND)
          .onClick(() => { this.requestDeleteStore(card.storeId) })
      }
      ForEach(card.visibleItems, (item: CartItem) => {
        this.CartItemRow(item)
      }, (item: CartItem) => `${item.storeId}-${item.goods.id}-${item.specId ?? 0}`)

      if (card.items.length > 2) {
        Button(card.expanded ? '收起商品 ∧' : `展开其余 ${card.items.length - 2} 件商品 ∨`)
          .attributeModifier(new AppButtonStyle()).height(44).width('100%')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
          .backgroundColor(COLORS.BG_PRIMARY)
          .id(`cart-expand-${card.storeId}`)
          .accessibilityText(card.expanded ? '收起商品' : `展开其余 ${card.items.length - 2} 件商品`)
          .onClick(() => { this.toggleStore(card.storeId) })
      }
      Row() {
        Text(`共 ${card.items.reduce((sum: number, item: CartItem) => sum + item.quantity, 0)} 件`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).layoutWeight(1)
        Text(`小计 ¥${this.getStoreTotal(card.storeId).toFixed(2)}`)
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.PRICE_RED).maxLines(1)
      }.width('100%')
      // 凑单提示：未达起送价时给出差额与店内可凑单菜品
      if (this.getBundleHint(card.storeId) !== null) {
        this.BundleTipCard(this.getBundleHint(card.storeId)!)
      }
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(COLORS.BG_WHITE)
    .border({ width: 1, color: COLORS.DIVIDER })
    .id(`cart-store-${card.storeId}`)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  CartItemRow(item: CartItem) {
    Column({ space: SPACING.SM }) {
      Row({ space: SPACING.SM }) {
        if (this.editing) {
          Checkbox({ name: this.rowKey(item) })
            .select(this.isSelected(item)).width(44).height(44)
            .onChange(() => { this.toggleSelected(item) })
        }
        Image(merchantImageSource(item.goods.image)).alt(DEFAULT_MERCHANT_IMAGE)
          .width(60).height(60).objectFit(ImageFit.Contain)
          .backgroundColor(COLORS.BG_PRIMARY).borderRadius(BORDER_RADIUS.MD)
        Column({ space: SPACING.XS }) {
          Text(item.goods.name).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          if ((item.specName ?? '') !== '') {
            Text(`规格：${item.specName}`).fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_HINT).maxLines(2).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Row({ space: 4 }) {
        Text(`¥${(item.price ?? item.goods.price).toFixed(2)}`)
          .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
          .maxLines(1).layoutWeight(1)
        Button('删除').attributeModifier(new AppButtonStyle()).height(44)
          .padding({ left: 8, right: 8 }).fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT).backgroundColor(Color.Transparent)
          .onClick(() => { this.deleteOne(item) })
        Button({ type: ButtonType.Normal }) {
          Text('−').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            .textAlign(TextAlign.Center).width('100%')
        }.attributeModifier(new AppButtonStyle()).width(44).height(44).padding(0)
          .backgroundColor(COLORS.BG_PRIMARY)
          .id(`cart-minus-${item.goods.id}-${item.specId ?? 0}`)
          .accessibilityText(`减少${item.goods.name}`)
          .onClick(() => { this.changeQuantity(item, -1) })
        Text(this.getRowQuantity(item).toString()).fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY).width(28).textAlign(TextAlign.Center).maxLines(1)
          .id(`cart-qty-${item.goods.id}-${item.specId ?? 0}`)
        Button({ type: ButtonType.Normal }) {
          Text('+').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLORS.ON_PRIMARY)
            .textAlign(TextAlign.Center).width('100%')
        }.attributeModifier(new AppButtonStyle()).width(44).height(44).padding(0)
          .backgroundColor(COLORS.PRIMARY)
          .id(`cart-plus-${item.goods.id}-${item.specId ?? 0}`)
          .accessibilityText(`增加${item.goods.name}`)
          .onClick(() => { this.changeQuantity(item, 1) })
      }.width('100%')
    }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.SM })
    .id(`cart-row-${item.storeId}-${item.goods.id}-${item.specId ?? 0}`)
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
        Button('去凑单 ›')
          .attributeModifier(new AppButtonStyle())
          .height(44)
          .backgroundColor(Color.Transparent)
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
