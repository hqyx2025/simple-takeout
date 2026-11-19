import { FormSelect } from '../components/FormSelect'
import { ImageUpload } from '../components/ImageUpload'
import { FormInput } from '../components/FormInput'
import { AppButtonStyle } from '../common/theme/AppTheme'
/**
 * 商户中心页面
 * 商户可查看自己的店铺列表、管理店铺、上架食物
 */
import { AppMotion } from '../common/theme/AppMotion'
import { StoreItem, UserRole, User, Address } from '../model/Models'
import { createMerchantStoreApi, updateMerchantStoreApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, DELIVERY_RANGE } from '../common/Constants'
import { promptCompat as promptAction } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'
import { routerCompat as router } from '../common/UiNavigation'
import { AddressSearchResult, searchAddress, joinAddressParts } from '../service/LocationService'
import { syncAddressesRemote } from '../service/AppStorageManager'
import { PageHeader } from '../components/PageHeader'

import { PageSession } from '../service/PageSession'
import { fetchMerchantStoresResultApi } from '../service/api/MerchantApi'
import { FormDraftStore, StoredFormDraft, askToRestoreDraft, discardUnreadableDraft } from '../service/FormDraftStore'
import { RemoteState } from '../components/RemoteState'
const MERCHANT_RADIUS_DEFAULT_KM: number = DELIVERY_RANGE.STORE_DEFAULT_KM
const MERCHANT_RADIUS_LABEL: string = `配送半径 ${DELIVERY_RANGE.STORE_MIN_KM}–${DELIVERY_RANGE.STORE_MAX_KM} 公里`

class MerchantAddressOption {
  id: number = 0
  value: string = ''

  static create(id: number, value: string): MerchantAddressOption {
    const option: MerchantAddressOption = new MerchantAddressOption()
    option.id = id
    option.value = value
    return option
  }
}

@Entry
@Component
export struct MerchantStoreEditPage {
  private session: PageSession = new PageSession()

  @StorageLink('isLoggedIn') @Watch('onSessionIdentityChange') loggedIn: boolean = false
  @StorageLink('user') @Watch('onSessionIdentityChange') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State myStores: StoreItem[] = []
  @StorageLink('addressList') merchantAddresses: Address[] = []
  @State storeAddressOptions: MerchantAddressOption[] = []
  @State editStoreAddressOptions: MerchantAddressOption[] = []
  @State newStoreAddressId: number = 0
  @State editStoreAddressId: number = 0
  @State newStoreAddressIndex: number = -1
  @State editStoreAddressIndex: number = -1
  @State editStoreAddressFallbackText: string = ''
  @State editStoreAddressFallbackLatitude: number = 0
  @State editStoreAddressFallbackLongitude: number = 0

  // 新增店铺表单
  @State @Watch('onDraftChange') newStoreName: string = ''
  @State @Watch('onDraftChange') newStoreNotice: string = ''
  @State @Watch('onDraftChange') newStoreDeliveryFee: string = '3'
  @State @Watch('onDraftChange') newStoreMinOrder: string = '20'
  // 店铺照片（上传接口返回的相对地址；空串表示未上传）
  @State imageUploading: boolean = false
  @State @Watch('onDraftChange') newStoreImages: string[] = []
  // 表单用公里，接口用米。
  @State @Watch('onDraftChange') newStoreRadius: string = `${MERCHANT_RADIUS_DEFAULT_KM}`
  // 「定位选择店铺位置」的结果：非空时优先于已保存地址
  @State newStorePickedAddress: string = ''
  @State newStorePickedLatitude: number = 0
  @State newStorePickedLongitude: number = 0

  // 商户分类管理（演进项，见大纲 8.3）

  // 编辑店铺表单
  @State @Watch('onDraftChange') editStoreName: string = ''
  @State @Watch('onDraftChange') editStoreNotice: string = ''
  @State @Watch('onDraftChange') editStoreDeliveryFee: string = ''
  @State @Watch('onDraftChange') editStoreMinOrder: string = ''
  @State @Watch('onDraftChange') editStoreImages: string[] = []
  @State @Watch('onDraftChange') editStoreRadius: string = `${MERCHANT_RADIUS_DEFAULT_KM}`
  @State editingStoreId: number = 0
  @State savingStore: boolean = false
  @State creatingStore: boolean = false
  // 半径过小/过大的确认弹窗（确认后带着 confirmed 标记重入提交）

  @State loading: boolean = true
  @State loadFailed: boolean = false
  @State draftError: string = ''
  private draft: FormDraftStore = new FormDraftStore()
  private initialized: boolean = false
  private draftTimer: number = -1

