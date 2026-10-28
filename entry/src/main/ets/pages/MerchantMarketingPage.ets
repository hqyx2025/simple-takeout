import { AppButtonStyle, AppCardStyle, AppTheme } from '../common/theme/AppTheme'
import { SPACING, getMarketingTypeText } from '../common/Constants'
import { MarketingActivity, MerchantSeckill, StoreItem, GoodsItem, User, UserRole, createEmptyUser } from '../model/Models'
import { fetchMerchantStoresApi, fetchMerchantGoodsApi, fetchMerchantActivitiesApi, saveMerchantActivityApi,
  updateMerchantActivityStatusApi, deleteMerchantActivityApi, fetchMerchantSeckillsApi, saveMerchantSeckillApi,
  updateMerchantSeckillStatusApi, deleteMerchantSeckillApi, MerchantMarketingInput, MerchantSeckillInput } from '../service/ApiService'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { PageHeader } from '../components/PageHeader'
import { FormInput } from '../components/FormInput'
import { DateTimeField } from '../components/DateTimeField'
import { EmptyState } from '../components/EmptyState'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { getAuthSessionEpoch } from '../service/HttpClient'

class MarketingSelectOption {
  value: string
  constructor(value: string) { this.value = value }
}

@Entry
@Component
export struct MerchantMarketingPage {
  @State stores: StoreItem[] = []
  @State selectedStoreId: number = 0
  @State activities: MarketingActivity[] = []
  @State seckills: MerchantSeckill[] = []
  @State goods: GoodsItem[] = []
  @State goodsOptions: MarketingSelectOption[] = []
  @State section: string = 'activities'
  @State form: string = ''
  @State title: string = ''
  @State type: string = 'DISCOUNT'
  @State discountRate: string = '0.8'
  @State reduceAmount: string = '3'
  @State threshold: string = ''
  @State giftGoodsId: number = 0
  @State startTime: string = ''
  @State endTime: string = ''
  @State activityStatus: number = 1
  @State seckillGoodsId: number = 0
  @State seckillPrice: string = ''
  @State seckillQuota: string = '50'
  @State saving: boolean = false
  @State loading: boolean = false
  @State errorText: string = ''
  @State editingActivityId: number = 0
  @State pendingActivity: MarketingActivity | null = null
  @State pendingSeckill: MerchantSeckill | null = null
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = createEmptyUser()
  private active: boolean = true
  private version: number = 0

  async aboutToAppear(): Promise<void> {
    if (!this.loggedIn || this.user.role !== UserRole.MERCHANT) { router.back(); return }
    this.loading = true
    this.stores = await fetchMerchantStoresApi()
    if (!this.active) { return }
    if (this.stores.length > 0) { this.selectedStoreId = this.stores[0].id; await this.loadStoreData() }
    else { this.loading = false }
  }

  aboutToDisappear(): void { this.active = false; this.version += 1 }

  private async loadStoreData(): Promise<void> {
    if (this.selectedStoreId <= 0) { return }
    const version: number = ++this.version
    const storeId: number = this.selectedStoreId
    const epoch: number = getAuthSessionEpoch()
    this.loading = true
    const activities: MarketingActivity[] = await fetchMerchantActivitiesApi(storeId)
    const seckills: MerchantSeckill[] = await fetchMerchantSeckillsApi(storeId)
    const goods: GoodsItem[] = await fetchMerchantGoodsApi(storeId)
    if (!this.active || version !== this.version || storeId !== this.selectedStoreId || epoch !== getAuthSessionEpoch()) { return }
    this.activities = activities; this.seckills = seckills
    this.goods = goods.filter((item: GoodsItem): boolean => (item.specs?.length ?? 0) === 0)
    this.goodsOptions = this.goods.map((item: GoodsItem): MarketingSelectOption => new MarketingSelectOption(item.name))
    this.loading = false
  }

  private typeLabel(type: string): string {
    return getMarketingTypeText(type)
  }

  private goodsName(id: number): string {
    return this.goods.find((item: GoodsItem): boolean => item.id === id)?.name ?? '商品已下架或不可用'
  }

