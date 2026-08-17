/**
 * 管理端-分类管理页（大纲 9.4 平台分类管理）
 * 平台分类的增删改：新增、行内编辑（名称）、删除（后端校验有关联店铺时禁止删除）
 */
import { User, UserRole, Category } from '../model/Models'
import { ApiResponse, get, post, put, del } from '../service/HttpClient'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { logInfo } from '../service/AppLogger'

interface AdminCategoryRequest {
  name: string
  icon: string
  color: string
}

@Entry
@Component
export struct AdminCategoryPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State categories: Category[] = []
  @State newCategoryName: string = ''
  @State editingCategoryId: number = 0
  @State editCategoryName: string = ''
  @State deletingCategoryId: number = 0
  @State showDeleteConfirm: boolean = false

  aboutToAppear(): void {
    logInfo('Page', '进入管理端分类管理页 AdminCategoryPage')
    if (!this.loggedIn || this.user.role !== UserRole.ADMIN) {
      promptAction.showToast({ message: '仅管理端账号可以进入平台管理', duration: 1800 })
      router.replaceUrl({ url: 'pages/Index' })
      return
    }
    this.refresh()
  }

  async refresh(): Promise<void> {
    const resp: ApiResponse<Category[]> = await get<Category[]>('/api/admin/categories')
    this.categories = resp.code === 200 && resp.data !== null ? resp.data : []
  }

  async createCategory(): Promise<void> {
    const name: string = this.newCategoryName.trim()
    if (name === '') {
      promptAction.showToast({ message: '请输入分类名称', duration: 1500 })
      return
    }
    const req: AdminCategoryRequest = { name: name, icon: '🍱', color: '#FF6B35' }
    const resp: ApiResponse<Category> = await post<Category>('/api/admin/categories', req)
    if (resp.code === 200) {
      this.newCategoryName = ''
      promptAction.showToast({ message: '分类创建成功', duration: 1500 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: resp.message || '分类创建失败，请稍后重试', duration: 1800 })
    }
  }

  async saveCategory(category: Category): Promise<void> {
    const name: string = this.editCategoryName.trim()
    if (name === '') {
      promptAction.showToast({ message: '分类名称不能为空', duration: 1500 })
      return
    }
    const req: AdminCategoryRequest = { name: name, icon: category.icon, color: category.color }
    const resp: ApiResponse<Category> = await put<Category>(`/api/admin/categories/${category.id}`, req)
    if (resp.code === 200) {
      this.editingCategoryId = 0
      promptAction.showToast({ message: '分类已更新', duration: 1500 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: resp.message || '分类更新失败，请稍后重试', duration: 1800 })
    }
  }

  async deleteCategory(): Promise<void> {
    const resp: ApiResponse<Object> = await del<Object>(`/api/admin/categories/${this.deletingCategoryId}`)
    this.showDeleteConfirm = false
    if (resp.code === 200) {
      this.deletingCategoryId = 0
      promptAction.showToast({ message: '分类已删除', duration: 1500 })
      await this.refresh()
    } else {
      promptAction.showToast({ message: resp.message || '分类删除失败，请稍后重试', duration: 1800 })
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text('‹ 返回')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.PRIMARY)
            .onClick(() => { router.back() })
          Text('分类管理')
            .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
          Button('刷新').height(32).fontSize(FONT_SIZE.SM).onClick(() => { this.refresh() })
        }
        .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG, top: 30 })
        .backgroundColor(COLORS.BG_WHITE)

        Scroll() {
          Column({ space: SPACING.MD }) {
            Text('平台分类用于首页导航与店铺/商品归类，删除前需先解除店铺关联')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')

            // 新增分类
            Row({ space: SPACING.SM }) {
              TextInput({ placeholder: '新增分类名称', text: this.newCategoryName })
                .layoutWeight(1).height(42).onChange((value: string) => { this.newCategoryName = value })
              Button('新增').height(42).fontSize(FONT_SIZE.SM)
                .backgroundColor(COLORS.PRIMARY).onClick(() => { this.createCategory() })
            }.width('100%')

            // 分类列表（含行内编辑与删除）
            if (this.categories.length === 0) {
              Text('暂无分类').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%').padding(SPACING.MD)
            }
            ForEach(this.categories, (category: Category) => {
              Row({ space: SPACING.MD }) {
                Text(category.icon).fontSize(FONT_SIZE.LG)
                if (this.editingCategoryId === category.id) {
                  TextInput({ placeholder: '分类名称', text: this.editCategoryName })
                    .layoutWeight(1).height(36).onChange((value: string) => { this.editCategoryName = value })
                  Button('保存')
                    .height(30).fontSize(FONT_SIZE.XS).fontColor(Color.White).backgroundColor(COLORS.SUCCESS)
                    .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                    .onClick(() => { this.saveCategory(category) })
                  Button('取消')
                    .height(30).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
                    .backgroundColor('#F5F5F5').borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                    .onClick(() => { this.editingCategoryId = 0 })
                } else {
                  Column({ space: 2 }) {
                    Text(category.name).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
                    Text(`#${category.id}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text('编辑')
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
                    .onClick(() => {
                      this.editingCategoryId = category.id
                      this.editCategoryName = category.name
                    })
                  Text('删除')
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR)
                    .onClick(() => {
                      this.deletingCategoryId = category.id
                      this.showDeleteConfirm = true
                    })
                }
              }
              .width('100%').padding(SPACING.MD)
              .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.MD)
            }, (category: Category) => category.id.toString())
          }
          .width('100%').padding(SPACING.LG)
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

      // 删除确认弹窗
      if (this.showDeleteConfirm) {
        ConfirmDialog({
          title: '删除分类',
          content: '确定删除该分类吗？分类下仍有关联店铺时将无法删除。',
          confirmText: '确定删除',
          cancelText: '取消',
          onConfirm: () => { this.deleteCategory() },
          onCancel: () => { this.showDeleteConfirm = false }
        })
      }
    }
    .width('100%').height('100%')
  }
}
