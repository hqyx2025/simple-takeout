/**
 * 管理端-店铺管理页（大纲 9.3 商户管理-经营状态）
 * 查看全部店铺并切换营业状态（营业中/已暂停），仅 ADMIN 可进入
 */
import { User, UserRole } from '../model/Models'
import { ApiResponse, get, put } from '../service/HttpClient'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
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
  }

  /** 切换店铺营业状态：1 营业中 ↔ 0 已暂停（后端校验 status 合法性）。 */
  async toggleStore(store: AdminStore): Promise<void> {
    const nextStatus: number = store.status === 1 ? 0 : 1
    const req: AdminStoreStatusRequest = { status: nextStatus }
    const resp: ApiResponse<Object> = await put<Object>(`/api/admin/stores/${store.id}/status`, req)
    if (resp.code === 200) {
      promptAction.showToast({ message: nextStatus === 1 ? '店铺已恢复营业' : '店铺已暂停营业', duration: 1500 })
      await this.refresh()
    }
  }

  async toggleRecommend(store: AdminStore): Promise<void> {
    const nextRecommended: number = store.recommended === 1 ? 0 : 1
    const req: AdminStoreRecommendRequest = { recommended: nextRecommended }
    const resp: ApiResponse<Object> = await put<Object>(`/api/admin/stores/${store.id}/recommend`, req)
    if (resp.code === 200) {
      promptAction.showToast({ message: nextRecommended === 1 ? '已推荐到发现页' : '已取消发现页推荐', duration: 1500 })
      await this.refresh()
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
        Text('店铺管理')
          .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button('刷新').height(32).fontSize(FONT_SIZE.SM).onClick(() => { this.refresh() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          Text('推荐状态决定是否展示在用户发现页；距离超过 2 公里的店铺不会出现在附近推荐中。')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')

          if (this.stores.length === 0) {
            Text('暂无店铺').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%').padding(SPACING.MD)
          }
          ForEach(this.stores, (store: AdminStore) => {
            Row({ space: SPACING.MD }) {
              Column({ space: 4 }) {
                Text(store.name).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
                Text(store.status === 1 ? '营业中' : '已暂停').fontSize(FONT_SIZE.SM)
                  .fontColor(store.status === 1 ? COLORS.SUCCESS : COLORS.ERROR)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Column({ space: SPACING.XS }) {
                Button(store.recommended === 1 ? '取消推荐' : '推荐到发现')
                  .height(32).fontSize(FONT_SIZE.XS)
                  .fontColor(store.recommended === 1 ? COLORS.PRIMARY : Color.White)
                  .backgroundColor(store.recommended === 1 ? COLORS.TAG_BG : COLORS.PRIMARY)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.toggleRecommend(store) })
                Button(store.status === 1 ? '暂停营业' : '恢复营业')
                  .height(32).fontSize(FONT_SIZE.XS)
                  .fontColor(store.status === 1 ? COLORS.WARNING : Color.White)
                  .backgroundColor(store.status === 1 ? '#FFF3E0' : COLORS.SUCCESS)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.toggleStore(store) })
              }
            }
            .width('100%').padding(SPACING.MD)
            .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
          }, (store: AdminStore) => store.id.toString())
        }
        .width('100%').padding(SPACING.LG)
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
