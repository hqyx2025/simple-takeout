import { AppButtonStyle, AppCardStyle, AppInputStyle } from '../common/theme/AppTheme'
/**
 * 地址管理页面
 * 支持地址的增删改查与设置默认地址
 */
import { AppMotion } from '../common/theme/AppMotion'
import { Address } from '../model/Models'
import { addAddressRemote, deleteAddressRemote, updateAddressRemote, setDefaultAddressRemote, syncAddressesRemote, deduplicateAddresses, isLoggedIn, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { common } from '@kit.AbilityKit'
import { GeoPosition, getCurrentPosition, reverseGeocodePosition } from '../service/LocationService'

const MAX_ADDRESS_COUNT: number = 20

// 表单数据类（用于避免无类型对象字面量）
class AddressFormData {
  name: string = ''
  phone: string = ''
  address: string = ''
  detail: string = ''
  latitude?: number
  longitude?: number
  tag: string = ''
  isDefault: boolean = false

  static create(): AddressFormData {
    return new AddressFormData()
  }

  static fromAddress(addr: Address): AddressFormData {
    let form = new AddressFormData()
    form.name = addr.name
    form.phone = addr.phone
    const addressText: string = addr.address.trim()
    const detailText: string = addr.detail.trim()
    // 存量服务端只有合并后的 detail；新服务端会分别返回地图位置和门牌。
    if (addressText === '') {
      form.address = detailText
      form.detail = ''
    } else {
      form.address = addressText
      form.detail = detailText
    }
    form.latitude = addr.latitude
    form.longitude = addr.longitude
    form.tag = addr.tag ?? ''
    form.isDefault = addr.isDefault
    return form
  }
}

// 地址标签选项
class AddressTag {
  static readonly SCHOOL: string = '学校'
  static readonly HOME: string = '家'
  static readonly COMPANY: string = '公司'
  static readonly OTHER: string = '其他'
  static readonly ALL: string[] = [AddressTag.SCHOOL, AddressTag.HOME, AddressTag.COMPANY, AddressTag.OTHER]
}

@Entry
@Component
export struct AddressListPage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
  }

  @StorageLink('addressList') addressList: Address[] = []
  @StorageLink('addressSyncState') addressSyncState: string = 'idle'
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State addressListRevision: number = 0
  @State showAddForm: boolean = false
  @State editingAddress: Address | null = null
  @State formData: AddressFormData = new AddressFormData()
  @State locatingCurrent: boolean = false
  @State saving: boolean = false
  @State pendingDeleteAddress: Address | null = null

  onBack: () => void = () => { router.back() }
  onSelectAddress: (address: Address) => void = () => {}

  async aboutToAppear(): Promise<void> {
    // 先清理本地缓存中的重复地址，再等待后端最新数据，避免重复“当前位置”短暂显示。
    const cachedAddresses: Address[] = AppStorage.get<Address[]>('addressList') || []
    const visibleAddresses: Address[] = deduplicateAddresses(cachedAddresses)
      .filter((address: Address) => address.name !== '当前位置')
    AppStorage.setOrCreate<Address[]>('addressList', visibleAddresses)
    if (!isLoggedIn()) {
      this.showLoginRequired()
      return
    }
    // 等待首次同步完成，避免它在设置默认地址后用旧数据覆盖 UI。
    await syncAddressesRemote()
    if (AppStorage.get<boolean>('merchantOpenAddressForm') || false) {
      AppStorage.setOrCreate<boolean>('merchantOpenAddressForm', false)
      this.openAddForm()
    }
  }

  aboutToDisappear(): void {
    // 无论通过选择地址、顶部返回还是系统返回离开，都不能把下一次普通地址管理误判为选择模式。
    AppStorage.setOrCreate<boolean>('addressSelectionMode', false)
  }

  build() {
    Stack() {
      // 主内容
      Column() {
        // 顶部导航栏
        PageHeader({ title: '收货地址', backText: '‹', onBack: () => { this.onBack() } })

        // 地址列表 / 空状态
        if (this.addressList.length === 0) {
          Column({ space: SPACING.SM }) {
            Image($r('app.media.ui_inbox')).width(60).height(60).objectFit(ImageFit.Contain)
              .margin({ top: 80 })
            Text(this.addressSyncState === 'failed' ? '收货地址暂时无法加载'
              : this.addressSyncState === 'loading' ? '正在同步收货地址…' : '暂无收货地址')
              .fontSize(FONT_SIZE.LG)
              .fontColor(COLORS.TEXT_HINT)
            Text(this.addressSyncState === 'failed' ? '请检查网络连接后重试'
              : this.addressSyncState === 'loading' ? '请稍候' : '点击下方按钮添加收货地址')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_HINT)
            if (this.addressSyncState === 'failed') {
              Button('重新加载')
                .attributeModifier(new AppButtonStyle())
                .id('address-retry')
                .onClick(() => { syncAddressesRemote() })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: SPACING.MD }) {
            ForEach(this.addressList, (addr: Address) => {
              ListItem() {
                Column({ space: SPACING.SM }) {
                  // 姓名 + 电话 + 默认标识
                  Row() {
                    Text(addr.name)
                      .fontSize(FONT_SIZE.LG)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(COLORS.TEXT_PRIMARY)
                    Text(addr.phone)
                      .fontSize(FONT_SIZE.MD)
                      .fontColor(COLORS.TEXT_SECONDARY)
                      .margin({ left: SPACING.MD })
                    Blank()
                    if (addr.isDefault) {
                      Text('默认')
                        .fontSize(FONT_SIZE.XS)
                        .fontColor(COLORS.ON_PRIMARY)
                        .backgroundColor(COLORS.PRIMARY)
                        .padding({ left: SPACING.SM, right: SPACING.SM, top: 2, bottom: 2 })
                        .borderRadius(BORDER_RADIUS.SM)
                    }
                  }
                  .width('100%')

                  // 地址详情
                  Text(this.getDisplayAddress(addr))
                    .fontSize(FONT_SIZE.MD)
                    .fontColor(COLORS.TEXT_SECONDARY)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')

                  // 标签 + 操作按钮
                  Row() {
                    if (addr.tag !== undefined && addr.tag !== '') {
                      Text(addr.tag)
                        .fontSize(FONT_SIZE.XS)
                        .fontColor(COLORS.TEXT_SECONDARY)
                        .backgroundColor(COLORS.BG_PRIMARY)
                        .padding({ left: SPACING.SM, right: SPACING.SM, top: 2, bottom: 2 })
                        .borderRadius(BORDER_RADIUS.SM)
                    }
                    Blank()
                    Button('编辑', { type: ButtonType.Normal })
                      .id(`address-edit-${addr.id}`)
                      .attributeModifier(new AppButtonStyle())
                      .height(44)
                      .constraintSize({ minWidth: 52 })
                      .fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.PRIMARY)
                      .backgroundColor(Color.Transparent)
                      .padding({ left: SPACING.SM, right: SPACING.SM })
                      .onClick(() => { this.openEditForm(addr) })
                    Button('删除', { type: ButtonType.Normal })
                      .attributeModifier(new AppButtonStyle())
                      .height(44)
                      .constraintSize({ minWidth: 52 })
                      .fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.ERROR)
                      .backgroundColor(Color.Transparent)
                      .padding({ left: SPACING.SM, right: SPACING.SM })
                      .onClick(() => { this.requestDeleteAddress(addr) })
                    if (!addr.isDefault) {
                      Button('设为默认', { type: ButtonType.Normal })
                        .attributeModifier(new AppButtonStyle())
                        .height(44)
                        .constraintSize({ minWidth: 76 })
                        .fontSize(FONT_SIZE.SM)
                        .fontColor(COLORS.TEXT_SECONDARY)
                        .backgroundColor(Color.Transparent)
                        .padding({ left: SPACING.SM, right: SPACING.SM })
                        .onClick(() => { this.setDefault(addr) })
                    }
                  }
                  .width('100%')
                }
                  .attributeModifier(new AppCardStyle())
                .width('100%')
                .padding(SPACING.LG)
                .onClick(() => {
                  // 选择该地址作为当前配送地址（首页/结算页联动）
                  AppStorage.setOrCreate<Address>('currentAddress', addr)
                  this.onSelectAddress(addr)
                  const selectionMode: boolean = AppStorage.get<boolean>('addressSelectionMode') || false
                  if (selectionMode) {
                    AppStorage.setOrCreate<boolean>('addressSelectionMode', false)
                    router.back()
                  }
                })
              }
            }, (item: Address) => `${this.addressListRevision}-${item.id}-${item.isDefault ? 'default' : 'normal'}`)
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM })
          .layoutWeight(1)
          .divider({ strokeWidth: 0 })
        }

        if (this.addressList.length >= MAX_ADDRESS_COUNT) {
          Text(`已保存 ${MAX_ADDRESS_COUNT} 个收货地址，请先删除不再使用的地址后再新增`)
            .width('90%').constraintSize({ maxWidth: 460 })
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
            .textAlign(TextAlign.Center)
            .padding({ top: SPACING.MD, bottom: SPACING.MD })
        } else {
          Button('+ 新增收货地址').id('address-add')
            .attributeModifier(new AppButtonStyle())
            .width('90%').constraintSize({ maxWidth: 460 })
            .height(48)
            .fontSize(FONT_SIZE.LG).fontColor(COLORS.ON_PRIMARY)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .margin({ top: SPACING.MD, bottom: SPACING.SM })
            .onClick(() => { this.openAddForm() })
        }

      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 新增/编辑表单弹窗
      if (this.showAddForm) {
        Column() {
          Column({ space: SPACING.MD }) {
            Scroll() {
              Column({ space: SPACING.MD }) {
              Text(this.editingAddress === null ? '新增地址' : '编辑地址')
                .fontSize(FONT_SIZE.XL)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
                .width('100%')
                .textAlign(TextAlign.Center)

            Text('收货人').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).width('100%')
            TextInput({ placeholder: '收货人姓名（如：张女士）', text: this.formData.name })
              .attributeModifier(new AppInputStyle()).id('address-name').accessibilityText('收货人')
              .width('100%')
              .onChange((v: string) => { this.formData.name = v })

            Text('联系电话').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).width('100%')
            TextInput({ placeholder: '11 位手机号（如：13800138000）', text: this.formData.phone })
              .attributeModifier(new AppInputStyle()).id('address-phone').accessibilityText('联系电话')
              .width('100%')
              .type(InputType.PhoneNumber)
              .onChange((v: string) => { this.formData.phone = v })

              Row() {
                Text('地图位置')
                  .fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.TEXT_SECONDARY)
                Blank()
                Image($r('app.media.home_location')).width(FONT_SIZE.MD).height(FONT_SIZE.MD)
                  .objectFit(ImageFit.Contain)
                Text(this.locatingCurrent ? ' 正在定位…' : ' 定位选择当前位置')
                  .fontSize(FONT_SIZE.SM)
                  .fontColor(this.locatingCurrent ? COLORS.TEXT_HINT : COLORS.PRIMARY)
                  .onClick(() => { this.fillCurrentLocation() })
              }
              .width('100%')

            TextInput({ placeholder: '地图位置（如：南宁学院东门）', text: this.formData.address })
              .attributeModifier(new AppInputStyle())
              .width('100%').id('address-map-address').accessibilityText('地图位置')
              .onChange((v: string) => { this.changeMapAddress(v) })

            Text(this.hasFormCoordinates() ? '已定位'
              : '地址已修改，请重新定位')
              .fontSize(FONT_SIZE.XS)
              .fontColor(this.hasFormCoordinates() ? COLORS.TEXT_SECONDARY : COLORS.TEXT_HINT)
              .width('100%')

            Text('详细地址（选填）').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).width('100%')
            TextInput({ placeholder: '楼栋、楼层或门牌（如：3 栋 1206，东门进入）', text: this.formData.detail })
              .attributeModifier(new AppInputStyle()).id('address-detail').accessibilityText('详细地址（选填）')
              .width('100%')
              .onChange((v: string) => { this.formData.detail = v })

            Text('学校、园区请填写宿舍楼或取餐点；确无门牌可留空')
              .fontSize(FONT_SIZE.XS)
              .fontColor(COLORS.TEXT_HINT)
              .width('100%')

            // 标签选择
            Row() {
              Text('标签')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
              Blank()
              ForEach(AddressTag.ALL, (tag: string) => {
                Text(tag)
                  .fontSize(FONT_SIZE.SM)
                  .fontColor(this.formData.tag === tag ? COLORS.ON_PRIMARY : COLORS.TEXT_SECONDARY)
                  .backgroundColor(this.formData.tag === tag ? COLORS.PRIMARY : COLORS.BG_PRIMARY)
                  .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.XS, bottom: SPACING.XS })
                  .borderRadius(BORDER_RADIUS.ROUND)
                  .margin({ left: SPACING.XS })
                  .onClick(() => { this.selectTag(tag) })
              }, (tag: string) => tag)
            }
            .width('100%')

            // 默认地址开关
            Row() {
              Text('设为默认地址')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_PRIMARY)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.formData.isDefault })
                .onChange((isOn: boolean) => { this.formData.isDefault = isOn })
            }
            .width('100%')
              }
              .width('100%')
              .enabled(!this.saving)
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)

            Row({ space: SPACING.MD }) {
            Button('取消').id('address-form-cancel')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1)
                .height(44)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.saving)
                .onClick(() => { this.showAddForm = false })
            Button(this.saving ? '保存中…' : '保存').id('address-form-save')
                .attributeModifier(new AppButtonStyle())
                .layoutWeight(1)
                .height(44)
                .fontSize(FONT_SIZE.MD).fontColor(COLORS.ON_PRIMARY)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .enabled(!this.saving)
                .onClick(() => { this.doSave() })
            }
            .width('100%')
          }
          .attributeModifier(new AppCardStyle())
          .width('90%')
          .height('88%')
          .constraintSize({ maxWidth: 460 })
          .padding(SPACING.XL)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.OVERLAY)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      if (this.pendingDeleteAddress !== null) {
        ConfirmDialog({
          title: '删除收货地址',
          content: this.getDeleteConfirmContent(),
          confirmText: '确认删除',
          cancelText: '取消',
          onConfirm: () => { this.confirmDeleteAddress() },
          onCancel: () => { this.pendingDeleteAddress = null }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 打开新增表单
  openAddForm(): void {
    if (this.addressList.length >= MAX_ADDRESS_COUNT) {
      promptAction.showToast({
        message: `最多保存 ${MAX_ADDRESS_COUNT} 个收货地址，请先删除不再使用的地址`, duration: 1800
      })
      return
    }
    this.editingAddress = null
    this.formData = AddressFormData.create()
    this.locatingCurrent = false
    this.showAddForm = true
  }

  // 打开编辑表单
  openEditForm(addr: Address): void {
    this.editingAddress = addr
    this.formData = AddressFormData.fromAddress(addr)
    this.locatingCurrent = false
    this.showAddForm = true
  }

  private async fillCurrentLocation(): Promise<void> {
    if (this.locatingCurrent) {
      return
    }
    if (!isLoggedIn()) {
      this.showLoginRequired()
      return
    }
    this.locatingCurrent = true
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const position: GeoPosition = await getCurrentPosition(context)
      const addressText: string = await reverseGeocodePosition(position)
      if (addressText.trim() === '') {
        promptAction.showToast({ message: '未能解析当前位置，请手动填写地址', duration: 1800 })
        return
      }
      const nextForm: AddressFormData = new AddressFormData()
      nextForm.name = this.formData.name
      nextForm.phone = this.formData.phone
      nextForm.address = addressText
      nextForm.detail = this.formData.detail
      nextForm.latitude = position.latitude
      nextForm.longitude = position.longitude
      nextForm.tag = this.formData.tag
      nextForm.isDefault = this.formData.isDefault
      this.formData = nextForm
      promptAction.showToast({ message: '当前位置已填入地址', duration: 1200 })
    } catch (err) {
      promptAction.showToast({ message: '定位失败，请手动填写地址', duration: 1800 })
    } finally {
      this.locatingCurrent = false
    }
  }

  // 选择标签（重新赋值以触发UI更新）
  selectTag(tag: string): void {
    let form = new AddressFormData()
    form.name = this.formData.name
    form.phone = this.formData.phone
    form.address = this.formData.address
    form.detail = this.formData.detail
    form.latitude = this.formData.latitude
    form.longitude = this.formData.longitude
    form.tag = tag
    form.isDefault = this.formData.isDefault
    this.formData = form
  }

  private hasFormCoordinates(): boolean {
    return this.formData.latitude !== undefined && this.formData.longitude !== undefined
      && Number.isFinite(this.formData.latitude) && Number.isFinite(this.formData.longitude)
  }

  private changeMapAddress(value: string): void {
    const form: AddressFormData = new AddressFormData()
    form.name = this.formData.name
    form.phone = this.formData.phone
    form.address = value
    form.detail = this.formData.detail
    form.tag = this.formData.tag
    form.isDefault = this.formData.isDefault
    if (value.trim() === this.formData.address.trim()) {
      form.latitude = this.formData.latitude
      form.longitude = this.formData.longitude
    }
    this.formData = form
  }

  private showLoginRequired(): void {
    promptAction.showToast({ message: '登录状态已失效，请先登录后继续操作', duration: 1800 })
  }

  private showOperationFailure(action: string, detail: string = ''): void {
    if (!isLoggedIn()) {
      this.showLoginRequired()
      return
    }
    const message: string = detail.trim() !== '' ? detail : `${action}失败，请检查网络后重试`
    promptAction.showToast({ message: message, duration: 2200 })
  }

  private copyAddresses(source: Address[], defaultId?: number): Address[] {
    const copied: Address[] = []
    source.forEach((item: Address) => {
      const address: Address = {
        id: item.id,
        name: item.name,
        phone: item.phone,
        address: item.address,
        detail: item.detail,
        isDefault: defaultId === undefined ? item.isDefault : item.id === defaultId,
        tag: item.tag,
        latitude: item.latitude,
        longitude: item.longitude
      }
      copied.push(address)
    })
    return copied
  }

  private applyAddressList(addresses: Address[]): void {
    const next: Address[] = this.copyAddresses(deduplicateAddresses(addresses))
    this.addressList = next
    AppStorage.setOrCreate<Address[]>('addressList', next)
    // ForEach 以地址 ID 复用列表项时，内容字段变化可能不会重新创建子树；
    // revision 参与 key，确保编辑后姓名、电话和地址文本立即重绘。
    this.addressListRevision += 1
  }

  private getDisplayAddress(addr: Address): string {
    return `${addr.address} ${addr.detail}`.trim()
  }

  private getFormAddressDetail(): string {
    const addressText: string = this.formData.address.trim()
    const detailText: string = this.formData.detail.trim()
    if (addressText === '') {
      return detailText
    }
    if (detailText === '' || addressText === detailText || addressText.endsWith(` ${detailText}`)) {
      return addressText
    }
    return `${addressText} ${detailText}`
  }

  private applyEditedAddress(): void {
    if (this.editingAddress === null) {
      return
    }
    const editingId: number = this.editingAddress.id
    const mapAddressChanged: boolean = this.editingAddress.address.trim() !== this.formData.address.trim()
    const source: Address[] = AppStorage.get<Address[]>('addressList') || this.addressList
    const updated: Address[] = this.copyAddresses(source)
    updated.forEach((item: Address) => {
      if (item.id === editingId) {
        item.name = this.formData.name.trim()
        item.phone = this.formData.phone.trim()
        item.address = this.formData.address.trim()
        item.detail = this.formData.detail.trim()
        item.tag = this.formData.tag
        item.isDefault = this.formData.isDefault
        if (this.hasFormCoordinates()) {
          item.latitude = this.formData.latitude
          item.longitude = this.formData.longitude
        } else if (mapAddressChanged) {
          item.latitude = undefined
          item.longitude = undefined
        }
      } else if (this.formData.isDefault) {
        item.isDefault = false
      }
    })
    this.applyAddressList(updated)
  }

  private requestDeleteAddress(addr: Address): void {
    this.pendingDeleteAddress = addr
  }

  private getDeleteConfirmContent(): string {
    const addr: Address | null = this.pendingDeleteAddress
    return addr === null ? '' : `确认删除“${this.getDisplayAddress(addr)}”？删除后无法恢复。`
  }

  private confirmDeleteAddress(): void {
    const addr: Address | null = this.pendingDeleteAddress
    this.pendingDeleteAddress = null
    if (addr !== null) {
      this.deleteAddress(addr)
    }
  }

  // 设为默认地址
  async setDefault(addr: Address): Promise<void> {
    if (!isLoggedIn()) {
      this.showLoginRequired()
      return
    }

    const previous: Address[] = this.copyAddresses(this.addressList)
    // 先更新当前页面，接口成功后再用服务端同步结果校准，保证点击后立即有反馈。
    this.applyAddressList(this.copyAddresses(this.addressList, addr.id))
    const ok: boolean = await setDefaultAddressRemote(addr.id)
    if (!ok) {
      this.applyAddressList(previous)
      this.showOperationFailure('设置默认地址')
      return
    }

    const syncedAddresses: Address[] = AppStorage.get<Address[]>('addressList') || this.addressList
    this.applyAddressList(this.copyAddresses(syncedAddresses, addr.id))
    promptAction.showToast({ message: '已设为默认地址', duration: 1200 })
  }

  async deleteAddress(addr: Address): Promise<void> {
    if (!isLoggedIn()) {
      this.showLoginRequired()
      return
    }
    const ok: boolean = await deleteAddressRemote(addr.id)
    if (!ok) {
      this.showOperationFailure('删除地址')
      return
    }
    const syncedAddresses: Address[] = AppStorage.get<Address[]>('addressList') || []
    this.applyAddressList(syncedAddresses)
    promptAction.showToast({ message: '地址已删除', duration: 1200 })
  }

  // 保存地址
  async doSave(): Promise<void> {
    if (this.saving) {
      return
    }
    if (!isLoggedIn()) {
      this.showLoginRequired()
      return
    }
    // 验证
    const name: string = this.formData.name.trim()
    const phone: string = this.formData.phone.trim()
    const address: string = this.formData.address.trim()
    if (name === '' || phone === '' || address === '') {
      promptAction.showToast({ message: '请完善姓名、手机号和地址', duration: 1500 })
      return
    }
    if (!/^1\d{10}$/.test(phone)) {
      promptAction.showToast({ message: '请输入正确的11位手机号', duration: 1800 })
      return
    }

    const isNewAddress: boolean = this.editingAddress === null
    const returnToMerchant: boolean = isNewAddress
      && (AppStorage.get<boolean>('merchantAddressSelectionMode') || false)
    const editingAddress: Address | null = this.editingAddress
    const submittedForm: AddressFormData = new AddressFormData()
    submittedForm.name = name
    submittedForm.phone = phone
    submittedForm.address = address
    submittedForm.detail = this.formData.detail.trim()
    submittedForm.latitude = this.formData.latitude
    submittedForm.longitude = this.formData.longitude
    submittedForm.tag = this.formData.tag
    submittedForm.isDefault = this.formData.isDefault
    this.saving = true
    try {
      if (editingAddress === null) {
        const ok: boolean = await addAddressRemote(name, phone, this.getFormAddressDetail(),
          submittedForm.isDefault, submittedForm.latitude, submittedForm.longitude,
          address, submittedForm.detail, submittedForm.tag)
        if (!ok) {
          this.showOperationFailure('新增地址', getLastRemoteErrorMessage())
          return
        }
      } else {
        const ok: boolean = await updateAddressRemote(editingAddress.id, name, phone,
          this.getFormAddressDetail(), submittedForm.isDefault, submittedForm.latitude, submittedForm.longitude,
          address, submittedForm.detail, submittedForm.tag)
        if (!ok) {
          this.showOperationFailure('更新地址', getLastRemoteErrorMessage())
          return
        }
      }

      this.formData = submittedForm
      if (editingAddress !== null) {
        // 直接将本次提交的表单值写回本地列表，避免服务端查询延迟导致 UI 仍显示旧内容。
        this.applyEditedAddress()
      } else {
        const syncedAddresses: Address[] = AppStorage.get<Address[]>('addressList') || this.addressList
        this.applyAddressList(syncedAddresses)
      }
      this.showAddForm = false
      if (returnToMerchant) {
        const savedText: string = this.getFormAddressDetail()
        const selectedAddress: Address | undefined = this.addressList.find((item: Address) =>
          item.name === name && item.phone === phone && this.getDisplayAddress(item) === savedText)
        if (selectedAddress !== undefined) {
          AppStorage.setOrCreate<Address>('currentAddress', selectedAddress)
          AppStorage.setOrCreate<boolean>('addressSelectionMode', false)
          promptAction.showToast({ message: '地址已保存，已返回店铺表单', duration: 1400 })
          router.back()
          return
        }
      }
      promptAction.showToast({ message: isNewAddress ? '地址新增成功' : '地址更新成功', duration: 1200 })
    } finally {
      this.saving = false
    }
  }
}
