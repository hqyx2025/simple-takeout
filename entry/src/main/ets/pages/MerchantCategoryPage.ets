import { User, createEmptyUser } from '../model/Models'
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'
import { AppButtonStyle, AppCardStyle } from '../common/theme/AppTheme'
import { PageHeader } from '../components/PageHeader'
import { FormInput } from '../components/FormInput'
import { RemoteState } from '../components/RemoteState'
import { routerCompat as router, promptCompat as promptAction } from '../common/UiNavigation'
import { Category, StoreItem, UserRole } from '../model/Models'
import { PageSession } from '../service/PageSession'
import { FormDraftStore, StoredFormDraft, askToRestoreDraft, discardUnreadableDraft } from '../service/FormDraftStore'
import { fetchMerchantCategoriesResultApi, fetchMerchantStoresResultApi, createMerchantCategoryApi, updateMerchantCategoryApi, deleteMerchantCategoryApi } from '../service/api/MerchantApi'

@Entry
@Component
struct MerchantCategoryPage {
  private session: PageSession = new PageSession()
  @StorageLink('user') @Watch('onSessionIdentityChange') currentUser: User = createEmptyUser()
  @StorageLink('isLoggedIn') @Watch('onSessionIdentityChange') authenticated: boolean = false

  @State categories: Category[] = []
  @State storeName: string = ''
  @State name: string = ''
  @State editingId: number = 0
  @State loading: boolean = true
  @State failed: boolean = false
  @State busy: boolean = false
  @State draftError: string = ''
  private draft: FormDraftStore = new FormDraftStore()
  private storeId: number = 0

  onSessionIdentityChange(): void {
    if (this.session.matchesIdentity()) { return }
    this.session.pause()
    this.categories = []; this.name = ''
    router.replaceUrl({ url: 'pages/Index' })
  }

