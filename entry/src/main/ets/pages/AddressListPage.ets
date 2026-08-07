/**
 * 地址管理页面
 * 支持地址的增删改查与设置默认地址
 */
import { Address } from '../model/Models'
import { addAddress, deleteAddress } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import router from '@ohos.router'

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
    form.address = addr.address
    form.detail = addr.detail
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
  @State showAddForm: boolean = false
  @State editingAddress: Address | null = null
  @State formData: AddressFormData = new AddressFormData()

  onBack: () => void = () => { router.back() }
  onSelectAddress: (address: Address) => void = () => {}

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
                  Text(`${addr.address} ${addr.detail}`)
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
                      .onClick(() => { deleteAddress(addr.id) })
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
                })
              }
            }, (item: Address) => item.id.toString())
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

        // 定位选择位置入口
        Text('📍 定位选择当前位置')
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.PRIMARY)
          .width('90%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: SPACING.LG })
          .onClick(() => { router.pushUrl({ url: 'pages/LocationPage' }) })
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
    this.showAddForm = true
  }

  // 打开编辑表单
  openEditForm(addr: Address): void {
    this.editingAddress = addr
    this.formData = AddressFormData.fromAddress(addr)
    this.showAddForm = true
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

  // 设为默认地址
  setDefault(addr: Address): void {
    this.addressList.forEach(a => {
      a.isDefault = (a.id === addr.id)
    })
    AppStorage.setOrCreate('addressList', this.addressList)
  }

  // 保存地址
  doSave(): void {
    // 验证
    if (this.formData.name === '' || this.formData.phone === '' || this.formData.address === '') {
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
      addAddress(addr)
    } else {
      // 编辑 - 直接修改现有地址
      this.editingAddress.name = this.formData.name
      this.editingAddress.phone = this.formData.phone
      this.editingAddress.address = this.formData.address
      this.editingAddress.detail = this.formData.detail
      this.editingAddress.tag = this.formData.tag
      this.editingAddress.isDefault = this.formData.isDefault
      AppStorage.setOrCreate('addressList', this.addressList)
    }

    // 如果设为默认，取消其他默认
    if (this.formData.isDefault) {
      this.addressList.forEach(a => {
        if (a.id !== (this.editingAddress !== null ? this.editingAddress.id : 0)) {
          a.isDefault = false
        }
      })
      AppStorage.setOrCreate('addressList', this.addressList)
    }

    this.showAddForm = false
  }
}
