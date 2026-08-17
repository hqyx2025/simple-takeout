/**
 * 地址管理页面
 * 支持地址的增删改查与设置默认地址
 */
import { Address } from '../model/Models'
import { addAddressRemote, deleteAddressRemote, updateAddressRemote, setDefaultAddressRemote, syncAddressesRemote, deduplicateAddresses, isLoggedIn, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { common } from '@kit.AbilityKit'
import { GeoPosition, getCurrentPosition, reverseGeocodePosition } from '../service/LocationService'

// 表单数据类（用于避免无类型对象字面量）
class AddressFormData {
  name: string = ''
  phone: string = ''
  address: string = ''
  detail: string = ''
  tag: string = '学校'
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
    // 服务端将地址和详细地址保存为一个 detail 字段，编辑时把完整原文回填到地址输入框，
    // 避免再次保存时重复拼接。
    if (addressText === '') {
      form.address = detailText
      form.detail = ''
    } else {
      form.address = addressText
      form.detail = detailText
    }
    form.tag = addr.tag || '学校'
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
  @StorageLink('addressList') addressList: Address[] = []
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State addressListRevision: number = 0
  @State showAddForm: boolean = false
  @State editingAddress: Address | null = null
  @State formData: AddressFormData = new AddressFormData()
  @State locatingCurrent: boolean = false

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
        Row() {
          Text('‹')
            .fontSize(FONT_SIZE.XXL)
            .fontColor(COLORS.TEXT_PRIMARY)
            .onClick(() => { this.onBack() })
          Text('收货地址')
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          // 占位以保持标题居中
          Text('‹')
            .fontSize(FONT_SIZE.XXL)
            .fontColor(Color.Transparent)
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(COLORS.BG_WHITE)

        // 地址列表 / 空状态
        if (this.addressList.length === 0) {
          Column({ space: SPACING.SM }) {
            Text('📭')
              .fontSize(60)
              .margin({ top: 80 })
            Text('暂无收货地址')
              .fontSize(FONT_SIZE.LG)
              .fontColor(COLORS.TEXT_HINT)
            Text('点击下方按钮添加收货地址')
              .fontSize(FONT_SIZE.MD)
              .fontColor(COLORS.TEXT_HINT)
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
                        .fontColor(Color.White)
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
                    Text('编辑')
                      .fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.PRIMARY)
                      .padding({ left: SPACING.SM, right: SPACING.SM })
                      .onClick(() => { this.openEditForm(addr) })
                    Text('删除')
                      .fontSize(FONT_SIZE.SM)
                      .fontColor(COLORS.ERROR)
                      .padding({ left: SPACING.SM, right: SPACING.SM })
                      .onClick(() => { this.deleteAddress(addr) })
                    if (!addr.isDefault) {
                      Text('设为默认')
                        .fontSize(FONT_SIZE.SM)
                        .fontColor(COLORS.TEXT_SECONDARY)
                        .padding({ left: SPACING.SM, right: SPACING.SM })
                        .onClick(() => { this.setDefault(addr) })
                    }
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(SPACING.LG)
                .backgroundColor(COLORS.BG_WHITE)
                .borderRadius(BORDER_RADIUS.LG)
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

        // 新增收货地址按钮
        Button('+ 新增收货地址')
          .width('90%')
          .height(48)
          .fontSize(FONT_SIZE.LG)
          .fontColor(Color.White)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .margin({ top: SPACING.MD, bottom: SPACING.SM })
          .onClick(() => { this.openAddForm() })

      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 新增/编辑表单弹窗
      if (this.showAddForm) {
        Column() {
          Column({ space: SPACING.MD }) {
            Text(this.editingAddress === null ? '新增地址' : '编辑地址')
              .fontSize(FONT_SIZE.XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .width('100%')
              .textAlign(TextAlign.Center)

            TextInput({ placeholder: '姓名', text: this.formData.name })
              .width('100%')
              .height(44)
              .onChange((v: string) => { this.formData.name = v })

            TextInput({ placeholder: '电话', text: this.formData.phone })
              .width('100%')
              .height(44)
              .type(InputType.PhoneNumber)
              .onChange((v: string) => { this.formData.phone = v })

            if (this.editingAddress === null) {
              Row() {
                Text('地址')
                  .fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.TEXT_SECONDARY)
                Blank()
                Text(this.locatingCurrent ? '正在定位...' : '📍 定位选择当前位置')
                  .fontSize(FONT_SIZE.SM)
                  .fontColor(this.locatingCurrent ? COLORS.TEXT_HINT : COLORS.PRIMARY)
                  .onClick(() => { this.fillCurrentLocation() })
              }
              .width('100%')
            }

            TextInput({ placeholder: '地址（如：北京市海淀区）', text: this.formData.address })
              .width('100%')
              .height(44)
              .onChange((v: string) => { this.formData.address = v })

            TextInput({ placeholder: '详细地址（如：XX路XX号）', text: this.formData.detail })
              .width('100%')
              .height(44)
              .onChange((v: string) => { this.formData.detail = v })

            // 标签选择
            Row() {
              Text('标签')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
              Blank()
              ForEach(AddressTag.ALL, (tag: string) => {
                Text(tag)
                  .fontSize(FONT_SIZE.SM)
                  .fontColor(this.formData.tag === tag ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
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

            // 按钮组
            Row({ space: SPACING.MD }) {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.showAddForm = false })
              Button('保存')
                .layoutWeight(1)
                .height(44)
                .fontSize(FONT_SIZE.MD)
                .fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.doSave() })
            }
            .width('100%')
          }
          .width('90%')
          .padding(SPACING.XL)
          .backgroundColor(Color.White)
          .borderRadius(BORDER_RADIUS.XL)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  // 打开新增表单
  openAddForm(): void {
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
      nextForm.detail = ''
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
    form.tag = tag
    form.isDefault = this.formData.isDefault
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
    const source: Address[] = AppStorage.get<Address[]>('addressList') || this.addressList
    const updated: Address[] = this.copyAddresses(source)
    const savedDetail: string = this.getFormAddressDetail()
    updated.forEach((item: Address) => {
      if (item.id === editingId) {
        item.name = this.formData.name.trim()
        item.phone = this.formData.phone.trim()
        item.address = savedDetail
        item.detail = ''
        item.tag = this.formData.tag
        item.isDefault = this.formData.isDefault
      } else if (this.formData.isDefault) {
        item.isDefault = false
      }
    })
    this.applyAddressList(updated)
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

    if (this.editingAddress === null) {
      // 新增
      const addr: Address = {
        id: 0,
        name: this.formData.name,
        phone: this.formData.phone,
        address: this.formData.address,
        detail: this.formData.detail,
        isDefault: this.formData.isDefault,
        tag: this.formData.tag
      }
      const ok: boolean = await addAddressRemote(this.formData.name, this.formData.phone,
        this.getFormAddressDetail(), this.formData.isDefault)
      if (!ok) {
        this.showOperationFailure('新增地址', getLastRemoteErrorMessage())
        return
      }
    } else {
      const ok: boolean = await updateAddressRemote(this.editingAddress.id, this.formData.name, this.formData.phone,
        this.getFormAddressDetail(), this.formData.isDefault)
      if (!ok) {
        this.showOperationFailure('更新地址', getLastRemoteErrorMessage())
        return
      }
    }

    if (this.editingAddress !== null) {
      // 直接将本次提交的表单值写回本地列表，避免服务端查询延迟导致 UI 仍显示旧内容。
      this.applyEditedAddress()
    } else {
      const syncedAddresses: Address[] = AppStorage.get<Address[]>('addressList') || this.addressList
      this.applyAddressList(syncedAddresses)
    }
    this.showAddForm = false
    promptAction.showToast({ message: this.editingAddress === null ? '地址新增成功' : '地址更新成功', duration: 1200 })
  }
}
