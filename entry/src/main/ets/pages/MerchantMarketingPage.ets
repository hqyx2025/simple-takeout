import { AppButtonStyle, AppCardStyle, AppInputStyle } from '../common/theme/AppTheme'
import { AppMotion } from '../common/theme/AppMotion'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG } from '../common/Constants'
import { MarketingActivity, MerchantSeckill, StoreItem } from '../model/Models'
import { fetchMerchantStoresApi, fetchMerchantActivitiesApi, saveMerchantActivityApi, updateMerchantActivityStatusApi, deleteMerchantActivityApi, fetchMerchantSeckillsApi, saveMerchantSeckillApi, updateMerchantSeckillStatusApi, deleteMerchantSeckillApi, MerchantMarketingInput, MerchantSeckillInput } from '../service/ApiService'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { PageHeader } from '../components/PageHeader'

class MarketingSelectOption {
  value: string = ''

  constructor(value: string) {
    this.value = value
  }
}

@Entry
@Component
export struct MerchantMarketingPage {
  @State stores: StoreItem[] = []
  @State selectedStoreId: number = 0
  @State activities: MarketingActivity[] = []
  @State seckills: MerchantSeckill[] = []
  @State title: string = ''
  @State type: string = 'DISCOUNT'
  @State discountRate: string = '0.8'
  @State reduceAmount: string = '3'
  @State threshold: string = '50'
  @State startTime: string = ''
  @State endTime: string = ''
  @State seckillGoodsId: string = ''
  @State seckillPrice: string = ''
  @State seckillQuota: string = '50'
  @State saving: boolean = false
  @State editingActivityId: number = 0

  async aboutToAppear(): Promise<void> {
    this.stores = await fetchMerchantStoresApi()
    if (this.stores.length > 0) {
      this.selectedStoreId = this.stores[0].id
      await this.loadStoreData()
    }
  }

  private async loadStoreData(): Promise<void> {
    if (this.selectedStoreId <= 0) return
    this.activities = await fetchMerchantActivitiesApi(this.selectedStoreId)
    this.seckills = await fetchMerchantSeckillsApi(this.selectedStoreId)
  }

  private async createActivity(): Promise<void> {
    if (this.selectedStoreId <= 0 || this.title.trim() === '' || this.startTime.trim() === '' || this.endTime.trim() === '') {
      promptAction.showToast({ message: '请选择店铺并填写标题、开始和结束时间', duration: 1800 }); return
    }
    this.saving = true
    const input: MerchantMarketingInput = {
      type: this.type, title: this.title.trim(), discountRate: Number(this.discountRate),
      reduceAmount: Number(this.reduceAmount), threshold: Number(this.threshold), giftGoodsId: 0,
      startTime: this.startTime.trim(), endTime: this.endTime.trim(), status: 1
    }
    const result: MarketingActivity | null = await saveMerchantActivityApi(this.selectedStoreId, input, this.editingActivityId)
    this.saving = false
    if (result !== null) {
      this.title = ''; this.editingActivityId = 0; await this.loadStoreData()
      promptAction.showToast({ message: '活动已保存', duration: 1500 })
    }
  }

  private editActivity(item: MarketingActivity): void {
    this.editingActivityId = item.id
    this.title = item.title
    this.type = item.type
    this.discountRate = item.discountRate.toString()
    this.reduceAmount = item.reduceAmount.toString()
    this.startTime = item.startTime
    this.endTime = item.endTime
  }

  private async toggleActivity(item: MarketingActivity): Promise<void> {
    if (await updateMerchantActivityStatusApi(this.selectedStoreId, item.id, item.status === 1 ? 0 : 1)) await this.loadStoreData()
  }

  private async removeActivity(item: MarketingActivity): Promise<void> {
    if (await deleteMerchantActivityApi(this.selectedStoreId, item.id)) await this.loadStoreData()
  }

  private async createSeckill(): Promise<void> {
    if (this.selectedStoreId <= 0 || Number(this.seckillGoodsId) <= 0 || Number(this.seckillPrice) <= 0
      || Number(this.seckillQuota) <= 0 || this.startTime.trim() === '' || this.endTime.trim() === '') {
      promptAction.showToast({ message: '请填写商品 ID、秒杀价、名额和时间', duration: 1800 }); return
    }
    const input: MerchantSeckillInput = {
      goodsId: Number(this.seckillGoodsId), price: Number(this.seckillPrice), quota: Number(this.seckillQuota),
      startTime: this.startTime.trim(), endTime: this.endTime.trim(), status: 1
    }
    const result: MerchantSeckill | null = await saveMerchantSeckillApi(this.selectedStoreId, input)
    if (result !== null) { this.seckillGoodsId = ''; await this.loadStoreData(); promptAction.showToast({ message: '秒杀已创建', duration: 1500 }) }
  }

  private async toggleSeckill(item: MerchantSeckill): Promise<void> {
    if (await updateMerchantSeckillStatusApi(this.selectedStoreId, item.id, item.status === 1 ? 0 : 1)) await this.loadStoreData()
  }

