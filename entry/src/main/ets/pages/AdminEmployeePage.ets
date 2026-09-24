/** 管理端-员工账号管理：员工增删改中的新增、资料编辑和启停用。 */
import { AdminEmployee, User, UserRole } from '../model/Models'
import { createAdminEmployeeApi, fetchAdminEmployeesApi, updateAdminEmployeeApi, updateAdminEmployeeStatusApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { StatusBadge } from '../components/StatusBadge'
import { PageHeader } from '../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct AdminEmployeePage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State employees: AdminEmployee[] = []
  @State loading: boolean = false
  // 键只含 id 时，刷新回来的同 id 新对象会被复用，停用/改名后行内容不刷新。
  @State renderVersion: number = 0
  @State showForm: boolean = false
  // -1 全部 / 1 已启用 / 0 已停用（列表已在内存中，本地筛选即可）
  @State statusFilter: number = -1
  @State displayEmployees: AdminEmployee[] = []
  @State editingId: number = 0
  @State formUsername: string = ''
  @State formPhone: string = ''
  @State formPassword: string = ''

  aboutToAppear(): void {
    logInfo('Page', '进入员工管理页 AdminEmployeePage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入员工管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  async refresh(): Promise<void> {
    this.loading = true
    this.employees = await fetchAdminEmployeesApi()
    this.applyFilter()
    this.loading = false
  }

  /** 按启用状态筛选（显式计算，避免渲染期 getter 求值）。 */
  private applyFilter(): void {
    if (!Array.isArray(this.employees)) {
      this.displayEmployees = []
      return
    }
    this.displayEmployees = this.statusFilter === -1
      ? this.employees
      : this.employees.filter((employee: AdminEmployee) => employee.status === this.statusFilter)
    this.renderVersion += 1
  }

  private openCreate(): void {
    this.editingId = 0
    this.formUsername = ''
    this.formPhone = ''
    this.formPassword = ''
    this.showForm = true
  }

  private openEdit(employee: AdminEmployee): void {
    this.editingId = employee.id
    this.formUsername = employee.username
    this.formPhone = employee.phone
    this.formPassword = ''
    this.showForm = true
  }

  private closeForm(): void {
    this.showForm = false
    this.editingId = 0
  }

  private async saveEmployee(): Promise<void> {
    if (this.formUsername.trim() === '' || this.formPhone.trim() === '') {
      promptAction.showToast({ message: '姓名和手机号不能为空', duration: 1500 })
      return
    }
    const editing: boolean = this.editingId !== 0
    let ok: boolean = false
    if (!editing) {
      if (this.formPassword.length < 6) {
        promptAction.showToast({ message: '初始密码至少 6 位', duration: 1500 })
        return
      }
      ok = await createAdminEmployeeApi(this.formUsername.trim(), this.formPhone.trim(), this.formPassword)
    } else {
      ok = await updateAdminEmployeeApi(this.editingId, this.formUsername.trim(), this.formPhone.trim())
    }
    if (!ok) {
      promptAction.showToast({ message: '保存失败，请检查手机号或网络', duration: 1800 })
      return
    }
    this.closeForm()
    await this.refresh()
    promptAction.showToast({ message: editing ? '员工资料已更新' : '员工创建成功', duration: 1500 })
  }

  private async toggleStatus(employee: AdminEmployee): Promise<void> {
    const nextStatus: number = employee.status === 1 ? 0 : 1
    const ok: boolean = await updateAdminEmployeeStatusApi(employee.id, nextStatus)
    if (ok) {
      await this.refresh()
      promptAction.showToast({ message: nextStatus === 1 ? '员工已启用' : '员工已停用', duration: 1500 })
    } else {
      promptAction.showToast({ message: '员工状态更新失败，请刷新后重试', duration: 1800 })
    }
  }

  build() {
    Column() {
      PageHeader({
        title: '员工管理',
        backId: 'admin-employee-back',
        headerBgColor: MODULE_BG.ADMIN,
        actionColor: MODULE_COLOR.ADMIN,
        actionLabel: '新增员工',
        onBack: () => { router.back() },
        onAction: () => { this.openCreate() }
      })

      Row({ space: SPACING.MD }) {
        Text('状态').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        Button('全部').id('admin-employee-status-all').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === -1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === -1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = -1; this.applyFilter() })
        Button('已启用').id('admin-employee-status-enabled').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 1 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 1 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 1; this.applyFilter() })
        Button('已停用').id('admin-employee-status-disabled').fontSize(FONT_SIZE.SM)
          .backgroundColor(this.statusFilter === 0 ? MODULE_COLOR.ADMIN : COLORS.BG_PRIMARY)
          .fontColor(this.statusFilter === 0 ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.statusFilter = 0; this.applyFilter() })
      }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })

      // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在筛选行下方
      List({ space: SPACING.MD }) {
        ListItem() {
          Text('员工账号用于商户端登录；停用后无法继续登录，但不会删除其店铺和订单数据。')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
        }
        if (this.displayEmployees.length === 0) {
          ListItem() {
            Text(this.statusFilter === -1 ? '暂无员工账号' : '当前筛选条件下暂无员工账号')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .width('100%').padding(SPACING.LG)
          }
        }
        ForEach(this.displayEmployees, (employee: AdminEmployee) => {
          ListItem() {
            this.EmployeeRow(employee)
          }
        }, (employee: AdminEmployee) => `${this.renderVersion}-${employee.id}`)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.XXL })

      if (this.showForm) {
        Column() {
          Column({ space: SPACING.SM }) {
            Text(this.editingId === 0 ? '新增员工' : '编辑员工')
              .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
            Text('员工姓名（必填）').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
            TextInput({ placeholder: '请输入员工姓名，如：黄焖鸡老板', text: this.formUsername })
              .width('100%').height(42).onChange((value: string) => { this.formUsername = value })
            Text('手机号（必填）').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
            TextInput({ placeholder: '请输入 11 位手机号，如：13600136000', text: this.formPhone })
              .width('100%').height(42).type(InputType.PhoneNumber)
              .onChange((value: string) => { this.formPhone = value })
            if (this.editingId === 0) {
              Text('初始密码（必填）').fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
              TextInput({ placeholder: '请输入至少 6 位初始密码', text: this.formPassword })
                .width('100%').height(42).type(InputType.Password)
                .onChange((value: string) => { this.formPassword = value })
            }
            Row({ space: SPACING.SM }) {
              Button('取消').layoutWeight(1).height(38)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.closeForm() })
              Button('保存').layoutWeight(1).height(38).fontColor(COLORS.TEXT_WHITE)
                .backgroundColor(MODULE_COLOR.ADMIN)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule).onClick(() => { this.saveEmployee() })
            }.width('100%')
          }
          .width('90%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
        }
        .width('100%').height('100%').backgroundColor(COLORS.OVERLAY)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  EmployeeRow(employee: AdminEmployee) {
    Row({ space: SPACING.MD }) {
      Text(employee.username.substring(0, 1))
        .width(40).height(40).textAlign(TextAlign.Center)
        .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
        .fontColor(accentFg(accentIndexFromText(employee.username)))
        .backgroundColor(accentBg(accentIndexFromText(employee.username)))
        .borderRadius(BORDER_RADIUS.ROUND)
      Column({ space: SPACING.XS }) {
        Text(employee.username).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text(`${employee.phone} · 店铺 ${employee.storeCount} 家`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        StatusBadge({ text: employee.status === 1 ? '启用中' : '已停用', mode: employee.status === 1 ? 'success' : 'gray' })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Row({ space: SPACING.XS }) {
        Button('编辑').height(30).fontSize(FONT_SIZE.XS).onClick(() => { this.openEdit(employee) })
        Button(employee.status === 1 ? '停用' : '启用').height(30).fontSize(FONT_SIZE.XS)
          .fontColor(employee.status === 1 ? COLORS.ERROR : COLORS.SUCCESS)
          .onClick(() => { this.toggleStatus(employee) })
      }
    }
    .width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.MD)
  }
}
