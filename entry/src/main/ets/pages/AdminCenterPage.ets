/** 平台管理端：分类、店铺营业状态和托管订单退款。 */
import { User, UserRole, Category } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { ApiResponse, get, post, put } from '../service/HttpClient'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

interface AdminStore {
  id: number
  name: string
  status: number
  ownerId: number
  categoryId: number
}

interface AdminOrder {
  id: number
  orderNo: string
  storeName: string
  status: number
  payAmount: number
  escrowStatus?: number
}

interface AdminCategoryRequest {
  name: string
  icon: string
  color: string
}

interface AdminStoreStatusRequest {
  status: number
}

@Entry
@Component
export struct AdminCenterPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State categories: Category[] = []
  @State stores: AdminStore[] = []
  @State orders: AdminOrder[] = []
  @State categoryName: string = ''
  @State loading: boolean = false

  aboutToAppear(): void {
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  async refresh(): Promise<void> {
    this.loading = true
    const categoryResp: ApiResponse<Category[]> = await get<Category[]>('/api/admin/categories')
    const storeResp: ApiResponse<AdminStore[]> = await get<AdminStore[]>('/api/admin/stores')
    const orderResp: ApiResponse<AdminOrder[]> = await get<AdminOrder[]>('/api/admin/orders')
    this.categories = categoryResp.code === 200 && categoryResp.data !== null ? categoryResp.data : []
    this.stores = storeResp.code === 200 && storeResp.data !== null ? storeResp.data : []
    this.orders = orderResp.code === 200 && orderResp.data !== null ? orderResp.data : []
    this.loading = false
  }

  async createCategory(): Promise<void> {
    const name: string = this.categoryName.trim()
    if (name === '') {
      promptAction.showToast({ message: '请输入分类名称', duration: 1500 })
      return
    }
    const req: AdminCategoryRequest = { name: name, icon: '🍱', color: '#FF6B35' }
    const resp: ApiResponse<Category> = await post<Category>('/api/admin/categories', req)
    if (resp.code === 200) {
      this.categoryName = ''
      promptAction.showToast({ message: '分类创建成功', duration: 1500 })
      await this.refresh()
    }
  }

  async toggleStore(store: AdminStore): Promise<void> {
    const nextStatus: number = store.status === 1 ? 0 : 1
    const req: AdminStoreStatusRequest = { status: nextStatus }
    const resp: ApiResponse<void> = await put<void>(`/api/admin/stores/${store.id}/status`, req)
    if (resp.code === 200) {
      promptAction.showToast({ message: nextStatus === 1 ? '店铺已恢复营业' : '店铺已暂停营业', duration: 1500 })
      await this.refresh()
    }
  }

  async refund(order: AdminOrder): Promise<void> {
    const resp: ApiResponse<AdminOrder> = await put<AdminOrder>(`/api/admin/orders/${order.id}/refund`, undefined)
    if (resp.code === 200) {
      promptAction.showToast({ message: '订单已退款并关闭', duration: 1500 })
      await this.refresh()
    }
  }

  build() {
    Column() {
      Row() {
        Text('退出').fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).onClick(() => {
          logout()
          router.replaceUrl({ url: 'pages/Index' })
        })
        Text('平台管理').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('刷新').height(32).onClick(() => { this.refresh() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          Text('分类管理').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).width('100%')
          Row({ space: SPACING.SM }) {
            TextInput({ placeholder: '新增分类名称', text: this.categoryName })
              .layoutWeight(1).height(42).onChange((value: string) => { this.categoryName = value })
            Button('新增').height(42).onClick(() => { this.createCategory() })
          }.width('100%')
          ForEach(this.categories, (category: Category) => {
            Row() {
              Text(`${category.icon} ${category.name}`).layoutWeight(1).fontSize(FONT_SIZE.MD)
              Text(`#${category.id}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
            }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
          }, (category: Category) => category.id.toString())

          Text('店铺营业状态').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).width('100%')
          ForEach(this.stores, (store: AdminStore) => {
            Row() {
              Column() {
                Text(store.name).fontSize(FONT_SIZE.MD)
                Text(store.status === 1 ? '营业中' : '已暂停').fontSize(FONT_SIZE.SM)
                  .fontColor(store.status === 1 ? COLORS.SUCCESS : COLORS.ERROR)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button(store.status === 1 ? '暂停营业' : '恢复营业')
                .height(34).onClick(() => { this.toggleStore(store) })
            }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
          }, (store: AdminStore) => store.id.toString())

          Text('托管订单').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).width('100%')
          ForEach(this.orders, (order: AdminOrder) => {
            Row() {
              Column() {
                Text(`${order.storeName}  #${order.orderNo}`).fontSize(FONT_SIZE.MD)
                Text(`¥${order.payAmount.toFixed(2)}  状态 ${order.status}`).fontSize(FONT_SIZE.SM)
                  .fontColor(COLORS.TEXT_SECONDARY)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (order.status !== 4 && order.status !== 5) {
                Button('退款').height(34).onClick(() => { this.refund(order) })
              }
            }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
          }, (order: AdminOrder) => order.id.toString())
        }
        .width('100%').padding(SPACING.LG)
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
