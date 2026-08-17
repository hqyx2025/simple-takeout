/** 管理端-员工账号管理：员工增删改中的新增、资料编辑和启停用。 */
import { AdminEmployee, User, UserRole } from '../model/Models'
import { createAdminEmployeeApi, fetchAdminEmployeesApi, updateAdminEmployeeApi, updateAdminEmployeeStatusApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
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
  @State showForm: boolean = false
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
    this.loading = false
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
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回').fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
          .onClick(() => { router.back() })
        Text('员工管理').fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Button('新增员工').height(32).fontSize(FONT_SIZE.SM)
          .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND).onClick(() => { this.openCreate() })
      }
      .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
      .backgroundColor(COLORS.BG_WHITE)

      Scroll() {
        Column({ space: SPACING.MD }) {
          Text('员工账号用于商户端登录；停用后无法继续登录，但不会删除其店铺和订单数据。')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
          if (this.employees.length === 0) {
            Text('暂无员工账号').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .width('100%').padding(SPACING.LG)
          }
          ForEach(this.employees, (employee: AdminEmployee) => {
            this.EmployeeRow(employee)
          }, (employee: AdminEmployee) => employee.id.toString())
        }
        .width('100%').padding(SPACING.LG)
      }
      .layoutWeight(1).scrollBar(BarState.Off)

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
              Button('取消').layoutWeight(1).height(38).onClick(() => { this.closeForm() })
              Button('保存').layoutWeight(1).height(38).fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY).onClick(() => { this.saveEmployee() })
            }.width('100%')
          }
          .width('90%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
        }
        .width('100%').height('100%').backgroundColor('rgba(0,0,0,0.35)')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  EmployeeRow(employee: AdminEmployee) {
    Row({ space: SPACING.MD }) {
      Column({ space: 4 }) {
        Text(employee.username).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text(`${employee.phone} · 店铺 ${employee.storeCount} 家`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        Text(employee.status === 1 ? '启用中' : '已停用')
          .fontSize(FONT_SIZE.XS).fontColor(employee.status === 1 ? COLORS.SUCCESS : COLORS.ERROR)
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
