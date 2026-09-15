/** 平台商品监管：搜索全部店铺商品、强制上下架和删除违规商品。 */
import { AdminProduct, User, UserRole } from '../model/Models'
import { deleteAdminProductApi, fetchAdminProductsApi, updateAdminProductStatusApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { StatusBadge } from '../components/StatusBadge'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { ConfirmDialog } from '../components/ConfirmDialog'

@Entry
@Component
export struct AdminProductPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State products: AdminProduct[] = []
  @State keyword: string = ''
  @State statusFilter: number = -1
  @State loading: boolean = false
  @State deletingId: number = 0
  @State showDeleteConfirm: boolean = false
  // 同 AdminUserPage：键只含 id 时刷新回来的新对象会被复用，强制上下架后按钮不刷新。
  @State renderVersion: number = 0

  aboutToAppear(): void {
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入商品监管', duration: 1600 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      promptAction.showToast({ message: '商品数据正在刷新，请稍候', duration: 1200 })
      return
    }
    this.loading = true
    const status: number | undefined = this.statusFilter < 0 ? undefined : this.statusFilter
    this.products = await fetchAdminProductsApi(this.keyword, status)
    this.renderVersion += 1
    this.loading = false
  }

  private async toggleStatus(product: AdminProduct): Promise<void> {
    const next: number = product.status === 1 ? 0 : 1
    const ok: boolean = await updateAdminProductStatusApi(product.id, next)
    if (ok) {
      promptAction.showToast({ message: next === 1 ? '商品已强制上架' : '商品已强制下架', duration: 1400 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '商品状态更新失败，请刷新后重试', duration: 1800 })
    }
  }

  private async deleteProduct(): Promise<void> {
    const ok: boolean = await deleteAdminProductApi(this.deletingId)
    this.showDeleteConfirm = false
    this.deletingId = 0
    if (ok) {
      promptAction.showToast({ message: '商品已删除', duration: 1400 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '商品删除失败，请刷新后重试', duration: 1800 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('返回').fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).onClick(() => { router.back() })
        Text('商品监管').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button(this.loading ? '加载中' : '刷新').height(32).fontSize(FONT_SIZE.SM)
          .onClick(() => { this.refresh() })
      }.width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 }).backgroundColor(COLORS.BG_WHITE)

      Row({ space: SPACING.SM }) {
        TextInput({ placeholder: '搜索商品名或店铺名', text: this.keyword })
          .layoutWeight(1).height(40).onChange((value: string) => { this.keyword = value })
        Button('搜索').height(40).fontSize(FONT_SIZE.SM).onClick(() => { this.refresh() })
      }.width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE)

      Row({ space: SPACING.MD }) {
        Button('全部').fontSize(FONT_SIZE.SM).backgroundColor(this.statusFilter === -1 ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === -1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = -1; this.refresh() })
        Button('上架').fontSize(FONT_SIZE.SM).backgroundColor(this.statusFilter === 1 ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 1; this.refresh() })
        Button('下架').fontSize(FONT_SIZE.SM).backgroundColor(this.statusFilter === 0 ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 0 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 0; this.refresh() })
      }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })

      // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在筛选行下方
      List({ space: SPACING.MD }) {
        if (this.products.length === 0) {
          ListItem() {
            Text(this.statusFilter === -1 && this.keyword.trim() === '' ? '暂无商品数据' : '当前筛选条件下暂无商品')
              .width('100%').padding(SPACING.LG).fontColor(COLORS.TEXT_HINT)
          }
        }
        ForEach(this.products, (product: AdminProduct) => {
          ListItem() {
            this.ProductRow(product)
          }
        }, (product: AdminProduct) => `${this.renderVersion}-${product.id}`)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })

      if (this.showDeleteConfirm) {
        ConfirmDialog({
          title: '删除商品', content: '删除后商品将不再出现在店铺商品列表中，历史订单快照不受影响。',
          confirmText: '确认删除', cancelText: '取消', onConfirm: () => { this.deleteProduct() },
          onCancel: () => { this.showDeleteConfirm = false }
        })
      }
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  ProductRow(product: AdminProduct) {
    Row({ space: SPACING.MD }) {
      Column({ space: SPACING.XS }) {
        Text(product.name).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        Text(`${product.storeName}  ¥${product.price.toFixed(2)}  月销${product.sales}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        StatusBadge({ text: product.status === 1 ? '上架中' : '已下架', mode: product.status === 1 ? 'success' : 'gray' })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Row({ space: SPACING.XS }) {
        Button(product.status === 1 ? '强制下架' : '强制上架').height(30).fontSize(FONT_SIZE.XS)
          .onClick(() => { this.toggleStatus(product) })
        Button('删除').height(30).fontSize(FONT_SIZE.XS).fontColor(COLORS.ERROR)
          .onClick(() => { this.deletingId = product.id; this.showDeleteConfirm = true })
      }
    }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
  }
}