  private async removeSeckill(item: MerchantSeckill): Promise<void> {
    if (item.sold > 0) { promptAction.showToast({ message: '已有销量的秒杀请先下架', duration: 1800 }); return }
    if (await deleteMerchantSeckillApi(this.selectedStoreId, item.id)) await this.loadStoreData()
  }

  build() {
    Column() {
      PageHeader({ title: '营销活动', onBack: () => { router.back() } })
      if (this.stores.length === 0) {
        Text('暂无店铺，请先创建店铺').fontColor(COLORS.TEXT_HINT).padding(SPACING.XL)
      } else {
        Select(this.stores.map((s: StoreItem) => new MarketingSelectOption(s.name)))
          .value(this.stores.find((s: StoreItem) => s.id === this.selectedStoreId)?.name ?? '')
          .onSelect(async (index: number) => { this.selectedStoreId = this.stores[index].id; await this.loadStoreData() })
          .margin({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM })
        Scroll() {
          Column({ space: SPACING.MD }) {
            Column({ space: SPACING.SM }) {
              Text('新建活动').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              TextInput({ placeholder: '活动标题，如：全店 8 折', text: this.title }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.title = v })
              Select([new MarketingSelectOption('DISCOUNT'), new MarketingSelectOption('NEW_USER')]).value(this.type).onSelect((i: number) => { this.type = i === 0 ? 'DISCOUNT' : 'NEW_USER' })
              TextInput({ placeholder: '开始时间 yyyy-MM-dd HH:mm:ss', text: this.startTime }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.startTime = v })
              TextInput({ placeholder: '结束时间 yyyy-MM-dd HH:mm:ss', text: this.endTime }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.endTime = v })
              TextInput({ placeholder: '折扣率（如 0.8）', text: this.discountRate }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.discountRate = v })
              TextInput({ placeholder: '新客立减金额', text: this.reduceAmount }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.reduceAmount = v })
              Button(this.saving ? '保存中…' : (this.editingActivityId > 0 ? '保存活动' : '创建活动')).attributeModifier(new AppButtonStyle()).backgroundColor(MODULE_COLOR.MERCHANT).fontColor(COLORS.ON_PRIMARY).borderRadius(BORDER_RADIUS.ROUND).onClick(() => { this.createActivity() })
            }.attributeModifier(new AppCardStyle()).padding(SPACING.MD).width('100%')
            Text('活动列表').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).width('100%')
            ForEach(this.activities, (item: MarketingActivity) => {
              Row({ space: SPACING.SM }) {
                Column({ space: SPACING.XS }) { Text(item.title).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY); Text(`${item.type} · ${item.startTime} 至 ${item.endTime}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY) }.layoutWeight(1)
                Button('编辑').fontColor(MODULE_COLOR.MERCHANT).onClick(() => { this.editActivity(item) })
                Button(item.status === 1 ? '下架' : '上架').backgroundColor(MODULE_BG.MERCHANT).fontColor(MODULE_COLOR.MERCHANT).onClick(() => { this.toggleActivity(item) })
                Button('删除').fontColor(COLORS.ERROR).onClick(() => { this.removeActivity(item) })
              }.attributeModifier(new AppCardStyle()).padding(SPACING.MD)
            }, (item: MarketingActivity) => `activity-${item.id}`)
            Column({ space: SPACING.SM }) {
              Text('新建秒杀').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              TextInput({ placeholder: '商品 ID（店内无规格商品）', text: this.seckillGoodsId }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.seckillGoodsId = v })
              TextInput({ placeholder: '秒杀价，如 9.9', text: this.seckillPrice }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.seckillPrice = v })
              TextInput({ placeholder: '秒杀名额', text: this.seckillQuota }).attributeModifier(new AppInputStyle()).onChange((v: string) => { this.seckillQuota = v })
              Button('创建秒杀').attributeModifier(new AppButtonStyle()).backgroundColor(MODULE_COLOR.MERCHANT).fontColor(COLORS.ON_PRIMARY).borderRadius(BORDER_RADIUS.ROUND).onClick(() => { this.createSeckill() })
            }.attributeModifier(new AppCardStyle()).padding(SPACING.MD).width('100%')
            Text('秒杀活动').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).width('100%')
            ForEach(this.seckills, (item: MerchantSeckill) => {
              Row({ space: SPACING.SM }) {
                Column({ space: SPACING.XS }) { Text(`商品 #${item.goodsId} · ¥${item.price.toFixed(2)}`).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY); Text(`名额 ${item.sold}/${item.quota} · ${item.startTime} 至 ${item.endTime}`).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY) }.layoutWeight(1)
                Button(item.status === 1 ? '下架' : '上架').backgroundColor(MODULE_BG.MERCHANT).fontColor(MODULE_COLOR.MERCHANT).onClick(() => { this.toggleSeckill(item) })
                Button('删除').fontColor(COLORS.ERROR).onClick(() => { this.removeSeckill(item) })
              }.attributeModifier(new AppCardStyle()).padding(SPACING.MD)
            }, (item: MerchantSeckill) => `seckill-${item.id}`)
          }.width('100%').padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.XL })
        }.layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)
  }
}
