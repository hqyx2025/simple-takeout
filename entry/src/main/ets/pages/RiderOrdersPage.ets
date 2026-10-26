import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { call } from '@kit.TelephonyKit'
/**
 * 我的配送单（四端改造）：骑手已接订单，取餐 / 送达
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, getOrderStatusText, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Order, OrderPageData, StoreItem, User, UserRole } from '../model/Models'
import { fetchRiderOrdersPageResultApi } from '../service/api/RiderApi'
import { fetchStoreDetailApi } from '../service/api/CatalogApi'
import { getAuthSessionEpoch, getAuthToken } from '../service/HttpClient'
import { pickupOrderRemote, deliverOrderRemote, getLastRemoteErrorMessage, startRiderLocationTimer, stopRiderLocationTimer } from '../service/AppStorageManager'
import { logInfo } from '../service/AppLogger'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'

@Entry
@Component
export struct RiderOrdersPage {
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

  @State orders: Order[] = []
  @State loading: boolean = false
  @State loadFailed: boolean = false
  @State acting: boolean = false
  @State actingOrderId: number = 0
  @State actingAction: string = ''
  @State currentPage: number = 1
  @State totalOrders: number = 0
  @State hasMoreOrders: boolean = false
  @State pendingDeliverId: number = 0
  @State deliverySummary: string = ''
  @State storeOrderId: number = 0
  @State selectedStore: StoreItem | null = null
  @State storeLoading: boolean = false
  @State storeFailed: boolean = false
  @State openingContact: boolean = false
  @State deliveredOrderIds: number[] = []
  @StorageLink('isLoggedIn') @Watch('onSessionChanged') loggedIn: boolean = false
  @StorageLink('authToken') @Watch('onSessionChanged') authToken: string = ''
  @StorageLink('user') @Watch('onSessionChanged') user: User = { id: 0, username: '', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER, balance: 0, coupons: [], orders: [], storeIds: [] }
  private ordersRequestVersion: number = 0
  private storeRequestVersion: number = 0
  private pageVersion: number = 0
  private pageActive: boolean = false
  private ownerId: number = 0
  private ownerEpoch: number = 0

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入我的配送单 RiderOrdersPage')
    this.ownerId = this.user.id
    this.ownerEpoch = getAuthSessionEpoch()
    if (!this.loggedIn || this.user.role !== UserRole.RIDER) {
      promptAction.showToast({ message: '仅骑手账号可以查看配送单', duration: 1600 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
  }

  onPageShow(): void {
    this.pageActive = true
    if (this.hasRiderSession()) { this.loadOrders() }
  }

  onPageHide(): void { this.clearPage() }

  aboutToDisappear(): void { this.clearPage() }

  onBackPress(): boolean {
    if (this.pendingDeliverId > 0) {
      this.closeDeliveryConfirmation()
      return true
    }
    return this.acting
  }

  private hasRiderSession(): boolean {
    return this.pageActive && this.loggedIn && this.user.role === UserRole.RIDER &&
      this.user.id === this.ownerId && this.ownerId > 0 && getAuthToken() !== '' &&
      this.ownerEpoch === getAuthSessionEpoch()
  }

  private canApplyResponse(epoch: number, version: number): boolean {
    return this.hasRiderSession() && epoch === getAuthSessionEpoch() && version === this.pageVersion
  }

  private onSessionChanged(): void {
    if (this.loggedIn && this.user.role === UserRole.RIDER && this.user.id === this.ownerId &&
      getAuthToken() !== '' && this.ownerEpoch === getAuthSessionEpoch()) { return }
    const wasActive: boolean = this.pageActive
    this.clearPage()
    if (wasActive) { router.replaceUrl({ url: 'pages/Index' }) }
  }

  private clearPage(): void {
    this.pageActive = false
    this.pageVersion += 1
    this.ordersRequestVersion += 1
    this.storeRequestVersion += 1
    this.orders = []
    this.loading = false
    this.loadFailed = false
    this.acting = false
    this.actingOrderId = 0
    this.actingAction = ''
    this.openingContact = false
    this.deliveredOrderIds = []
    this.totalOrders = 0
    this.hasMoreOrders = false
    this.storeOrderId = 0
    this.selectedStore = null
    this.storeLoading = false
    this.storeFailed = false
    this.closeDeliveryConfirmation()
  }

  private activeOrder(orderId: number): Order | undefined {
    if (!this.hasRiderSession()) { return undefined }
    return this.orders.find((order: Order) => order.id === orderId && !this.deliveredOrderIds.includes(orderId) &&
      (order.status === 2 || order.status === 3))
  }

  private closeDeliveryConfirmation(): void {
    this.pendingDeliverId = 0
    this.deliverySummary = ''
  }

  private askToDeliver(order: Order): void {
    const current: Order | undefined = this.activeOrder(order.id)
    if (this.acting || this.loading || current === undefined || current.status !== 3) { return }
    this.pendingDeliverId = current.id
    this.deliverySummary = `请确认餐品已交给 ${current.address.name || '收货人'}，或已放在双方约定的位置。\n无法联系或尚未完成交付时，请先不要确认送达。`
  }

  private confirmDelivery(): void {
    const current: Order | undefined = this.activeOrder(this.pendingDeliverId)
    this.closeDeliveryConfirmation()
    if (current === undefined || current.status !== 3 || this.acting) { return }
    this.deliver(current)
  }

  private async copyAddress(orderId: number, storeAddress: boolean = false): Promise<void> {
    const order: Order | undefined = this.activeOrder(orderId)
    if (order === undefined || this.acting) { return }
    const text: string = storeAddress
      ? (this.storeOrderId === orderId ? this.selectedStore?.address ?? '' : '') : order.address.detail
    if (text.trim() === '') {
      promptAction.showToast({ message: '地址暂未提供，请刷新订单后重试', duration: 1800 })
      return
    }
    const epoch: number = getAuthSessionEpoch()
    const version: number = this.pageVersion
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const property: pasteboard.PasteDataProperty = data.getProperty()
      property.shareOption = pasteboard.ShareOption.LOCALDEVICE
      data.setProperty(property)
      await pasteboard.getSystemPasteboard().setData(data)
      if (!this.canApplyResponse(epoch, version) || this.activeOrder(orderId) === undefined) { return }
      promptAction.showToast({ message: storeAddress ? '门店地址已复制' : '完整收货地址已复制', duration: 1600 })
    } catch (_) {
      if (this.canApplyResponse(epoch, version)) {
        promptAction.showToast({ message: '复制失败，可长按地址选择文字', duration: 1800 })
      }
    }
  }

  private async contactCustomer(orderId: number): Promise<void> {
    const order: Order | undefined = this.activeOrder(orderId)
    if (order === undefined || this.openingContact || this.acting) { return }
    const phone: string = order.address.phone.replace(/[\s()-]/g, '')
    if (!/^\+?[0-9]{5,20}$/.test(phone)) {
      promptAction.showToast({ message: '联系电话暂不可用，请刷新订单后重试', duration: 1800 })
      return
    }
    this.openingContact = true
    const epoch: number = getAuthSessionEpoch()
    const version: number = this.pageVersion
    try {
      await call.makeCall(this.getUIContext().getHostContext() as common.UIAbilityContext, phone)
    } catch (_) {
      if (this.canApplyResponse(epoch, version)) {
        promptAction.showToast({ message: '无法打开拨号界面，可长按联系电话复制后拨打', duration: 2500 })
      }
    } finally {
      if (this.canApplyResponse(epoch, version)) { this.openingContact = false }
    }
  }

  private async loadStore(orderId: number): Promise<void> {
    const order: Order | undefined = this.activeOrder(orderId)
    if (order === undefined || this.acting) { return }
    const epoch: number = getAuthSessionEpoch()
    const version: number = this.pageVersion
    const serial: number = ++this.storeRequestVersion
    this.storeOrderId = orderId
    this.selectedStore = null
    this.storeLoading = true
    this.storeFailed = false
    try {
      const store: StoreItem | null = await fetchStoreDetailApi(order.storeId)
      if (!this.canApplyResponse(epoch, version) || serial !== this.storeRequestVersion ||
        this.activeOrder(orderId) === undefined) { return }
      this.selectedStore = store
      this.storeFailed = store === null
    } catch (_) {
      if (this.canApplyResponse(epoch, version) && serial === this.storeRequestVersion) {
        this.storeFailed = true
      }
    } finally {
      if (this.canApplyResponse(epoch, version) && serial === this.storeRequestVersion) {
        this.storeLoading = false
      }
    }
  }

  private hasStoreCoordinates(): boolean {
    const latitude: number = this.selectedStore?.latitude ?? Number.NaN
    const longitude: number = this.selectedStore?.longitude ?? Number.NaN
    return Number.isFinite(latitude) && Number.isFinite(longitude) && latitude >= -90 && latitude <= 90 &&
      longitude >= -180 && longitude <= 180 && !(latitude === 0 && longitude === 0)
  }

  private async openStoreMap(orderId: number): Promise<void> {
    if (this.acting || this.activeOrder(orderId) === undefined || this.storeOrderId !== orderId || !this.hasStoreCoordinates()) { return }
    const store: StoreItem | null = this.selectedStore
    if (store === null) { return }
    const epoch: number = getAuthSessionEpoch()
    const version: number = this.pageVersion
    const url: string = `https://uri.amap.com/marker?position=${store.longitude},${store.latitude}&name=${encodeURIComponent(store.name)}&coordinate=gaode&callnative=0&src=jiandanwaimai`
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      await context.openLink(url)
    } catch (_) {
      if (this.canApplyResponse(epoch, version)) {
        promptAction.showToast({ message: '地图暂时无法打开，请复制门店地址后在地图中查找', duration: 2500 })
      }
    }
  }

  /**
   * 加载并排序配送单：
   * ① 需要操作的（取餐/送达）按 readyTime 升序排在最上面——越早出餐越先取；
   * ② 已完成的按 completeTime 降序排在下面——最近完成的最靠上。
   */
  private sortOrders(orders: Order[]): Order[] {
    const O = [...orders]
    O.sort((a: Order, b: Order) => {
      const aActive: boolean = a.status === 2 || a.status === 3
      const bActive: boolean = b.status === 2 || b.status === 3
      if (aActive && !bActive) {
        return -1
      }
      if (!aActive && bActive) {
        return 1
      }
      if (aActive) {
        const aReady: string = a.readyTime ?? ''
        const bReady: string = b.readyTime ?? ''
        return aReady.localeCompare(bReady)
      }
      const aDone: string = a.completeTime ?? a.createTime ?? ''
      const bDone: string = b.completeTime ?? b.createTime ?? ''
      return bDone.localeCompare(aDone)
    })
    return O
  }

  private async loadOrders(page: number = 1, append: boolean = false,
    showErrorToast: boolean = true): Promise<boolean> {
    if (!this.hasRiderSession()) { return false }
    const epoch: number = getAuthSessionEpoch()
    const version: number = this.pageVersion
    const requestVersion: number = this.ordersRequestVersion + 1
    this.ordersRequestVersion = requestVersion
    this.loading = true
    try {
      const result: OrderPageData | null = await fetchRiderOrdersPageResultApi(page, 30, showErrorToast)
      if (!this.canApplyResponse(epoch, version) || requestVersion !== this.ordersRequestVersion) {
        return false
      }
      if (result === null) {
        if (this.orders.length === 0) {
          this.loadFailed = true
        }
        return false
      }
      this.loadFailed = false
      const combined: Order[] = append ? this.orders.concat(result.list) : result.list
      this.orders = this.sortOrders(combined)
      this.currentPage = result.page
      this.totalOrders = result.total
      this.hasMoreOrders = result.hasMore
      if (this.storeOrderId > 0 && this.activeOrder(this.storeOrderId) === undefined) {
        this.storeRequestVersion += 1
        this.storeOrderId = 0
        this.selectedStore = null
        this.storeLoading = false
      }
      if (this.pendingDeliverId > 0 && this.activeOrder(this.pendingDeliverId)?.status !== 3) {
        this.closeDeliveryConfirmation()
      }
      // 全局定时器按「有无配送中订单」开关，切页不中断
      if (this.orders.some((order: Order) => order.status === 3)) {
        startRiderLocationTimer()
      } else {
        stopRiderLocationTimer()
      }
      return true
    } finally {
      if (this.canApplyResponse(epoch, version) && requestVersion === this.ordersRequestVersion) {
        this.loading = false
      }
    }
  }

  private async loadMoreOrders(): Promise<void> {
    if (this.loading || this.acting || !this.hasMoreOrders) {
      return
    }
    await this.loadOrders(this.currentPage + 1, true)
  }

  private async pickup(order: Order): Promise<void> {
    if (this.acting || this.activeOrder(order.id)?.status !== 2) {
      return
    }
    this.acting = true
    this.actingOrderId = order.id
    this.actingAction = 'pickup'
    const epoch: number = getAuthSessionEpoch()
    const version: number = this.pageVersion
    try {
      let ok: boolean = false
      try {
        ok = await pickupOrderRemote(order.id, false)
      } catch (_) {
        ok = false
      }
      const actionError: string = getLastRemoteErrorMessage()
      if (!this.canApplyResponse(epoch, version)) { return }
      const refreshed: boolean = await this.loadOrders(1, false, false)
      if (!this.canApplyResponse(epoch, version)) { return }
      const latest: Order | undefined = refreshed
        ? this.orders.find((current: Order) => current.id === order.id) : undefined
      const advanced: boolean = latest !== undefined && latest.status === 3
      if (latest !== undefined && (latest.status === 4 || latest.status === 6)) {
        promptAction.showToast({ message: '订单履约已结束，无需再次取餐', duration: 1800 })
      } else if (ok || advanced) {
        promptAction.showToast({ message: '已取餐，开始配送', duration: 1500 })
      } else if (!refreshed || latest === undefined) {
        promptAction.showToast({ message: '取餐结果待确认，请稍后刷新配送单', duration: 2500 })
      } else {
        promptAction.showToast({
          message: actionError === '' ? '取餐失败，请确认订单状态' : actionError,
          duration: 2500
        })
      }
    } finally {
      if (this.canApplyResponse(epoch, version)) {
        this.acting = false
        this.actingOrderId = 0
        this.actingAction = ''
      }
    }
  }

  private async deliver(order: Order): Promise<void> {
    if (this.acting || this.activeOrder(order.id)?.status !== 3) {
      return
    }
    this.acting = true
    this.actingOrderId = order.id
    this.actingAction = 'deliver'
    const epoch: number = getAuthSessionEpoch()
    const version: number = this.pageVersion
    try {
      let ok: boolean = false
      try {
        ok = await deliverOrderRemote(order.id, false)
      } catch (_) {
        ok = false
      }
      const actionError: string = getLastRemoteErrorMessage()
      if (!this.canApplyResponse(epoch, version)) { return }
      // 送达已由服务端确认时先关闭联系入口，即使随后列表刷新失败也不继续暴露收货信息。
      if (ok) { this.deliveredOrderIds = this.deliveredOrderIds.concat([order.id]) }
      const refreshed: boolean = await this.loadOrders(1, false, false)
      if (!this.canApplyResponse(epoch, version)) { return }
      const latest: Order | undefined = refreshed
        ? this.orders.find((current: Order) => current.id === order.id) : undefined
      const advanced: boolean = latest !== undefined && (latest.status === 4 || latest.status === 6)
      if (ok || advanced) {
        promptAction.showToast({ message: '已送达', duration: 1500 })
      } else if (!refreshed || latest === undefined) {
        promptAction.showToast({ message: '送达结果待确认，请稍后刷新配送单', duration: 2500 })
      } else {
        promptAction.showToast({
          message: actionError === '' ? '送达失败，请确认订单状态' : actionError,
          duration: 2500
        })
      }
    } finally {
      if (this.canApplyResponse(epoch, version)) {
        this.acting = false
        this.actingOrderId = 0
        this.actingAction = ''
      }
    }
  }

  build() {
    Stack() {
      Column() {
      PageHeader({ title: '我的配送单', backText: '‹ 返回', backId: 'rider-orders-back', titleColor: COLORS.TEXT_PRIMARY, headerBgColor: COLORS.BG_PRIMARY, actionLabel: '刷新', onAction: () => { if (!this.acting) { this.loadOrders() } }, onBack: () => { if (!this.acting) { router.back() } } })

      if (this.loading) {
        Column() {
          Text('正在加载配送单…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.loadFailed) {
        Column({ space: SPACING.MD }) {
          Text('配送单暂时无法加载').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_PRIMARY)
          Text('请检查网络后重试').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
          Button('重新加载')
            .attributeModifier(new AppButtonStyle()).height(44)
            .id('rider-orders-retry')
            .onClick(() => { this.loadOrders() })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.orders.length === 0) {
        Column() {
          Image($r('app.media.login_rider')).width(60).height(60).objectFit(ImageFit.Contain).margin({ top: 40 })
          Text('暂无配送单').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
        }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
        List({ space: SPACING.SM }) {
          ForEach(this.orders, (order: Order) => {
            ListItem() {
              this.OrderCard(order)
            }
          }, (order: Order) => `${order.id}-${order.status}-${order.escrowStatus ?? 0}-${this.deliveredOrderIds.includes(order.id)}-${order.address.detail}-${order.address.phone}`)
          ListItem() {
            Row({ space: SPACING.SM }) {
              Text(`已显示 ${this.orders.length} / ${this.totalOrders}`)
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
              if (this.hasMoreOrders) {
                Button(this.loading ? '加载中' : '加载更多')
                  .attributeModifier(new AppButtonStyle()).height(44).fontSize(FONT_SIZE.XS)
                  .enabled(!this.loading).id('rider-order-load-more')
                  .onClick(() => { this.loadMoreOrders() })
              }
            }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.MD })
          }
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
      if (this.pendingDeliverId > 0) {
        ConfirmDialog({
          title: '确认餐品已交付',
          content: this.deliverySummary,
          confirmText: '确认已交付',
          cancelText: '尚未交付',
          onConfirm: () => { this.confirmDelivery() },
          onCancel: () => { this.closeDeliveryConfirmation() }
        }).id('rider-deliver-confirm-dialog')
      }
    }.width('100%').height('100%')
  }

  @Builder
  StoreLocation(order: Order) {
    Column({ space: SPACING.SM }) {
      if (this.storeOrderId !== order.id) {
        Button('查看取餐地点')
          .attributeModifier(new AppButtonStyle()).height(44).width('100%')
          .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
          .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(BORDER_RADIUS.MD)
          .enabled(!this.acting)
          .id(`rider-store-location-${order.id}`)
          .onClick(() => { this.loadStore(order.id) })
      } else if (this.storeLoading) {
        Text('正在读取门店地址…')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
      } else if (this.storeFailed) {
        Text('门店位置暂时无法读取，请重试')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
        Button('重试门店位置')
          .attributeModifier(new AppButtonStyle()).height(44).width('100%')
          .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
          .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(BORDER_RADIUS.MD)
          .enabled(!this.acting)
          .id(`rider-store-retry-${order.id}`)
          .onClick(() => { this.loadStore(order.id) })
      } else if (this.selectedStore !== null) {
        Text(`取餐地点：${this.selectedStore?.address?.trim() || '门店暂未提供文字地址'}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY).width('100%')
          .copyOption(CopyOptions.LocalDevice).id(`rider-store-address-${order.id}`)
        if (!this.hasStoreCoordinates()) {
          Text('门店未提供地图坐标，可复制地址后在地图中查找并核实。')
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
        }
        Row({ space: SPACING.SM }) {
          if ((this.selectedStore?.address ?? '').trim() !== '') {
            Button('复制门店地址')
              .attributeModifier(new AppButtonStyle()).height(44).layoutWeight(1)
              .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
              .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(BORDER_RADIUS.MD)
              .enabled(!this.acting)
              .id(`rider-copy-store-${order.id}`)
              .onClick(() => { this.copyAddress(order.id, true) })
          }
          if (this.hasStoreCoordinates()) {
            Button('地图查看门店')
              .attributeModifier(new AppButtonStyle()).height(44).layoutWeight(1)
              .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
              .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(BORDER_RADIUS.MD)
              .enabled(!this.acting)
              .id(`rider-map-store-${order.id}`)
              .onClick(() => { this.openStoreMap(order.id) })
          }
        }.width('100%')
      }
    }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.SM })
  }

  @Builder
  OrderCard(order: Order) {
    Column({ space: SPACING.XS }) {
      Row({ space: SPACING.SM }) {
        Text(order.storeName.substring(0, 1))
          .width(32).height(32).textAlign(TextAlign.Center)
          .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
          .fontColor(accentFg(accentIndexFromText(order.storeName)))
          .backgroundColor(accentBg(accentIndexFromText(order.storeName)))
          .borderRadius(BORDER_RADIUS.MD)
        Text(order.storeName)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.deliveredOrderIds.includes(order.id) && order.status === 3 ? '已送达，待刷新' :
          order.status === 2 ? '待取餐' : getOrderStatusText(order.status, order.escrowStatus ?? 0))
          .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.RIDER).fontWeight(FontWeight.Bold)
          .id(`rider-order-status-${order.id}`)
      }.width('100%')

      if ((order.status === 2 || order.status === 3) && !this.deliveredOrderIds.includes(order.id)) {
        Text(order.status === 2 ? '下一步：前往门店，核对餐品后取餐' : '下一步：送往收货地址，交付后确认送达')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_PRIMARY).width('100%')
          .padding({ top: SPACING.SM, bottom: SPACING.SM })
        this.StoreLocation(order)
        if (order.address.name.trim() !== '' || order.address.phone.trim() !== '') {
          Text(`收货：${order.address.name} ${order.address.phone}`.trim())
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }
        if (order.address.detail.trim() !== '') {
          Text(`地址：${order.address.detail}`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
            .copyOption(CopyOptions.LocalDevice).id(`rider-recipient-address-${order.id}`)
        }
        Row({ space: SPACING.SM }) {
          if (order.address.phone.trim() !== '') {
            Button(this.openingContact ? '正在打开拨号…' : '联系用户')
              .attributeModifier(new AppButtonStyle()).height(44).layoutWeight(1)
              .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
              .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(BORDER_RADIUS.MD)
              .enabled(!this.openingContact && !this.acting).id(`rider-contact-${order.id}`)
              .onClick(() => { this.contactCustomer(order.id) })
          }
          if (order.address.detail.trim() !== '') {
            Button('复制收货地址')
              .attributeModifier(new AppButtonStyle()).height(44).layoutWeight(1)
              .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
              .border({ width: 1, color: COLORS.DIVIDER }).borderRadius(BORDER_RADIUS.MD)
              .enabled(!this.acting)
              .id(`rider-copy-address-${order.id}`)
              .onClick(() => { this.copyAddress(order.id) })
          }
        }.width('100%').padding({ top: SPACING.SM, bottom: SPACING.SM })
        if (order.address.name.trim() === '' && order.address.phone.trim() === '' &&
          order.address.detail.trim() === '') {
          Text('收货信息暂时无法加载，请刷新后重试')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR).width('100%')
        }
      } else if (order.status === 4 || order.status === 5 || order.status === 6 || this.deliveredOrderIds.includes(order.id)) {
        Text('履约结束，收货信息已隐藏')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
          .id(`rider-contact-hidden-${order.id}`)
      } else {
        Text('当前状态暂不显示收货信息')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
      }

      Row() {
        Text(`¥${order.payAmount.toFixed(2)} · ${order.createTime}`)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).layoutWeight(1)
        if (order.status === 2) {
          Button(this.acting && this.actingOrderId === order.id && this.actingAction === 'pickup' ? '取餐中…' : '取餐')
            .attributeModifier(new AppButtonStyle()).height(44).fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY).backgroundColor(MODULE_COLOR.RIDER)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.acting)
            .id(`rider-pickup-${order.id}`)
            .onClick(() => { this.pickup(order) })
        } else if (order.status === 3 && !this.deliveredOrderIds.includes(order.id)) {
          Button(this.acting && this.actingOrderId === order.id && this.actingAction === 'deliver' ? '送达中…' : '送达')
            .attributeModifier(new AppButtonStyle()).height(44).fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.ON_PRIMARY).backgroundColor(COLORS.SUCCESS)
            .borderRadius(BORDER_RADIUS.ROUND)
            .enabled(!this.acting)
            .id(`rider-deliver-${order.id}`)
            .onClick(() => { this.askToDeliver(order) })
        }
      }.width('100%')
    }
      .attributeModifier(new AppCardStyle())
    .width('100%').padding(SPACING.LG)
    .id(`rider-order-card-${order.id}`)
  }
}