  private openForm(form: string): void {
    this.editingActivityId = 0; this.title = ''; this.type = 'DISCOUNT'; this.discountRate = '0.8'
    this.reduceAmount = '3'; this.threshold = ''; this.giftGoodsId = 0; this.activityStatus = 1
    this.seckillGoodsId = 0; this.seckillPrice = ''; this.seckillQuota = '50'
    this.startTime = ''; this.endTime = ''; this.errorText = ''; this.form = form
  }

  private editActivity(item: MarketingActivity): void {
    this.editingActivityId = item.id; this.title = item.title; this.type = item.type
    this.discountRate = item.discountRate.toString(); this.reduceAmount = item.reduceAmount.toString()
    this.threshold = item.threshold.toString(); this.giftGoodsId = item.giftGoodsId
    this.activityStatus = item.status; this.startTime = item.startTime; this.endTime = item.endTime
    this.errorText = ''; this.form = 'activity'
  }

  private async saveForm(): Promise<void> {
    if (this.saving || this.loading || !this.loggedIn) { return }
    this.errorText = ''
    if (this.startTime === '' || this.endTime === '') { this.errorText = '请选择开始和结束时间'; return }
    if (this.endTime <= this.startTime) { this.errorText = '结束时间须晚于开始时间'; return }
    const discount: number = Number(this.discountRate)
    const reduction: number = Number(this.reduceAmount)
    const threshold: number = Number(this.threshold)
    const price: number = Number(this.seckillPrice)
    const quota: number = Number(this.seckillQuota)
    if (this.form === 'activity') {
      if (this.title.trim() === '') { this.errorText = '请填写活动名称'; return }
      if (this.type === 'DISCOUNT' && (!Number.isFinite(discount) || discount <= 0 || discount >= 1)) { this.errorText = '折扣率须大于 0、小于 1'; return }
      if (this.type === 'NEW_USER' && (!Number.isFinite(reduction) || reduction <= 0)) { this.errorText = '立减金额须大于 0'; return }
      if (this.type === 'GIFT' && (!Number.isFinite(threshold) || threshold <= 0 || this.giftGoodsId <= 0)) { this.errorText = '请填写满赠门槛并选择赠品'; return }
    } else {
      if (this.seckillGoodsId <= 0) { this.errorText = '请选择秒杀商品'; return }
      if (!Number.isFinite(price) || price <= 0) { this.errorText = '秒杀价须大于 0'; return }
      if (!Number.isSafeInteger(quota) || quota <= 0) { this.errorText = '秒杀名额须为正整数'; return }
    }
    this.saving = true
    try {
      let saved: boolean = false
      if (this.form === 'activity') {
        const input: MerchantMarketingInput = { type: this.type, title: this.title.trim(),
          discountRate: this.type === 'DISCOUNT' ? discount : 1, reduceAmount: this.type === 'NEW_USER' ? reduction : 0,
          threshold: this.type === 'GIFT' ? threshold : 0, giftGoodsId: this.type === 'GIFT' ? this.giftGoodsId : 0,
          startTime: this.startTime, endTime: this.endTime, status: this.activityStatus }
        saved = await saveMerchantActivityApi(this.selectedStoreId, input, this.editingActivityId) !== null
      } else {
        const input: MerchantSeckillInput = { goodsId: this.seckillGoodsId, price: price, quota: quota,
          startTime: this.startTime, endTime: this.endTime, status: 1 }
        saved = await saveMerchantSeckillApi(this.selectedStoreId, input) !== null
      }
      if (this.active && saved) { this.form = ''; await this.loadStoreData(); promptAction.showToast({ message: '已保存', duration: 1500 }) }
    } finally { this.saving = false }
  }

  private async toggleActivity(item: MarketingActivity): Promise<void> {
    if (this.saving) { return }
    this.saving = true
    try { if (await updateMerchantActivityStatusApi(this.selectedStoreId, item.id, item.status === 1 ? 0 : 1)) { await this.loadStoreData() } }
    finally { this.saving = false }
  }

