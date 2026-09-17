/** 平台用户和商户账号管理：查看账号并启用/停用，不修改余额和业务数据。 */
import { AdminUser, User, UserRole } from '../model/Models'
import { fetchAdminUsersApi, updateAdminUserStatusApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { StatusBadge } from '../components/StatusBadge'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

@Entry
@Component
export struct AdminUserPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State users: AdminUser[] = []
  @State keyword: string = ''
  @State roleFilter: number = -1
  // -1 全部 / 1 已启用 / 0 已停用（后端 /api/admin/users 的 status 参数）
  @State statusFilter: number = -1
  @State loading: boolean = false
  // ForEach 键含 id 时，刷新回来的同 id 新对象会被复用而不重建行，
  // 表现为停用后按钮仍显示「停用」；用版本号拼进键强制重建。
  @State renderVersion: number = 0

  aboutToAppear(): void {
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入用户管理', duration: 1600 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      promptAction.showToast({ message: '账号数据正在刷新，请稍候', duration: 1200 })
      return
    }
    this.loading = true
    const role: number | undefined = this.roleFilter < 0 ? undefined : this.roleFilter
    const status: number | undefined = this.statusFilter < 0 ? undefined : this.statusFilter
    this.users = await fetchAdminUsersApi(role, status, this.keyword)
    this.renderVersion += 1
    this.loading = false
  }

  private async toggleStatus(item: AdminUser): Promise<void> {
    const next: number = item.status === 1 ? 0 : 1
    const ok: boolean = await updateAdminUserStatusApi(item.id, next)
    if (ok) {
      promptAction.showToast({ message: next === 1 ? '账号已启用' : '账号已停用', duration: 1400 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: '账号状态更新失败，请刷新后重试', duration: 1800 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('返回').fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.ADMIN).onClick(() => { router.back() })
        Text('用户管理').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.ADMIN).layoutWeight(1).textAlign(TextAlign.Center)
        Button(this.loading ? '加载中' : '刷新').height(32).fontSize(FONT_SIZE.SM)
          .onClick(() => { this.refresh() })
      }.width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 }).backgroundColor(MODULE_BG.ADMIN)

      Row({ space: SPACING.SM }) {
        TextInput({ placeholder: '搜索姓名或手机号', text: this.keyword }).layoutWeight(1).height(40)
          .onChange((value: string) => { this.keyword = value })
        Button('搜索').height(40).fontSize(FONT_SIZE.SM).onClick(() => { this.refresh() })
      }.width('100%').padding(SPACING.LG).backgroundColor(MODULE_BG.ADMIN)

      Row({ space: SPACING.MD }) {
        Text('角色').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        Button('全部').fontSize(FONT_SIZE.SM).backgroundColor(this.roleFilter === -1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.roleFilter === -1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.roleFilter = -1; this.refresh() })
        Button('用户').fontSize(FONT_SIZE.SM).backgroundColor(this.roleFilter === 0 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.roleFilter === 0 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.roleFilter = 0; this.refresh() })
        Button('商户').fontSize(FONT_SIZE.SM).backgroundColor(this.roleFilter === 1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.roleFilter === 1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.roleFilter = 1; this.refresh() })
      }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })

      Row({ space: SPACING.MD }) {
        Text('状态').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        Button('全部').id('admin-user-status-all').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === -1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === -1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = -1; this.refresh() })
        Button('已启用').id('admin-user-status-enabled').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 1; this.refresh() })
        Button('已停用').id('admin-user-status-disabled').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 0 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 0 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 0; this.refresh() })
      }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })

      // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在筛选行下方
      List({ space: SPACING.MD }) {
        if (this.users.length === 0) {
          ListItem() {
            Text(this.statusFilter === -1 && this.roleFilter === -1 ? '暂无账号数据' : '当前筛选条件下暂无账号')
              .width('100%').padding(SPACING.LG).fontColor(COLORS.TEXT_HINT)
          }
        }
        ForEach(this.users, (item: AdminUser) => {
          ListItem() {
            this.UserRow(item)
          }
        }, (item: AdminUser) => `${this.renderVersion}-${item.id}`)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  UserRow(item: AdminUser) {
    Row({ space: SPACING.MD }) {
      Text(item.username.substring(0, 1))
        .width(40).height(40).textAlign(TextAlign.Center)
        .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
        .fontColor(accentFg(accentIndexFromText(item.username)))
        .backgroundColor(accentBg(accentIndexFromText(item.username)))
        .borderRadius(BORDER_RADIUS.ROUND)
      Column({ space: SPACING.XS }) {
        Text(item.username).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        Text(`${item.phone}  ${item.role === 1 ? '商户' : '普通用户'}${item.role === 1 ? `  店铺${item.storeCount}家` : ''}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        StatusBadge({ text: item.status === 1 ? '正常' : '已停用', mode: item.status === 1 ? 'success' : 'gray' })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button(item.status === 1 ? '停用' : '启用').height(30).fontSize(FONT_SIZE.XS)
        .fontColor(item.status === 1 ? COLORS.ERROR : COLORS.SUCCESS)
        .onClick(() => { this.toggleStatus(item) })
    }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
  }
}
