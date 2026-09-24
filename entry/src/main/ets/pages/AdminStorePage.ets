/**
 * 管理端-店铺管理页（大纲 9.3 商户管理-经营状态）
 * 查看全部店铺并切换营业状态（营业中/已暂停），仅 ADMIN 可进入
 */
import { User, UserRole } from '../model/Models'
import { ApiResponse, get, put } from '../service/HttpClient'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { StatusBadge } from '../components/StatusBadge'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

interface AdminStore {
  id: number
  name: string
  status: number
  recommended: number
  ownerId: number
  categoryId: number
}

interface AdminStoreStatusRequest {
  status: number
}

interface AdminStoreRecommendRequest {
  recommended: number
}

@Entry
@Component
export struct AdminStorePage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State stores: AdminStore[] = []
  // -1 全部 / 1 营业中 / 0 已暂停（列表已在内存中，本地筛选即可，无需后端参数）
  @State statusFilter: number = -1
  @State displayStores: AdminStore[] = []
  // 刷新回来的同 id 新对象会被 ForEach 复用，营业/推荐状态变更后按钮不刷新。
  @State renderVersion: number = 0

  aboutToAppear(): void {
    logInfo('Page', '进入管理端店铺管理页 AdminStorePage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  async refresh(): Promise<void> {
    const resp: ApiResponse<AdminStore[]> = await get<AdminStore[]>('/api/admin/stores')
    this.stores = resp.code === 200 && resp.data !== null ? resp.data : []
    this.applyFilter()
  }

  /** 按营业状态筛选（显式计算，避免渲染期 getter 求值）。 */
  private applyFilter(): void {
    if (!Array.isArray(this.stores)) {
      this.displayStores = []
      return
    }
    this.displayStores = this.statusFilter === -1
      ? this.stores
      : this.stores.filter((store: AdminStore) => store.status === this.statusFilter)
    this.renderVersion += 1
  }

  /** 切换店铺营业状态：1 营业中 ↔ 0 已暂停（后端校验 status 合法性）。 */
  async toggleStore(store: AdminStore): Promise<void> {
    const nextStatus: number = store.status === 1 ? 0 : 1
    const req: AdminStoreStatusRequest = { status: nextStatus }
    const resp: ApiResponse<Object> = await put<Object>(`/api/admin/stores/${store.id}/status`, req)
    if (resp.code === 200) {
      promptAction.showToast({ message: nextStatus === 1 ? '店铺已恢复营业' : '店铺已暂停营业', duration: 1500 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: resp.message || '店铺营业状态更新失败，请稍后重试', duration: 1800 })
    }
  }

  async toggleRecommend(store: AdminStore): Promise<void> {
    const nextRecommended: number = store.recommended === 1 ? 0 : 1
    const req: AdminStoreRecommendRequest = { recommended: nextRecommended }
    const resp: ApiResponse<Object> = await put<Object>(`/api/admin/stores/${store.id}/recommend`, req)
    if (resp.code === 200) {
      promptAction.showToast({ message: nextRecommended === 1 ? '已推荐到发现页' : '已取消发现页推荐', duration: 1500 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: resp.message || '店铺推荐状态更新失败，请稍后重试', duration: 1800 })
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      PageHeader({
        title: '店铺管理',
        backId: 'admin-store-back',
        headerBgColor: MODULE_BG.ADMIN,
        actionColor: MODULE_COLOR.ADMIN,
        actionLabel: '刷新',
        onBack: () => { router.back() },
        onAction: () => { this.refresh() }
      })

      Row({ space: SPACING.MD }) {
        Text('状态').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        Button('全部').id('admin-store-status-all').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === -1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === -1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = -1; this.applyFilter() })
        Button('营业中').id('admin-store-status-open').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 1; this.applyFilter() })
        Button('已暂停').id('admin-store-status-closed').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 0 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 0 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 0; this.applyFilter() })
      }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })

      // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在筛选行下方
      List({ space: SPACING.MD }) {
        ListItem() {
          Text('推荐状态决定是否展示在用户发现页；距离超过 2 公里的店铺不会出现在附近推荐中。')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
        }

        if (this.displayStores.length === 0) {
          ListItem() {
            Text(this.statusFilter === -1 ? '暂无店铺' : '当前筛选条件下暂无店铺')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%').padding(SPACING.MD)
          }
        }
        ForEach(this.displayStores, (store: AdminStore) => {
          ListItem() {
            Row({ space: SPACING.MD }) {
              Text(store.name.substring(0, 1))
                .width(40).height(40).textAlign(TextAlign.Center)
                .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
                .fontColor(accentFg(accentIndexFromText(store.name)))
                .backgroundColor(accentBg(accentIndexFromText(store.name)))
                .borderRadius(BORDER_RADIUS.ROUND)
              Column({ space: SPACING.XS }) {
                Text(store.name).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
                StatusBadge({ text: store.status === 1 ? '营业中' : '已暂停', mode: store.status === 1 ? 'success' : 'gray' })
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Column({ space: SPACING.XS }) {
                Button(store.recommended === 1 ? '取消推荐' : '推荐到发现')
                  .height(32).fontSize(FONT_SIZE.XS)
                  .fontColor(store.recommended === 1 ? MODULE_COLOR.ADMIN : COLORS.TEXT_WHITE)
                  .backgroundColor(store.recommended === 1 ? COLORS.TAG_BG : MODULE_COLOR.ADMIN)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.toggleRecommend(store) })
                Button(store.status === 1 ? '暂停营业' : '恢复营业')
                  .height(32).fontSize(FONT_SIZE.XS)
                  .fontColor(store.status === 1 ? COLORS.WARNING : COLORS.TEXT_WHITE)
                  .backgroundColor(store.status === 1 ? COLORS.TAG_BG : COLORS.SUCCESS)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.toggleStore(store) })
              }
            }
            .width('100%').padding(SPACING.MD)
            .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
          }
        }, (store: AdminStore) => `${this.renderVersion}-${store.id}`)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