  private async toggleSeckill(item: MerchantSeckill): Promise<void> {
    if (this.saving) { return }
    this.saving = true
    try { if (await updateMerchantSeckillStatusApi(this.selectedStoreId, item.id, item.status === 1 ? 0 : 1)) { await this.loadStoreData() } }
    finally { this.saving = false }
  }

  private async removePending(): Promise<void> {
    if (this.saving) { return }
    this.saving = true
    const activity: MarketingActivity | null = this.pendingActivity
    const seckill: MerchantSeckill | null = this.pendingSeckill
    this.pendingActivity = null; this.pendingSeckill = null
    try {
      if (activity !== null && await deleteMerchantActivityApi(this.selectedStoreId, activity.id)) { await this.loadStoreData() }
      if (seckill !== null && await deleteMerchantSeckillApi(this.selectedStoreId, seckill.id)) { await this.loadStoreData() }
    } finally { this.saving = false }
  }

  @Builder
  GoodsChoice(label: string, id: string, selectedId: number, gift: boolean) {
    Column({ space: SPACING.SM }) {
      Text(label).fontSize(14).fontColor(AppTheme.TEXT).width('100%')
      if (this.goodsOptions.length === 0) { Text('暂无可选的无规格商品').fontSize(14).fontColor(AppTheme.MUTED) }
      else {
        Select(this.goodsOptions).value(selectedId > 0 ? this.goodsName(selectedId) : '请选择商品')
          .selected(this.goods.findIndex((item: GoodsItem): boolean => item.id === selectedId))
          .width('100%').id(id).enabled(!this.saving).accessibilityText(label)
          .onSelect((index: number) => { if (gift) { this.giftGoodsId = this.goods[index].id } else { this.seckillGoodsId = this.goods[index].id } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  FormContent() {
    Column({ space: SPACING.MD }) {
      if (this.form === 'activity') {
        FormInput({ label: '活动名称', value: this.title, placeholder: '例如：全店八折', fieldId: 'marketing-title', isEnabled: !this.saving,
          onChange: (value: string) => { this.title = value } })
        Text('活动类型').fontSize(14).fontColor(AppTheme.TEXT)
        Select([new MarketingSelectOption('折扣'), new MarketingSelectOption('新客立减'), new MarketingSelectOption('满赠')])
          .value(this.typeLabel(this.type)).selected(this.type === 'DISCOUNT' ? 0 : this.type === 'NEW_USER' ? 1 : 2)
          .width('100%').id('marketing-type').enabled(!this.saving)
          .onSelect((index: number) => { this.type = index === 0 ? 'DISCOUNT' : index === 1 ? 'NEW_USER' : 'GIFT' })
        if (this.type === 'DISCOUNT') {
          FormInput({ label: '折扣率', value: this.discountRate, placeholder: '例如：0.8 表示八折', fieldId: 'marketing-discount',
            inputType: InputType.NUMBER_DECIMAL, isEnabled: !this.saving, onChange: (value: string) => { this.discountRate = value } })
        } else if (this.type === 'NEW_USER') {
          FormInput({ label: '立减金额（元）', value: this.reduceAmount, placeholder: '例如：3', fieldId: 'marketing-reduction',
            inputType: InputType.NUMBER_DECIMAL, isEnabled: !this.saving, onChange: (value: string) => { this.reduceAmount = value } })
        } else {
          FormInput({ label: '满赠门槛（元）', value: this.threshold, placeholder: '例如：50', fieldId: 'marketing-threshold',
            inputType: InputType.NUMBER_DECIMAL, isEnabled: !this.saving, onChange: (value: string) => { this.threshold = value } })
          this.GoodsChoice('赠品', 'marketing-gift-goods', this.giftGoodsId, true)
        }
      } else {
        this.GoodsChoice('秒杀商品', 'seckill-goods', this.seckillGoodsId, false)
        FormInput({ label: '秒杀价（元）', value: this.seckillPrice, placeholder: '例如：9.9', fieldId: 'seckill-price',
          inputType: InputType.NUMBER_DECIMAL, isEnabled: !this.saving, onChange: (value: string) => { this.seckillPrice = value } })
        FormInput({ label: '秒杀名额', value: this.seckillQuota, placeholder: '例如：50', fieldId: 'seckill-quota',
          inputType: InputType.Number, isEnabled: !this.saving, onChange: (value: string) => { this.seckillQuota = value } })
      }
      DateTimeField({ label: '开始时间', value: this.startTime, fieldId: 'marketing-start', isEnabled: !this.saving,
        onChange: (value: string) => { this.startTime = value } })
      DateTimeField({ label: '结束时间', value: this.endTime, fieldId: 'marketing-end', isEnabled: !this.saving,
        onChange: (value: string) => { this.endTime = value } })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  ActivityCard(item: MarketingActivity) {
    Column({ space: SPACING.SM }) {
      Text(item.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT)
      Text(this.typeLabel(item.type) + ' · ' + (item.status === 1 ? '已上架' : '已下架')).fontSize(14).fontColor(AppTheme.MUTED)
      Text(item.startTime + ' 至 ' + item.endTime).fontSize(12).fontColor(AppTheme.MUTED)
      Row({ space: SPACING.SM }) {
        Button('编辑').attributeModifier(new AppButtonStyle()).layoutWeight(1).id(`marketing-edit-${item.id}`).onClick(() => { this.editActivity(item) })
        Button(item.status === 1 ? '下架' : '上架').attributeModifier(new AppButtonStyle()).layoutWeight(1).fontColor(AppTheme.TEXT).backgroundColor(AppTheme.INPUT).id(`marketing-toggle-${item.id}`).onClick(() => { this.toggleActivity(item) })
        Button('删除').attributeModifier(new AppButtonStyle()).layoutWeight(1).fontColor(AppTheme.ERROR).backgroundColor(AppTheme.ERROR_BG).id(`marketing-delete-${item.id}`).onClick(() => { this.pendingActivity = item })
      }.width('100%').enabled(!this.saving)
    }.attributeModifier(new AppCardStyle()).padding(SPACING.MD).width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  SeckillCard(item: MerchantSeckill) {
    Column({ space: SPACING.SM }) {
      Text(this.goodsName(item.goodsId)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT)
      Text(`¥${item.price.toFixed(2)} · 已售 ${item.sold}/${item.quota}`).fontSize(14).fontColor(AppTheme.MUTED)
      Text(item.startTime + ' 至 ' + item.endTime).fontSize(12).fontColor(AppTheme.MUTED)
      Row({ space: SPACING.SM }) {
        Button(item.status === 1 ? '下架' : '上架').attributeModifier(new AppButtonStyle()).layoutWeight(1).fontColor(AppTheme.TEXT).backgroundColor(AppTheme.INPUT).id(`seckill-toggle-${item.id}`).onClick(() => { this.toggleSeckill(item) })
        Button('删除').attributeModifier(new AppButtonStyle()).layoutWeight(1).fontColor(AppTheme.ERROR).backgroundColor(AppTheme.ERROR_BG).id(`seckill-delete-${item.id}`).enabled(item.sold === 0).onClick(() => { this.pendingSeckill = item })
      }.width('100%').enabled(!this.saving)
    }.attributeModifier(new AppCardStyle()).padding(SPACING.MD).width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      Column() {
        PageHeader({ title: this.form === 'activity' ? (this.editingActivityId > 0 ? '编辑活动' : '新建活动') : this.form === 'seckill' ? '新建秒杀' : '营销活动',
          backId: 'marketing-back', onBack: () => { if (!this.saving) { if (this.form !== '') { this.form = '' } else { router.back() } } },
          actionLabel: this.form !== '' || this.stores.length === 0 ? '' : (this.section === 'activities' ? '新增活动' : '新增秒杀'),
          actionEnabled: !this.saving && !this.loading,
          onAction: () => { if (!this.saving && !this.loading) { this.openForm(this.section === 'activities' ? 'activity' : 'seckill') } } })
        if (this.stores.length > 0 && this.form === '') {
          Select(this.stores.map((store: StoreItem): MarketingSelectOption => new MarketingSelectOption(store.name)))
            .value(this.stores.find((store: StoreItem): boolean => store.id === this.selectedStoreId)?.name ?? '')
            .id('marketing-store').enabled(!this.saving && !this.loading)
            .onSelect((index: number) => { this.selectedStoreId = this.stores[index].id; this.loadStoreData() })
          Row({ space: SPACING.SM }) {
            Button('活动').attributeModifier(new AppButtonStyle()).layoutWeight(1).id('marketing-tab-activities')
              .backgroundColor(this.section === 'activities' ? AppTheme.PRIMARY : AppTheme.INPUT).fontColor(this.section === 'activities' ? AppTheme.PRIMARY_TEXT : AppTheme.TEXT).onClick(() => { this.section = 'activities' })
            Button('秒杀').attributeModifier(new AppButtonStyle()).layoutWeight(1).id('marketing-tab-seckills')
              .backgroundColor(this.section === 'seckills' ? AppTheme.PRIMARY : AppTheme.INPUT).fontColor(this.section === 'seckills' ? AppTheme.PRIMARY_TEXT : AppTheme.TEXT).onClick(() => { this.section = 'seckills' })
          }.width('100%').padding(SPACING.MD)
        }
        if (this.loading) { Text('正在加载…').fontColor(AppTheme.MUTED).layoutWeight(1) }
        else if (this.stores.length === 0) { EmptyState({ title: '暂无店铺', actionLabel: '去管理店铺', actionUrl: 'pages/MerchantCenterPage' }) }
        else {
          Scroll() {
            Column({ space: SPACING.MD }) {
              if (this.form !== '') { this.FormContent() }
              else if (this.section === 'activities') {
                if (this.activities.length === 0) { EmptyState({ title: '暂无活动', actionLabel: '新建活动', onAction: () => { this.openForm('activity') } }) }
                ForEach(this.activities, (item: MarketingActivity) => { this.ActivityCard(item) }, (item: MarketingActivity) => `${item.id}-${item.status}-${item.title}`)
              } else {
                if (this.seckills.length === 0) { EmptyState({ title: '暂无秒杀', actionLabel: '新建秒杀', onAction: () => { this.openForm('seckill') } }) }
                ForEach(this.seckills, (item: MerchantSeckill) => { this.SeckillCard(item) }, (item: MerchantSeckill) => `${item.id}-${item.status}`)
              }
            }.width('100%').padding(SPACING.LG).constraintSize({ maxWidth: 680 }).alignItems(HorizontalAlign.Start)
          }.width('100%').layoutWeight(1).align(Alignment.Top)
        }
        if (this.form !== '') {
          if (this.errorText !== '') { Text(this.errorText).fontColor(AppTheme.ERROR).id('marketing-error').width('90%') }
          Row({ space: SPACING.MD }) {
            Button('取消').attributeModifier(new AppButtonStyle()).layoutWeight(1).id('marketing-cancel').fontColor(AppTheme.TEXT).backgroundColor(AppTheme.INPUT)
              .enabled(!this.saving).onClick(() => { this.form = ''; this.errorText = '' })
            Button(this.saving ? '保存中…' : '保存').attributeModifier(new AppButtonStyle()).layoutWeight(1).id('marketing-submit').enabled(!this.saving && !this.loading).onClick(() => { this.saveForm() })
          }.width('100%').padding(SPACING.LG)
        } else if (this.stores.length > 0) {
          Button('刷新列表').attributeModifier(new AppButtonStyle()).width('90%').fontColor(AppTheme.TEXT).backgroundColor(AppTheme.INPUT).id('marketing-reload').enabled(!this.saving && !this.loading).onClick(() => { this.loadStoreData() })
        }
      }.width('100%').height('100%').backgroundColor(AppTheme.PAGE)
      if (this.pendingActivity !== null || this.pendingSeckill !== null) {
        ConfirmDialog({ title: '删除活动', content: '删除后无法恢复。已有销量的秒杀只能下架。', confirmText: '删除', cancelText: '取消',
          onConfirm: () => { this.removePending() }, onCancel: () => { this.pendingActivity = null; this.pendingSeckill = null } })
      }
    }.width('100%').height('100%')
  }
}