  onSessionIdentityChange(): void {
    if (this.session.matchesIdentity()) { return }
    this.session.pause()
    this.newStoreName = ''; this.editStoreName = ''; this.newStoreImages = []; this.editStoreImages = []
    router.replaceUrl({ url: 'pages/Index' })
  }

  aboutToAppear(): void {
    if (!this.session.start(UserRole.MERCHANT)) { router.replaceUrl({ url: 'pages/Index' }); return }
    this.editingStoreId = router.getParams()?.storeId ?? 0
    this.initialize()
  }

  private async initialize(): Promise<void> {
    const version: number = this.session.request()
    this.loading = true
    this.loadFailed = false
    const stores: StoreItem[] | null = await fetchMerchantStoresResultApi()
    if (!this.session.current(version)) { return }
    if (stores === null) { this.loading = false; this.loadFailed = true; return }
    this.myStores = stores
    await this.refreshMerchantAddresses()
    if (!this.session.current(version)) { return }
    if (this.editingStoreId > 0) {
      const store: StoreItem | undefined = stores.find((item: StoreItem) => item.id === this.editingStoreId)
      if (store === undefined) { this.loading = false; this.loadFailed = true; this.draftError = '门店不存在或无权管理'; return }
      this.startEditStore(store)
    } else { await this.openAddStoreForm() }
    if (!this.session.current(version)) { return }
    this.loading = false
    this.initialized = true
    try {
      const saved: StoredFormDraft | null = await this.draft.open(`store:${this.editingStoreId}:edit`, this.draftFields())
      if (!this.session.current(version)) { return }
      if (saved !== null) {
        const restore: boolean = await askToRestoreDraft(this.getUIContext(), saved)
        if (!this.session.current(version)) { return }
        if (restore) { this.applyDraft(saved.fields) }
        else if (!(await this.draft.clear())) { this.draftError = '草稿未能删除，请重试'; return }
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

  onPageHide(): void { clearTimeout(this.draftTimer); this.saveDraft(); this.session.pause() }
  aboutToDisappear(): void { this.onPageHide() }
  async onPageShow(): Promise<void> {
    if (!this.initialized) { return }
    const version: number = this.session.request()
    if (!this.session.current(version)) { router.replaceUrl({ url: 'pages/Index' }); return }
    await this.refreshMerchantAddresses()
    if (this.session.current(version)) { this.applyPickedStoreLocation() }
  }

  private draftFields(): Record<string, string> {
    const editing: boolean = this.editingStoreId > 0
    const fields: Record<string, string> = {}
    fields['name'] = editing ? this.editStoreName : this.newStoreName
    fields['notice'] = editing ? this.editStoreNotice : this.newStoreNotice
    fields['fee'] = editing ? this.editStoreDeliveryFee : this.newStoreDeliveryFee
    fields['minimum'] = editing ? this.editStoreMinOrder : this.newStoreMinOrder
    fields['radius'] = editing ? this.editStoreRadius : this.newStoreRadius
    fields['addressId'] = (editing ? this.editStoreAddressId : this.newStoreAddressId).toString()
    fields['address'] = editing ? this.editStoreAddressFallbackText : this.newStorePickedAddress
    fields['latitude'] = (editing ? this.editStoreAddressFallbackLatitude : this.newStorePickedLatitude).toString()
    fields['longitude'] = (editing ? this.editStoreAddressFallbackLongitude : this.newStorePickedLongitude).toString()
    fields['images'] = JSON.stringify(editing ? this.editStoreImages : this.newStoreImages)
    return fields
  }

  private applyDraft(fields: Record<string, string>): void {
    let images: string[] = []
    try {
      const parsed: string[] = JSON.parse(fields['images'] ?? '[]') as string[]
      if (Array.isArray(parsed)) { images = parsed.filter((url: string): boolean => typeof url === 'string' && url.startsWith('/uploads/')) }
    } catch (_) {}
    const addressId: number = Number(fields['addressId'] ?? '0')
    const latitude: number = Number(fields['latitude'] ?? '0')
    const longitude: number = Number(fields['longitude'] ?? '0')
    if (this.editingStoreId > 0) {
      if (addressId === -1 && this.validCoordinates(latitude, longitude)) {
        this.editStoreAddressId = -1
        this.editStoreAddressFallbackText = fields['address'] ?? this.editStoreAddressFallbackText
        this.editStoreAddressFallbackLatitude = latitude; this.editStoreAddressFallbackLongitude = longitude
      } else if (this.findMerchantAddress(addressId) !== null) { this.editStoreAddressId = addressId }
      this.editStoreName = fields['name'] ?? this.editStoreName
      this.editStoreNotice = fields['notice'] ?? this.editStoreNotice
      this.editStoreDeliveryFee = fields['fee'] ?? this.editStoreDeliveryFee
      this.editStoreMinOrder = fields['minimum'] ?? this.editStoreMinOrder
      this.editStoreRadius = fields['radius'] ?? this.editStoreRadius
      this.editStoreImages = images
    } else {
      if (this.findMerchantAddress(addressId) !== null) { this.newStoreAddressId = addressId }
      if (this.validCoordinates(latitude, longitude)) {
        this.newStorePickedAddress = fields['address'] ?? ''
        this.newStorePickedLatitude = latitude; this.newStorePickedLongitude = longitude
      }
      this.newStoreName = fields['name'] ?? this.newStoreName
      this.newStoreNotice = fields['notice'] ?? this.newStoreNotice
      this.newStoreDeliveryFee = fields['fee'] ?? this.newStoreDeliveryFee
      this.newStoreMinOrder = fields['minimum'] ?? this.newStoreMinOrder
      this.newStoreRadius = fields['radius'] ?? this.newStoreRadius
      this.newStoreImages = images
    }
    this.rebuildStoreAddressOptions()
  }

  onDraftChange(): void {
    if (!this.initialized || this.loading) { return }
    clearTimeout(this.draftTimer)
    this.draftTimer = setTimeout(() => { this.saveDraft() }, 400)
  }
  private async saveDraft(): Promise<void> {
    if (!(await this.draft.save(this.draftFields()))) { this.draftError = '草稿保存失败，请勿关闭页面'; promptAction.showToast({ message: this.draftError }) }
  }
  private async finish(): Promise<void> {
    clearTimeout(this.draftTimer)
    if (!(await this.draft.clear())) { promptAction.showToast({ message: '已保存，旧草稿清理失败' }) }
    router.back()
  }
  async refreshMerchantAddresses(): Promise<void> {
    await syncAddressesRemote()
    const latestAddresses: Address[] = AppStorage.get<Address[]>('addressList') || []
    this.merchantAddresses = latestAddresses.slice()
    this.rebuildStoreAddressOptions()
    this.applyPendingAddressSelection()
  }

  private getAddressText(address: Address): string {
    return `${address.address} ${address.detail}`.trim()
  }

  private getAddressOptionText(address: Address): string {
    const addressText: string = this.getAddressText(address)
    const tag: string = address.tag === undefined ? '' : address.tag.trim()
    if (tag === '') {
      return addressText
    }
    return `${tag} · ${addressText}`
  }

  private buildAddressOptions(includeStoreFallback: boolean): MerchantAddressOption[] {
    const options: MerchantAddressOption[] = []
    if (includeStoreFallback && this.editStoreAddressFallbackText !== '') {
      options.push(MerchantAddressOption.create(-1, `当前店铺地址：${this.editStoreAddressFallbackText}`))
    }
    for (const address of this.merchantAddresses) {
      const addressText: string = this.getAddressOptionText(address)
      if (addressText !== '') {
        options.push(MerchantAddressOption.create(address.id, addressText))
      }
    }
    options.push(MerchantAddressOption.create(0, '＋ 新增地址'))
    return options
  }

  private findOptionIndex(options: MerchantAddressOption[], addressId: number): number {
    for (let i = 0; i < options.length; i++) {
      if (options[i].id === addressId) {
        return i
      }
    }
    return -1
  }

  private rebuildStoreAddressOptions(): void {
    this.storeAddressOptions = this.buildAddressOptions(false)
    this.editStoreAddressOptions = this.buildAddressOptions(true)
    this.newStoreAddressIndex = this.findOptionIndex(this.storeAddressOptions, this.newStoreAddressId)
    this.editStoreAddressIndex = this.findOptionIndex(this.editStoreAddressOptions, this.editStoreAddressId)
  }

  private getPreferredAddressId(): number {
    const current: Address | null = AppStorage.get<Address>('currentAddress') ?? null
    if (current !== null && this.merchantAddresses.some((address: Address) => address.id === current.id)) {
      return current.id
    }
    const defaultAddress: Address | undefined = this.merchantAddresses.find((address: Address) => address.isDefault)
    if (defaultAddress !== undefined) {
      return defaultAddress.id
    }
    return this.merchantAddresses.length > 0 ? this.merchantAddresses[0].id : 0
  }

  private findMerchantAddress(addressId: number): Address | null {
    const address: Address | undefined = this.merchantAddresses.find((item: Address) => item.id === addressId)
    return address === undefined ? null : address
  }

  private validCoordinates(latitude: number, longitude: number): boolean {
    return Number.isFinite(latitude) && Number.isFinite(longitude)
      && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
      && !(latitude === 0 && longitude === 0)
  }

  private applyPendingAddressSelection(): void {
    const pending: boolean = AppStorage.get<boolean>('merchantAddressSelectionMode') || false
    if (!pending) {
      return
    }
    const target: string = AppStorage.get<string>('merchantAddressSelectionTarget') || 'new'
    const selected: Address | null = AppStorage.get<Address>('currentAddress') ?? null
    if (selected !== null && this.findMerchantAddress(selected.id) !== null) {
      if (target === 'edit') {
        this.editStoreAddressId = selected.id
        this.editStoreAddressIndex = this.findOptionIndex(this.editStoreAddressOptions, selected.id)
      } else {
        this.newStoreAddressId = selected.id
        this.newStoreAddressIndex = this.findOptionIndex(this.storeAddressOptions, selected.id)
      }
    }
    AppStorage.setOrCreate<boolean>('merchantAddressSelectionMode', false)
    AppStorage.setOrCreate<string>('merchantAddressSelectionTarget', '')
    this.rebuildStoreAddressOptions()
  }

  private openStoreLocationPicker(target: string): void {
    AppStorage.setOrCreate<boolean>('storeLocationPickMode', true)
    AppStorage.setOrCreate<string>('storeLocationPickTarget', target)
    router.pushUrl({ url: 'pages/LocationPage' })
  }

  private applyPickedStoreLocation(): void {
    const picked: Address | null = AppStorage.get<Address>('pickedStoreLocation') ?? null
    if (picked === null) {
      return
    }
    const text: string = joinAddressParts(picked.address ?? '', picked.detail ?? '')
    const target: string = AppStorage.get<string>('storeLocationPickTarget') || 'new'
    if (text !== '') {
      if (target === 'edit') {
        // 编辑：写进"店铺自有地址"通道（下拉框里显示为当前门店位置），坐标一并更新
        this.editStoreAddressFallbackText = text
        this.editStoreAddressFallbackLatitude = picked.latitude ?? 0
        this.editStoreAddressFallbackLongitude = picked.longitude ?? 0
        this.editStoreAddressId = -1
        this.rebuildStoreAddressOptions()
      } else {
        this.newStorePickedAddress = text
        this.newStorePickedLatitude = picked.latitude ?? 0
        this.newStorePickedLongitude = picked.longitude ?? 0
      }
      logInfo('Merchant', `门店定位已选（${target}）：${text}`)
    }
    AppStorage.setOrCreate<Address | null>('pickedStoreLocation', null)
    AppStorage.setOrCreate<string>('storeLocationPickTarget', '')
    this.onDraftChange()
  }

  private openStoreAddressManager(target: string): void {
    AppStorage.setOrCreate<boolean>('addressSelectionMode', true)
    AppStorage.setOrCreate<boolean>('merchantAddressSelectionMode', true)
    AppStorage.setOrCreate<string>('merchantAddressSelectionTarget', target)
    AppStorage.setOrCreate<boolean>('merchantOpenAddressForm', true)
    router.pushUrl({ url: 'pages/AddressListPage' })
  }

  private handleStoreAddressSelect(target: string, index: number): void {
    const options: MerchantAddressOption[] = target === 'edit'
      ? this.editStoreAddressOptions : this.storeAddressOptions
    if (index < 0 || index >= options.length) {
      promptAction.showToast({ message: '地址选项不可用，请刷新后重试', duration: 1600 })
      return
    }
    const option: MerchantAddressOption = options[index]
    if (option.id === 0) {
      this.openStoreAddressManager(target)
      return
    }
    if (target === 'edit') {
      this.editStoreAddressId = option.id
      this.editStoreAddressIndex = index
    } else {
      this.newStoreAddressId = option.id
      this.newStoreAddressIndex = index
    }
    this.onDraftChange()
  }

  onBackPress(): boolean { return this.savingStore || this.creatingStore || this.imageUploading }

  async openAddStoreForm(): Promise<void> {
    if (this.merchantAddresses.length === 0) {
      await this.refreshMerchantAddresses()
    }
    this.creatingStore = false
    this.newStoreImages = []
    this.newStoreAddressId = this.getPreferredAddressId()
    this.rebuildStoreAddressOptions()
    this.newStoreAddressIndex = this.findOptionIndex(this.storeAddressOptions, this.newStoreAddressId)
  }

  startEditStore(store: StoreItem) {
    this.editingStoreId = store.id
    this.editStoreName = store.name
    this.editStoreNotice = store.notice
    this.editStoreDeliveryFee = store.deliveryFee.toString()
    this.editStoreMinOrder = store.minOrder.toString()
    this.editStoreImages = store.images ?? (store.image ? [store.image] : [])
    const radiusMeters: number = store.deliveryRadius ?? 0
    this.editStoreRadius = radiusMeters > 0
      ? `${radiusMeters / 1000}` : `${MERCHANT_RADIUS_DEFAULT_KM}`
    this.editStoreAddressFallbackText = (store.address || '').trim()
    this.editStoreAddressFallbackLatitude = store.latitude ?? 0
    this.editStoreAddressFallbackLongitude = store.longitude ?? 0
    const matchedAddress: Address | undefined = this.merchantAddresses.find((address: Address) =>
      this.getAddressText(address) === this.editStoreAddressFallbackText)
    this.editStoreAddressId = matchedAddress !== undefined ? matchedAddress.id : -1
    this.rebuildStoreAddressOptions()
    this.editStoreAddressIndex = this.findOptionIndex(this.editStoreAddressOptions, this.editStoreAddressId)
    this.savingStore = false
  }

  async doCreateStore() {
    if (this.creatingStore || this.imageUploading) {
      promptAction.showToast({ message: '店铺正在创建，请稍候', duration: 1400 })
      return
    }
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    const name: string = this.newStoreName.trim()
    if (name === '') {
      promptAction.showToast({ message: '请输入店铺名称' })
      return
    }
    // 门店位置优先用「定位选点」的结果（地图选点），没定位过才回落到已保存地址
    const picked: boolean = this.newStorePickedAddress !== ''
    const selectedAddress: Address | null = picked ? null : this.findMerchantAddress(this.newStoreAddressId)
    if (!picked && selectedAddress === null) {
      promptAction.showToast({ message: '请选择店铺地址，或点「定位选择店铺位置」用地图选点' })
      return
    }
    let address: string = this.newStorePickedAddress
    if (!picked) {
      address = this.getAddressText(selectedAddress as Address)
    }
    if (address === '') {
      promptAction.showToast({ message: '所选地址内容为空，请先完善地址信息' })
      return
    }
    // 「|| 3」会把合法的 0（免配送费）当成空值改回 3；先判空再解析，并挡住非数字与负数
    const fee = this.newStoreDeliveryFee.trim() === '' ? 3 : Number(this.newStoreDeliveryFee)
    const minOrder = this.newStoreMinOrder.trim() === '' ? 20 : Number(this.newStoreMinOrder)
    if (!Number.isFinite(fee) || !Number.isFinite(minOrder) || fee < 0 || minOrder < 0) {
      promptAction.showToast({ message: '配送费和起送价必须是非负数字', duration: 1800 })
      return
    }
    const radiusKm: number = this.newStoreRadius.trim() === ''
      ? MERCHANT_RADIUS_DEFAULT_KM : Number(this.newStoreRadius)
    if (!this.validRadius(radiusKm)) {
      return
    }
    const radius: number = Math.round(radiusKm * 1000)
    this.creatingStore = true
    let latitude: number = this.newStorePickedLatitude
    let longitude: number = this.newStorePickedLongitude
    if (!picked) {
      const saved: Address = selectedAddress as Address
      latitude = saved.latitude ?? 0
      longitude = saved.longitude ?? 0
    }
    if (!this.validCoordinates(latitude, longitude)) {
      const addressResults: AddressSearchResult[] = await searchAddress(address)
      if (!this.session.current(version)) { return }
      if (addressResults.length === 0) {
        this.creatingStore = false
        promptAction.showToast({ message: '所选地址无法定位，请到地址管理中补充更详细的地址', duration: 2200 })
        return
      }
      const location: AddressSearchResult = addressResults[0]
      latitude = location.latitude
      longitude = location.longitude
    }
    const created: StoreItem | null = await createMerchantStoreApi(name, 1, fee, minOrder, '30分钟',
      this.newStoreNotice.trim() || '欢迎光临', address, latitude, longitude, this.newStoreImages[0] ?? '', radius, this.newStoreImages)
    if (!this.session.current(version)) { return }
    if (created === null) {
      this.creatingStore = false
      promptAction.showToast({ message: '创建失败，请检查网络或登录状态' })
      return
    }
    this.newStoreName = ''
    this.newStoreNotice = ''
    this.newStoreImages = []
    this.newStoreRadius = `${MERCHANT_RADIUS_DEFAULT_KM}`
    this.newStorePickedAddress = ''
    this.newStorePickedLatitude = 0
    this.newStorePickedLongitude = 0
    this.newStoreAddressId = 0
    this.newStoreAddressIndex = -1
    await this.finish()
    this.creatingStore = false
    promptAction.showToast({ message: '店铺已提交，等待平台审核', duration: 1800 })
  }

  private validRadius(km: number): boolean {
    if (Number.isFinite(km) && km >= DELIVERY_RANGE.STORE_MIN_KM && km <= DELIVERY_RANGE.STORE_MAX_KM) {
      return true
    }
    promptAction.showToast({ message: `请输入${MERCHANT_RADIUS_LABEL}`, duration: 2000 })
    return false
  }

  async doEditStore() {
    if (this.savingStore || this.imageUploading) {
      promptAction.showToast({ message: '店铺正在保存，请稍候', duration: 1400 })
      return
    }
    const version: number = this.session.request()
    if (!this.session.current(version)) { return }
    const name: string = this.editStoreName.trim()
    if (name === '') {
      promptAction.showToast({ message: '店铺名称不能为空' })
      return
    }
    const originalStore = this.myStores.find(s => s.id === this.editingStoreId)
    if (originalStore === undefined || originalStore === null) {
      promptAction.showToast({ message: '店铺信息已变化，请刷新后重试', duration: 1800 })
      return
    }
    // 留空表示「不修改」而不是「改成 0」：原写法空输入会把配送费静默改成 0
    const fee = this.editStoreDeliveryFee.trim() === '' ? originalStore.deliveryFee : Number(this.editStoreDeliveryFee)
    const minOrder = this.editStoreMinOrder.trim() === '' ? originalStore.minOrder : Number(this.editStoreMinOrder)
    if (!Number.isFinite(fee) || !Number.isFinite(minOrder) || fee < 0 || minOrder < 0) {
      promptAction.showToast({ message: '配送费和起送价必须是非负数字', duration: 1800 })
      return
    }
    const keepRadius: boolean = this.editStoreRadius.trim() === ''
    const radiusKm: number = Number(this.editStoreRadius)
    if (!keepRadius && !this.validRadius(radiusKm)) { return }
    const radius: number = keepRadius ? -1 : Math.round(radiusKm * 1000)
    this.savingStore = true
    const selectedAddress: Address | null = this.findMerchantAddress(this.editStoreAddressId)
    let address: string = ''
    let latitude: number = 0
    let longitude: number = 0
    if (this.editStoreAddressId === -1 && this.editStoreAddressFallbackText !== '') {
      address = this.editStoreAddressFallbackText
      latitude = this.editStoreAddressFallbackLatitude
      longitude = this.editStoreAddressFallbackLongitude
    } else if (selectedAddress !== null) {
      address = this.getAddressText(selectedAddress)
      latitude = selectedAddress.latitude ?? 0
      longitude = selectedAddress.longitude ?? 0
    }
    if (address === '') {
      this.savingStore = false
      promptAction.showToast({ message: '请选择一个已保存的店铺地址' })
      return
    }
    if (!this.validCoordinates(latitude, longitude)) {
      const addressResults: AddressSearchResult[] = await searchAddress(address)
      if (!this.session.current(version)) { return }
      if (addressResults.length === 0) {
        this.savingStore = false
        promptAction.showToast({ message: '所选地址无法定位，请到地址管理中补充更详细的地址', duration: 2200 })
        return
      }
      const location: AddressSearchResult = addressResults[0]
      latitude = location.latitude
      longitude = location.longitude
    }
    const updated: StoreItem | null = await updateMerchantStoreApi(originalStore.id, name, fee, minOrder,
      originalStore.deliveryTime, this.editStoreNotice.trim() || '欢迎光临', address, latitude, longitude,
      this.editStoreImages[0] ?? '', radius, this.editStoreImages)
    if (!this.session.current(version)) { return }
    if (updated === null) {
      this.savingStore = false
      promptAction.showToast({ message: '保存失败，请稍后重试' })
      return
    }
    await this.finish()
    this.savingStore = false
    promptAction.showToast({ message: '保存成功' })
  }

  build() {
    Stack() {
      Column() {
        PageHeader({ title: this.editingStoreId > 0 ? '编辑门店 · ' + this.editStoreName : '新建门店', onBack: () => { router.back() } })
        if (this.draftError !== '') { Text(this.draftError).fontColor(COLORS.ERROR).fontSize(FONT_SIZE.SM).padding(SPACING.SM) }
        if (this.loading || this.loadFailed) {
          RemoteState({ loading: this.loading, failed: this.loadFailed, onRetry: () => { this.initialize() } })
        } else if (this.editingStoreId > 0) {
            Scroll() {
              Column({ space: SPACING.MD }) {
                Column({ space: SPACING.XS }) {

                  FormInput({ label: '店铺名称',
                    value: this.editStoreName,
                    placeholder: '请输入店铺名称，如：老王快餐店',
                    onChange: (v: string) => { this.editStoreName = v },
                    fieldId: 'MerchantCenterPage-editStoreName',
                    required: true }).width('100%')
                }
                Column({ space: SPACING.XS }) {
                  Text('店铺地址（必填，用于计算距离）')
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  if (this.editStoreAddressOptions.length > 1) {
                    FormSelect({ label: '店铺地址',
          options: this.editStoreAddressOptions,
          selected: this.editStoreAddressIndex,
          onSelect: (index: number, value: string) => { this.handleStoreAddressSelect('edit', index) } })
                  } else {
                    Button('暂无保存地址，去新增地址')
                      .attributeModifier(new AppButtonStyle())
                      .width('100%').height(44).fontSize(FONT_SIZE.SM)
                      .fontColor(MODULE_COLOR.MERCHANT).backgroundColor(MODULE_BG.MERCHANT)
                      .borderRadius(BORDER_RADIUS.ROUND)
                      .onClick(() => { this.openStoreAddressManager('edit') })
                  }
                  Button('定位选择店铺位置（地图选点）')
                    .attributeModifier(new AppButtonStyle())
                    .width('100%').height(40).fontSize(FONT_SIZE.SM)
                    .fontColor(MODULE_COLOR.MERCHANT).backgroundColor(MODULE_BG.MERCHANT)
                    .borderRadius(BORDER_RADIUS.ROUND)
                    .onClick(() => { this.openStoreLocationPicker('edit') })
                }
                Column({ space: SPACING.XS }) {

                  FormInput({ label: '店铺公告',
                    value: this.editStoreNotice,
                    placeholder: '请输入店铺公告，如：本店支持免配送费',
                    onChange: (v: string) => { this.editStoreNotice = v },
                    fieldId: 'MerchantCenterPage-editStoreNotice' }).width('100%')
                }
                Column({ space: SPACING.XS }) {
                  Text('店铺照片（选填）')
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  ImageUpload({ images: this.editStoreImages, maxFiles: 20, recommendedFiles: 5, disabled: this.creatingStore || this.savingStore,
                    contextVersion: (): number => this.editingStoreId,
                    onChange: (images: string[]) => { this.editStoreImages = images },
                    onBusy: (busy: boolean) => { this.imageUploading = busy } })
                }
                Row({ space: SPACING.MD }) {
                  Column({ space: SPACING.XS }) {

                    FormInput({ label: '配送费（元）',
                      value: this.editStoreDeliveryFee,
                      placeholder: '如：3',
                      inputType: InputType.Number,
                      onChange: (v: string) => { this.editStoreDeliveryFee = v },
                      fieldId: 'MerchantCenterPage-editStoreDeliveryFee',
                      required: true }).width('100%')
                  }
                  .layoutWeight(1)
                  Column({ space: SPACING.XS }) {

                    FormInput({ label: '起送价（元）',
                      value: this.editStoreMinOrder,
                      placeholder: '如：20',
                      inputType: InputType.Number,
                      onChange: (v: string) => { this.editStoreMinOrder = v },
                      fieldId: 'MerchantCenterPage-editStoreMinOrder',
                      required: true }).width('100%')
                  }
                  .layoutWeight(1)
                }
                Column({ space: SPACING.XS }) {
                  Text(MERCHANT_RADIUS_LABEL)
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  FormInput({ label: '配送半径（公里）',
                    value: this.editStoreRadius,
                    placeholder: `如：${MERCHANT_RADIUS_DEFAULT_KM}`,
                    inputType: InputType.Number,
                    fieldId: 'merchant-radius-input-edit',
                    onChange: (v: string) => { this.editStoreRadius = v },
                    required: true }).width('100%')
                }
              }
              .width('100%')
            }.align(Alignment.Top)
            .width('100%').layoutWeight(1).scrollBar(BarState.Off)
            Row({ space: SPACING.MD }) {
              Button('取消')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1).height(42).fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.savingStore && !this.creatingStore && !this.imageUploading).onClick(() => { router.back() })
              Button(this.savingStore ? '保存中...' : '确认保存')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1).height(42).fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY).backgroundColor(MODULE_COLOR.MERCHANT)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.savingStore && !this.imageUploading).onClick(() => { this.doEditStore() })
            }
        } else {
            Scroll() {
              Column({ space: SPACING.MD }) {
                Column({ space: SPACING.XS }) {

                  FormInput({ label: '店铺名称',
                    value: this.newStoreName,
                    placeholder: '请输入店铺名称，如：老王快餐店',
                    onChange: (v: string) => { this.newStoreName = v },
                    fieldId: 'MerchantCenterPage-newStoreName',
                    required: true }).width('100%')
                }
                Column({ space: SPACING.XS }) {
                  Text('店铺地址（必填，用于计算距离）')
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  if (this.storeAddressOptions.length > 1) {
                    FormSelect({ label: '店铺地址',
          options: this.storeAddressOptions,
          selected: this.newStoreAddressIndex,
          onSelect: (index: number, value: string) => { this.handleStoreAddressSelect('new', index) } })
                  } else {
                    Button('暂无保存地址，去新增地址')
                      .attributeModifier(new AppButtonStyle())
                      .width('100%').height(44).fontSize(FONT_SIZE.SM)
                      .fontColor(MODULE_COLOR.MERCHANT).backgroundColor(MODULE_BG.MERCHANT)
                      .borderRadius(BORDER_RADIUS.ROUND)
                      .onClick(() => { this.openStoreAddressManager('new') })
                  }
                  Button('定位选择店铺位置（地图选点）')
                    .attributeModifier(new AppButtonStyle())
                    .width('100%').height(40).fontSize(FONT_SIZE.SM)
                    .fontColor(MODULE_COLOR.MERCHANT).backgroundColor(MODULE_BG.MERCHANT)
                    .borderRadius(BORDER_RADIUS.ROUND)
                    .onClick(() => { this.openStoreLocationPicker('new') })
                  if (this.newStorePickedAddress !== '') {
                    Text(`已定位门店位置：${this.newStorePickedAddress}`)
                      .fontSize(FONT_SIZE.XS).fontColor(MODULE_COLOR.MERCHANT).width('100%')
                  }
                }
                Column({ space: SPACING.XS }) {

                  FormInput({ label: '店铺公告',
                    value: this.newStoreNotice,
                    placeholder: '请输入店铺公告，如：新店开业，欢迎光临',
                    onChange: (v: string) => { this.newStoreNotice = v },
                    fieldId: 'MerchantCenterPage-newStoreNotice' }).width('100%')
                }
                Column({ space: SPACING.XS }) {
                  Text('店铺照片（选填）')
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  ImageUpload({ images: this.newStoreImages, maxFiles: 20, recommendedFiles: 5, disabled: this.creatingStore || this.savingStore,
                    onChange: (images: string[]) => { this.newStoreImages = images },
                    onBusy: (busy: boolean) => { this.imageUploading = busy } })
                }
                Row({ space: SPACING.MD }) {
                  Column({ space: SPACING.XS }) {

                    FormInput({ label: '配送费（元）',
                      value: this.newStoreDeliveryFee,
                      placeholder: '如：3',
                      inputType: InputType.Number,
                      onChange: (v: string) => { this.newStoreDeliveryFee = v },
                      fieldId: 'MerchantCenterPage-newStoreDeliveryFee',
                      required: true }).width('100%')
                  }
                  .layoutWeight(1)
                  Column({ space: SPACING.XS }) {

                    FormInput({ label: '起送价（元）',
                      value: this.newStoreMinOrder,
                      placeholder: '如：20',
                      inputType: InputType.Number,
                      onChange: (v: string) => { this.newStoreMinOrder = v },
                      fieldId: 'MerchantCenterPage-newStoreMinOrder',
                      required: true }).width('100%')
                  }
                  .layoutWeight(1)
                }
                Column({ space: SPACING.XS }) {
                  Text(`${MERCHANT_RADIUS_LABEL}，默认 ${MERCHANT_RADIUS_DEFAULT_KM} 公里`)
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  FormInput({ label: '配送半径（公里）',
                    value: this.newStoreRadius,
                    placeholder: `如：${MERCHANT_RADIUS_DEFAULT_KM}`,
                    inputType: InputType.Number,
                    fieldId: 'merchant-radius-input-new',
                    onChange: (v: string) => { this.newStoreRadius = v },
                    required: true }).width('100%')
                }
              }
              .width('100%')
            }.align(Alignment.Top)
            .width('100%').layoutWeight(1).scrollBar(BarState.Off)
            Row({ space: SPACING.MD }) {
              Button('取消')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1).height(42).fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.savingStore && !this.creatingStore && !this.imageUploading).onClick(() => { router.back() })
              Button(this.creatingStore ? '创建中...' : '确认创建')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1).height(42).fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY).backgroundColor(MODULE_COLOR.MERCHANT)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.creatingStore && !this.imageUploading).onClick(() => { this.doCreateStore() })
            }
        }
      }.width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

    }.width('100%').height('100%')
  }
}
