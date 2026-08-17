/**
 * 管理端-平台管理入口页
 * 仅 ADMIN 可进入：平台分类/店铺/员工/订单/退款管理 + 数据概览
 * 各模块为独立页面，避免单页堆叠过长；退出登录后回到登录页
 */
import { User, UserRole, Category, RefundRecord } from '../model/Models'
import { logout } from '../service/AppStorageManager'
import { ApiResponse, get } from '../service/HttpClient'
import { fetchAdminRefundsApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

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

/** 入口卡片模型 */
class AdminEntryItem {
  icon: string = ''
  title: string = ''
  description: string = ''
  count: number = 0
  page: string = ''

  static create(icon: string, title: string, description: string, count: number, page: string): AdminEntryItem {
    const item: AdminEntryItem = new AdminEntryItem()
    item.icon = icon
    item.title = title
    item.description = description
    item.count = count
    item.page = page
    return item
  }
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
  @State refunds: RefundRecord[] = []
  @State employees: number = 0
  @State loading: boolean = false

  aboutToAppear(): void {
    logInfo('Page', '进入管理端入口页 AdminCenterPage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
  }

  // 从子管理页返回时刷新概览数据（分类/店铺/订单/退款数量保持最新）
  onPageShow(): void {
    if (this.loggedIn && this.user.role === UserRole.ADMIN) {
      this.refresh()
    }
  }

  async refresh(): Promise<void> {
    this.loading = true
    const categoryResp: ApiResponse<Category[]> = await get<Category[]>('/api/admin/categories')
    const storeResp: ApiResponse<AdminStore[]> = await get<AdminStore[]>('/api/admin/stores')
    const orderResp: ApiResponse<AdminOrder[]> = await get<AdminOrder[]>('/api/admin/orders')
    const employeeResp: ApiResponse<Object[]> = await get<Object[]>('/api/admin/employees')
    this.categories = categoryResp.code === 200 && categoryResp.data !== null ? categoryResp.data : []
    this.stores = storeResp.code === 200 && storeResp.data !== null ? storeResp.data : []
    this.orders = orderResp.code === 200 && orderResp.data !== null ? orderResp.data : []
    this.employees = employeeResp.code === 200 && employeeResp.data !== null ? employeeResp.data.length : 0
    this.refunds = await fetchAdminRefundsApi()
    this.loading = false
  }

  /** 待审批退款数量（入口卡片徽标）。 */
  private getPendingRefundCount(): number {
    return this.refunds.filter(r => r.status === 'PENDING').length
  }

  /** 四个后台模块入口卡片（数据源提取为方法，避免 ForEach 字面量闭包捕获问题）。 */
  private getAdminEntries(): AdminEntryItem[] {
    const entries: AdminEntryItem[] = [
      AdminEntryItem.create('📂', '分类管理', '平台分类的增删改', this.categories.length, 'pages/AdminCategoryPage'),
      AdminEntryItem.create('🏪', '店铺管理', '查看店铺与营业状态切换', this.stores.length, 'pages/AdminStorePage'),
      AdminEntryItem.create('👥', '员工管理', '商户账号创建、编辑与停用', this.employees, 'pages/AdminEmployeePage'),
      AdminEntryItem.create('🍽️', '商品监管', '搜索商品并强制上下架', 0, 'pages/AdminProductPage'),
      AdminEntryItem.create('🧑‍💼', '用户管理', '查看用户和商户账号状态', 0, 'pages/AdminUserPage'),
      AdminEntryItem.create('📦', '订单管理', '托管订单状态与退款', this.orders.length, 'pages/AdminOrderPage'),
      AdminEntryItem.create('💰', '退款审批', '处理用户退款申请', this.getPendingRefundCount(), 'pages/AdminRefundPage'),
      AdminEntryItem.create('📊', '平台统计', '查看平台订单、成交和热销商品', 0, 'pages/AdminStatisticsPage')
    ]
    return entries
  }

  build() {
    Column() {
      Row() {
        Text('退出').fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).onClick(() => {
          logout()
          router.replaceUrl({ url: 'pages/Index' })
        })
        Text('平台管理').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button(this.loading ? '加载中…' : '刷新').height(32).fontSize(FONT_SIZE.SM)
          .enabled(!this.loading)
          .onClick(() => { this.refresh() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          // 数据概览
          Row() {
            Column({ space: 4 }) {
              Text(this.categories.length.toString())
                .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
              Text('平台分类').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            }.layoutWeight(1).alignItems(HorizontalAlign.Center)
            Column({ space: 4 }) {
              Text(this.stores.length.toString())
                .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
              Text('店铺总数').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            }.layoutWeight(1).alignItems(HorizontalAlign.Center)
            Column({ space: 4 }) {
              Text(this.orders.length.toString())
                .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
              Text('订单总数').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            }.layoutWeight(1).alignItems(HorizontalAlign.Center)
            Column({ space: 4 }) {
              Text(this.getPendingRefundCount().toString())
                .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold)
                .fontColor(this.getPendingRefundCount() > 0 ? COLORS.ERROR : COLORS.PRIMARY)
              Text('待审批退款').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
            }.layoutWeight(1).alignItems(HorizontalAlign.Center)
          }
          .width('100%').padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)

          // 功能入口卡片
          ForEach(this.getAdminEntries(), (item: AdminEntryItem) => {
            this.EntryCard(item)
          }, (item: AdminEntryItem) => item.title)

          Text('管理端仅提供后台运营功能，不包含点餐、定位等用户端能力')
            .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%').textAlign(TextAlign.Center)
            .margin({ top: SPACING.MD })
        }
        .width('100%').padding(SPACING.LG)
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  /** 入口卡片（参数经方法作用域传递，规避 ArkTS ForEach 闭包捕获限制）。 */
  @Builder
  EntryCard(item: AdminEntryItem) {
    Row({ space: SPACING.MD }) {
      Text(item.icon).fontSize(32)
      Column({ space: 4 }) {
        Row({ space: SPACING.SM }) {
          Text(item.title).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          if (item.count > 0) {
            Text(item.count.toString())
              .fontSize(FONT_SIZE.XS).fontColor(Color.White)
              .backgroundColor(item.title === '退款审批' ? COLORS.ERROR : COLORS.PRIMARY)
              .borderRadius(BORDER_RADIUS.ROUND)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
        }
        Text(item.description).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(FONT_SIZE.XL).fontColor(COLORS.TEXT_HINT)
    }
    .width('100%').padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    .onClick(() => { router.pushUrl({ url: item.page }) })
  }
}