  aboutToAppear(): void {
    this.storeId = router.getParams()?.storeId ?? 0
    if (!this.session.start(UserRole.MERCHANT)) { router.back(); return }
    this.load(true)
  }
  onPageShow(): void { if (this.session.matchesIdentity()) { this.busy = false } }
  onPageHide(): void { this.saveDraft(); this.session.pause() }
  aboutToDisappear(): void { this.onPageHide() }
  private async load(restore: boolean = false): Promise<void> {
    const version: number = this.session.request()
    this.loading = true
    this.failed = false
    const stores: StoreItem[] | null = await fetchMerchantStoresResultApi()
    if (!this.session.current(version)) { return }
    if (stores === null || (this.storeId > 0 && !stores.some((store: StoreItem) => store.id === this.storeId))) {
      this.loading = false; this.failed = true; return
    }
    this.storeName = stores.find((store: StoreItem) => store.id === this.storeId)?.name ?? ''
    const categories: Category[] | null = await fetchMerchantCategoriesResultApi()
    if (!this.session.current(version)) { return }
    this.loading = false
    if (categories === null) { this.failed = true; return }
    this.categories = categories
    if (!restore) { return }
    try {
      const saved: StoredFormDraft | null = await this.draft.open(`categories:${this.storeId}`, this.draftFields())
      if (!this.session.current(version)) { return }
      if (saved !== null) {
        const id: number = Number(saved.fields['categoryId'] ?? '0')
        if (id > 0 && !categories.some((item: Category) => item.id === id)) {
          this.draftError = '草稿对应的分类已删除'; await this.draft.clear()
        } else {
          const restoreDraft: boolean = await askToRestoreDraft(this.getUIContext(), saved)
          if (!this.session.current(version)) { return }
          if (restoreDraft) { this.editingId = id; this.name = saved.fields['name'] ?? '' }
          else if (!(await this.draft.clear())) { this.draftError = '草稿清理失败' }
        }
      }
      this.draft.resume(this.draftFields())
    } catch (_) {
      if (!this.session.current(version)) { return }
      const discarded: boolean = await discardUnreadableDraft(this.getUIContext(), this.draft)
      if (!this.session.current(version)) { return }
      if (!discarded) { router.back(); return }
      this.draft.resume(this.draftFields())

    }
  }
  private draftFields(): Record<string, string> {
    const fields: Record<string, string> = {}
    fields['name'] = this.name
    fields['categoryId'] = this.editingId.toString()
    return fields
  }
  private async saveDraft(): Promise<void> {
    if (!(await this.draft.save(this.draftFields()))) { this.draftError = '草稿保存失败，请勿关闭页面' }
  }
  private async save(): Promise<void> {
    if (this.busy || this.loading || this.failed || this.name.trim() === '') { return }
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    this.busy = true
    const category: Category | undefined = this.categories.find((item: Category) => item.id === this.editingId)
    const result: Category | null = this.editingId > 0
      ? await updateMerchantCategoryApi(this.editingId, this.name.trim(), category?.sort ?? 0)
      : await createMerchantCategoryApi(this.name.trim(), this.categories.length + 1)
    if (!this.session.current(version)) { return }
    this.busy = false
    if (result === null) { return }
    if (!(await this.draft.clear())) { this.draftError = '已保存，旧草稿清理失败' }
    this.name = ''; this.editingId = 0
    this.draft.resume(this.draftFields())
    promptAction.showToast({ message: '分类已保存' })
    this.load()
  }
  private async remove(category: Category): Promise<void> {
    if (this.busy) { return }
    const version: number = this.session.request()
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '删除共享分类',
        message: `「${category.name}」由本账号的门店共用，确认删除？`,
        buttons: [{ text: '取消', color: COLORS.TEXT_SECONDARY }, { text: '删除', color: COLORS.ERROR }] })
      if (choice.index !== 1 || !this.session.current(version)) { return }
      this.busy = true
      const deleted: boolean = await deleteMerchantCategoryApi(category.id)
      if (!this.session.current(version)) { return }
      this.busy = false
      if (deleted) {
        if (this.editingId === category.id) { this.editingId = 0; this.name = ''; await this.draft.clear(); this.draft.resume(this.draftFields()) }
        promptAction.showToast({ message: '分类已删除' }); this.load()
      }
    } catch (_) { if (this.session.current(version)) { this.busy = false } }
  }
  @Builder
  CategoryRow(category: Category) {
    Row({ space: SPACING.SM }) {
      Text(category.name).fontColor(COLORS.TEXT_PRIMARY).fontSize(FONT_SIZE.MD).layoutWeight(1)
      Button('改名').attributeModifier(new AppButtonStyle()).height(44).enabled(!this.busy)
        .onClick(() => { this.editingId = category.id; this.name = category.name; this.saveDraft() })
      Button('删除').attributeModifier(new AppButtonStyle()).height(44).fontColor(COLORS.ERROR).enabled(!this.busy)
        .onClick(() => { this.remove(category) })
    }.attributeModifier(new AppCardStyle()).width('100%').padding(SPACING.MD)
  }
  build() {
    Column() {
      PageHeader({ title: this.storeName === '' ? '分类管理' : this.storeName + ' · 分类管理', onBack: () => { router.back() } })
      Scroll() {
        Column({ space: SPACING.MD }) {
          Text('商户共享分类，修改会影响本账号的所有门店').fontColor(COLORS.TEXT_SECONDARY).fontSize(FONT_SIZE.SM)
          if (this.draftError !== '') { Text(this.draftError).fontColor(COLORS.ERROR).fontSize(FONT_SIZE.SM) }
          FormInput({ label: this.editingId > 0 ? '分类名称' : '新增分类名称', value: this.name,
            placeholder: '如：招牌热菜', required: true, isEnabled: !this.busy && !this.loading && !this.failed,
            fieldId: this.editingId > 0 ? 'MerchantCenterPage-editCategoryName' : 'MerchantCenterPage-newCategoryName',
            onChange: (value: string) => { this.name = value; this.saveDraft() } })
          if (this.editingId > 0) {
            Button('取消改名').attributeModifier(new AppButtonStyle()).height(44).enabled(!this.busy)
              .onClick(() => { this.editingId = 0; this.name = ''; this.saveDraft() })
          }
          RemoteState({ loading: this.loading, failed: this.failed, hasData: this.categories.length > 0,
            emptyTitle: '暂无分类，请先新增', onRetry: () => { this.load(true) } })
          ForEach(this.categories, (category: Category) => { this.CategoryRow(category) }, (category: Category) => `${category.id}:${category.name}`)
        }.width('100%').padding(SPACING.LG)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
      Button(this.busy ? '保存中…' : this.editingId > 0 ? '保存分类' : '新增分类').attributeModifier(new AppButtonStyle())
        .width('90%').height(48).margin(SPACING.MD).enabled(!this.busy && !this.loading && !this.failed && this.name.trim() !== '')
        .onClick(() => { this.save() })
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
