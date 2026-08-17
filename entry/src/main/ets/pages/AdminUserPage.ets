/** 平台用户和商户账号管理：查看账号并启用/停用，不修改余额和业务数据。 */
import { AdminUser, User, UserRole } from '../model/Models'
import { fetchAdminUsersApi, updateAdminUserStatusApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
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
  @State loading: boolean = false

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
    this.users = await fetchAdminUsersApi(role, undefined, this.keyword)
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
        Text('返回').fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).onClick(() => { router.back() })
        Text('用户管理').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button(this.loading ? '加载中' : '刷新').height(32).fontSize(FONT_SIZE.SM)
          .onClick(() => { this.refresh() })
      }.width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 }).backgroundColor(COLORS.BG_WHITE)

      Row({ space: SPACING.SM }) {
        TextInput({ placeholder: '搜索姓名或手机号', text: this.keyword }).layoutWeight(1).height(40)
          .onChange((value: string) => { this.keyword = value })
        Button('搜索').height(40).fontSize(FONT_SIZE.SM).onClick(() => { this.refresh() })
      }.width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE)

      Row({ space: SPACING.MD }) {
        Button('全部').fontSize(FONT_SIZE.SM).backgroundColor(this.roleFilter === -1 ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
          .fontColor(this.roleFilter === -1 ? Color.White : COLORS.TEXT_SECONDARY).onClick(() => { this.roleFilter = -1; this.refresh() })
        Button('用户').fontSize(FONT_SIZE.SM).backgroundColor(this.roleFilter === 0 ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
          .fontColor(this.roleFilter === 0 ? Color.White : COLORS.TEXT_SECONDARY).onClick(() => { this.roleFilter = 0; this.refresh() })
        Button('商户').fontSize(FONT_SIZE.SM).backgroundColor(this.roleFilter === 1 ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
          .fontColor(this.roleFilter === 1 ? Color.White : COLORS.TEXT_SECONDARY).onClick(() => { this.roleFilter = 1; this.refresh() })
      }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })

      Scroll() {
        Column({ space: SPACING.MD }) {
          if (this.users.length === 0) {
            Text('暂无账号数据').width('100%').padding(SPACING.LG).fontColor(COLORS.TEXT_HINT)
          }
          ForEach(this.users, (item: AdminUser) => { this.UserRow(item) }, (item: AdminUser) => item.id.toString())
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  UserRow(item: AdminUser) {
    Row({ space: SPACING.MD }) {
      Column({ space: 4 }) {
        Text(item.username).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        Text(`${item.phone}  ${item.role === 1 ? '商户' : '普通用户'}${item.role === 1 ? `  店铺${item.storeCount}家` : ''}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(item.status === 1 ? '正常' : '已停用').fontSize(FONT_SIZE.XS)
          .fontColor(item.status === 1 ? COLORS.SUCCESS : COLORS.ERROR)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button(item.status === 1 ? '停用' : '启用').height(30).fontSize(FONT_SIZE.XS)
        .fontColor(item.status === 1 ? COLORS.ERROR : COLORS.SUCCESS)
        .onClick(() => { this.toggleStatus(item) })
    }.width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
  }
}
