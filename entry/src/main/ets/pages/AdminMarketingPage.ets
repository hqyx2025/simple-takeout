import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'
import { AdminSeckill, MarketingActivity, StoreItem, User, UserRole } from '../model/Models'
import {
  deleteAdminMarketingActivityApi, deleteAdminMarketingSeckillApi, fetchAdminMarketingActivitiesApi,
  fetchAdminMarketingSeckillsApi, fetchAdminMarketingStoresApi, updateAdminMarketingActivityStatusApi,
  updateAdminMarketingSeckillStatusApi
} from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG } from '../common/Constants'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

class AdminMarketingOption {
  value: string = ''

  constructor(value: string) {
    this.value = value
  }
}

@Entry
@Component
export struct AdminMarketingPage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) }).opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) }).opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) }).opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) }).opacity(0)
  }

  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State stores: StoreItem[] = []
  @State selectedStoreId: number = 0
  @State selectedStatus: number = -1
  @State activeTab: number = 0
  @State activities: MarketingActivity[] = []
  @State seckills: AdminSeckill[] = []
  @State loading: boolean = false
  @State showDeleteConfirm: boolean = false
  @State pendingDeleteId: number = 0
  @State pendingDeleteType: number = 0

  aboutToAppear(): void {
    logInfo('Page', '进入平台营销监管页 AdminMarketingPage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.loadStoresAndData()
  }

  private async loadStoresAndData(): Promise<void> {
    this.stores = await fetchAdminMarketingStoresApi()
    await this.refresh()
  }

  private async refresh(): Promise<void> {
    if (this.loading) return
    this.loading = true
    if (this.activeTab === 0) {
      this.activities = await fetchAdminMarketingActivitiesApi(this.selectedStoreId, this.selectedStatus)
    } else {
      this.seckills = await fetchAdminMarketingSeckillsApi(this.selectedStoreId, this.selectedStatus)
    }
    this.loading = false
  }

  private storeOptions(): AdminMarketingOption[] {
    const options: AdminMarketingOption[] = [new AdminMarketingOption('全部店铺')]
    for (let index = 0; index < this.stores.length; index++) {
      options.push(new AdminMarketingOption(this.stores[index].name))
    }
    return options
  }

  private selectedStoreName(): string {
    if (this.selectedStoreId === 0) return '全部店铺'
    const store: StoreItem | undefined = this.stores.find((item: StoreItem) => item.id === this.selectedStoreId)
    return store?.name ?? '全部店铺'
  }

  private selectedStatusName(): string {
    if (this.selectedStatus === 1) return '已上架'
    if (this.selectedStatus === 0) return '已下架'
    return '全部状态'
  }

  private async selectStore(index: number): Promise<void> {
    this.selectedStoreId = index === 0 ? 0 : this.stores[index - 1].id
    await this.refresh()
  }

  private async selectStatus(index: number): Promise<void> {
    this.selectedStatus = index === 1 ? 1 : index === 2 ? 0 : -1
    await this.refresh()
  }

  private async selectTab(index: number): Promise<void> {
    this.activeTab = index
    await this.refresh()
  }

  private async toggleActivity(item: MarketingActivity): Promise<void> {
    const nextStatus: number = item.status === 1 ? 0 : 1
    if (await updateAdminMarketingActivityStatusApi(item.id, nextStatus)) {
      promptAction.showToast({ message: nextStatus === 1 ? '活动已上架' : '活动已下架', duration: 1400 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '活动状态更新失败，请刷新后重试', duration: 1800 })
    }
  }

  private async toggleSeckill(item: AdminSeckill): Promise<void> {
    const nextStatus: number = item.status === 1 ? 0 : 1
    if (await updateAdminMarketingSeckillStatusApi(item.id, nextStatus)) {
      promptAction.showToast({ message: nextStatus === 1 ? '秒杀已上架' : '秒杀已下架', duration: 1400 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '秒杀状态更新失败，请刷新后重试', duration: 1800 })
    }
  }

  private requestDelete(type: number, id: number, sold: number = 0): void {
    if (type === 2 && sold > 0) {
      promptAction.showToast({ message: '已有销量的秒杀请先下架，不能删除', duration: 1800 })
      return
    }
    this.pendingDeleteType = type
    this.pendingDeleteId = id
    this.showDeleteConfirm = true
  }

  private async confirmDelete(): Promise<void> {
    const type: number = this.pendingDeleteType
    const id: number = this.pendingDeleteId
    this.showDeleteConfirm = false
    const deleted: boolean = type === 1
      ? await deleteAdminMarketingActivityApi(id)
      : await deleteAdminMarketingSeckillApi(id)
    if (deleted) {
      promptAction.showToast({ message: type === 1 ? '活动已删除' : '秒杀已删除', duration: 1400 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '删除失败，请刷新后重试', duration: 1800 })
    }
  }

  build() {
    Stack() {
    Column() {
      PageHeader({
        title: '营销监管', backId: 'admin-marketing-back', headerBgColor: COLORS.BG_PRIMARY,
        actionColor: MODULE_COLOR.ADMIN, actionLabel: this.loading ? '加载中' : '刷新',
        onBack: () => { router.back() }, onAction: () => { this.refresh() }
      })
      Column({ space: SPACING.SM }) {
        Row({ space: SPACING.SM }) {
          Button('营销活动').attributeModifier(new AppButtonStyle()).layoutWeight(1).height(40)
            .backgroundColor(this.activeTab === 0 ? MODULE_COLOR.ADMIN : MODULE_BG.ADMIN)
            .fontColor(this.activeTab === 0 ? COLORS.ON_PRIMARY : MODULE_COLOR.ADMIN)
            .onClick(() => { this.selectTab(0) })
          Button('限时秒杀').attributeModifier(new AppButtonStyle()).layoutWeight(1).height(40)
            .backgroundColor(this.activeTab === 1 ? MODULE_COLOR.ADMIN : MODULE_BG.ADMIN)
            .fontColor(this.activeTab === 1 ? COLORS.ON_PRIMARY : MODULE_COLOR.ADMIN)
            .onClick(() => { this.selectTab(1) })
        }.width('100%')
        Row({ space: SPACING.SM }) {
          Select(this.storeOptions()).value(this.selectedStoreName())
            .layoutWeight(1).onSelect((index: number) => { this.selectStore(index) })
          Select([new AdminMarketingOption('全部状态'), new AdminMarketingOption('已上架'), new AdminMarketingOption('已下架')])
            .value(this.selectedStatusName()).layoutWeight(1)
            .onSelect((index: number) => { this.selectStatus(index) })
        }.width('100%')
      }.padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })

      Scroll() {
        Column({ space: SPACING.SM }) {
          if (this.activeTab === 0) {
            Text(`营销活动 · ${this.activities.length} 条`).fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_HINT).width('100%')
            if (this.activities.length === 0 && !this.loading) {
              Text('暂无营销活动').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                .width('100%').padding(SPACING.LG)
            }
            ForEach(this.activities, (item: MarketingActivity) => {
              Column({ space: SPACING.SM }) {
                Row({ space: SPACING.SM }) {
                  Column({ space: SPACING.XS }) {
                    Text(item.title).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
                      .fontColor(COLORS.TEXT_PRIMARY).maxLines(2)
                    Text(`${item.type} · 店铺 #${item.storeId}`).fontSize(FONT_SIZE.XS)
                      .fontColor(COLORS.TEXT_SECONDARY)
                  }.layoutWeight(1)
                  StatusBadge({ text: item.status === 1 ? '已上架' : '已下架', mode: item.status === 1 ? 'success' : 'warning' })
                }.width('100%')
                Text(`${item.startTime} 至 ${item.endTime}`).fontSize(FONT_SIZE.XS)
                  .fontColor(COLORS.TEXT_HINT).width('100%')
                Row({ space: SPACING.SM }) {
                  Button(item.status === 1 ? '下架' : '上架').attributeModifier(new AppButtonStyle())
                    .layoutWeight(1).height(40).fontSize(FONT_SIZE.SM)
                    .backgroundColor(MODULE_BG.ADMIN).fontColor(MODULE_COLOR.ADMIN)
                    .onClick(() => { this.toggleActivity(item) })
                  Button('删除').attributeModifier(new AppButtonStyle()).layoutWeight(1).height(40)
                    .fontSize(FONT_SIZE.SM).backgroundColor(COLORS.ERROR_LIGHT).fontColor(COLORS.ERROR)
                    .onClick(() => { this.requestDelete(1, item.id) })
                }.width('100%')
              }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD)
            }, (item: MarketingActivity) => `activity-${item.id}`)
          } else {
            Text(`限时秒杀 · ${this.seckills.length} 条`).fontSize(FONT_SIZE.SM)
              .fontColor(COLORS.TEXT_HINT).width('100%')
            if (this.seckills.length === 0 && !this.loading) {
              Text('暂无秒杀活动').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                .width('100%').padding(SPACING.LG)
            }
            ForEach(this.seckills, (item: AdminSeckill) => {
              Column({ space: SPACING.SM }) {
                Row({ space: SPACING.SM }) {
                  Column({ space: SPACING.XS }) {
                    Text(`商品 #${item.goodsId} · ¥${item.price.toFixed(2)}`)
                      .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                    Text(`店铺 #${item.storeId} · 已售 ${item.sold}/${item.quota}`)
                      .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
                  }.layoutWeight(1)
                  StatusBadge({ text: item.status === 1 ? '已上架' : '已下架', mode: item.status === 1 ? 'success' : 'warning' })
                }.width('100%')
                Text(`${item.startTime} 至 ${item.endTime}`).fontSize(FONT_SIZE.XS)
                  .fontColor(COLORS.TEXT_HINT).width('100%')
                Row({ space: SPACING.SM }) {
                  Button(item.status === 1 ? '下架' : '上架').attributeModifier(new AppButtonStyle())
                    .layoutWeight(1).height(40).fontSize(FONT_SIZE.SM)
                    .backgroundColor(MODULE_BG.ADMIN).fontColor(MODULE_COLOR.ADMIN)
                    .onClick(() => { this.toggleSeckill(item) })
                  Button('删除').attributeModifier(new AppButtonStyle()).layoutWeight(1).height(40)
                    .fontSize(FONT_SIZE.SM).backgroundColor(COLORS.ERROR_LIGHT).fontColor(COLORS.ERROR)
                    .onClick(() => { this.requestDelete(2, item.id, item.sold) })
                }.width('100%')
              }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD)
            }, (item: AdminSeckill) => `seckill-${item.id}`)
          }
        }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XL })
      }.layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

    if (this.showDeleteConfirm) {
      ConfirmDialog({
        title: this.pendingDeleteType === 1 ? '删除营销活动' : '删除秒杀活动',
        content: '删除后无法恢复，确认继续吗？', confirmText: '删除', cancelText: '取消',
        onConfirm: () => { this.confirmDelete() },
        onCancel: () => { this.showDeleteConfirm = false }
      })
    }
    }.width('100%').height('100%')
  }
}
