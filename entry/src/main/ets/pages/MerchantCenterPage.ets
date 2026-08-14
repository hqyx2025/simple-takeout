/**
 * 商户中心页面
 * 商户可查看自己的店铺列表、管理店铺、上架食物
 */
import { StoreItem, GoodsItem, UserRole, User } from '../model/Models'
import { fetchMerchantStoresApi, fetchMerchantGoodsApi, createMerchantStoreApi, updateMerchantStoreApi,
  createMerchantGoodsApi, updateMerchantGoodsApi, deleteMerchantGoodsApi } from '../service/ApiService'
import { formatSales } from '../service/MockDataService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { promptCompat as promptAction } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'
import { routerCompat as router } from '../common/UiNavigation'

@Entry
@Component
export struct MerchantCenterPage {
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State myStores: StoreItem[] = []
  @State showAddStore: boolean = false
  @State showAddGoods: boolean = false
  @State selectedStoreId: number = 0
  @State selectedStoreGoods: GoodsItem[] = []
  @State storeGoodsCounts: Record<string, number> = {}

  // 新增店铺表单
  @State newStoreName: string = ''
  @State newStoreNotice: string = ''
  @State newStoreDeliveryFee: string = '3'
  @State newStoreMinOrder: string = '20'

  // 新增商品表单
  @State newGoodsName: string = ''
  @State newGoodsDesc: string = ''
  @State newGoodsPrice: string = ''
  @State newGoodsCategory: string = '1'

  // 编辑店铺表单
  @State showEditStore: boolean = false
  @State editStoreName: string = ''
  @State editStoreNotice: string = ''
  @State editStoreDeliveryFee: string = ''
  @State editStoreMinOrder: string = ''
  @State editingStoreId: number = 0

  // 编辑商品表单
  @State showEditGoods: boolean = false
  @State editingGoodsId: number = 0
  @State editGoodsName: string = ''
  @State editGoodsDesc: string = ''
  @State editGoodsPrice: string = ''

  aboutToAppear() {
    logInfo('Page', '进入商户中心页 MerchantCenterPage')
    this.refreshStores()
  }

  async refreshStores() {
    this.myStores = await fetchMerchantStoresApi()
    const counts: Record<string, number> = {}
    for (const store of this.myStores) {
      const goods: GoodsItem[] = await fetchMerchantGoodsApi(store.id)
      counts[store.id.toString()] = goods.length
    }
    this.storeGoodsCounts = counts
  }

  build() {
    Stack() {
      Column() {
        // 顶部
        Row() {
          Text('‹')
            .fontSize(FONT_SIZE.XXL)
            .fontColor(COLORS.TEXT_PRIMARY)
            .onClick(() => { router.back() })
          Text('🏪 商户中心')
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .margin({ left: SPACING.MD })
          Text(this.user.username)
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.LG, right: SPACING.LG, top: 40 })
        .backgroundColor(COLORS.BG_WHITE)

        // 统计概览
        Row() {
          Column({ space: 4 }) {
            Text(this.myStores.length.toString())
              .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
            Text('我的店铺')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
          Column({ space: 4 }) {
            Text(this.user.balance.toFixed(2))
              .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
            Text('账户余额')
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding(SPACING.LG)
        .margin({ top: SPACING.SM })
        .backgroundColor(COLORS.BG_WHITE)
        .borderRadius(BORDER_RADIUS.LG)

        // 新建店铺按钮
        Button('+ 新建店铺')
          .width('90%')
          .height(44)
          .fontSize(FONT_SIZE.MD)
          .fontColor(Color.White)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .margin({ top: SPACING.LG })
          .onClick(() => {
            this.showAddStore = true
            this.showAddGoods = false
          })

        // 店铺列表
        Text('我的店铺')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .width('100%')
          .padding({ left: SPACING.LG, top: SPACING.LG, bottom: SPACING.SM })

        List({ space: SPACING.SM }) {
          ForEach(this.myStores, (store: StoreItem) => {
            ListItem() {
              Row({ space: SPACING.MD }) {
                Column() {
                  Text(store.name.substring(0, 1))
                    .fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
                }
                .width(60).height(60)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.MD)
                .justifyContent(FlexAlign.Center)

                Column({ space: 4 }) {
                  Text(store.name)
                    .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
                    .fontColor(COLORS.TEXT_PRIMARY)
                  Row({ space: 8 }) {
                    Text(`月售${formatSales(store.monthlySales)}`)
                      .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                    Text(`配送费¥${store.deliveryFee}`)
                      .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
                  }
                Text(`${this.storeGoodsCounts[store.id.toString()] || 0}种商品`)
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Blank()
                Text('编辑').fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => { this.startEditStore(store) })
                Text('管理 ›')
                  .fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
              }
              .width('100%')
              .padding(SPACING.MD)
              .backgroundColor(COLORS.BG_WHITE)
              .borderRadius(BORDER_RADIUS.LG)
              .onClick(async () => {
                this.selectedStoreId = store.id
                this.selectedStoreGoods = await fetchMerchantGoodsApi(store.id)
                this.storeGoodsCounts[store.id.toString()] = this.selectedStoreGoods.length
                this.showAddGoods = false
                this.showAddStore = false
              })
            }
          }, (item: StoreItem) => item.id.toString())
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .layoutWeight(1)
        .divider({ strokeWidth: 0 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      // 新建店铺弹窗
      if (this.showAddStore) {
        Column() {
          Column({ space: SPACING.MD }) {
            Text('新建店铺')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Text('创建后将自动归入您的名下，店铺名称为必填项')
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
            Column({ space: SPACING.XS }) {
              Text('店铺名称（必填）')
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              TextInput({ placeholder: '请输入店铺名称，如：老王快餐店', text: this.newStoreName })
                .width('100%').height(44).onChange((v: string) => { this.newStoreName = v })
            }
            Column({ space: SPACING.XS }) {
              Text('店铺公告（选填，将展示在店铺详情页）')
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              TextInput({ placeholder: '请输入店铺公告，如：新店开业，欢迎光临', text: this.newStoreNotice })
                .width('100%').height(44).onChange((v: string) => { this.newStoreNotice = v })
            }
            Row({ space: SPACING.MD }) {
              Column({ space: SPACING.XS }) {
                Text('配送费（元）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '如：3', text: this.newStoreDeliveryFee })
                  .layoutWeight(1).height(44).type(InputType.Number)
                  .onChange((v: string) => { this.newStoreDeliveryFee = v })
              }
              .layoutWeight(1)
              Column({ space: SPACING.XS }) {
                Text('起送价（元）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '如：20', text: this.newStoreMinOrder })
                  .layoutWeight(1).height(44).type(InputType.Number)
                  .onChange((v: string) => { this.newStoreMinOrder = v })
              }
              .layoutWeight(1)
            }
            Row({ space: SPACING.MD }) {
              Button('取消')
                .layoutWeight(1).height(44).fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY).backgroundColor('#F5F5F5')
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .onClick(() => { this.showAddStore = false })
              Button('创建')
                .layoutWeight(1).height(44).fontSize(FONT_SIZE.MD)
                .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .onClick(() => { this.doCreateStore() })
            }
          }
          .width('90%')
          .padding(SPACING.XL)
          .backgroundColor(Color.White)
          .borderRadius(BORDER_RADIUS.XL)
        }
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 编辑店铺弹窗
      if (this.showEditStore) {
        Column() {
          Column({ space: SPACING.MD }) {
            Text('编辑店铺')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Text('修改后用户端店铺信息将同步更新，店铺名称为必填项')
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
            Column({ space: SPACING.XS }) {
              Text('店铺名称（必填）')
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              TextInput({ placeholder: '请输入店铺名称，如：老王快餐店', text: this.editStoreName })
                .width('100%').height(44).onChange((v: string) => { this.editStoreName = v })
            }
            Column({ space: SPACING.XS }) {
              Text('店铺公告（选填，将展示在店铺详情页）')
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              TextInput({ placeholder: '请输入店铺公告，如：本店支持免配送费', text: this.editStoreNotice })
                .width('100%').height(44).onChange((v: string) => { this.editStoreNotice = v })
            }
            Row({ space: SPACING.MD }) {
              Column({ space: SPACING.XS }) {
                Text('配送费（元）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '如：3', text: this.editStoreDeliveryFee })
                  .layoutWeight(1).height(44).type(InputType.Number)
                  .onChange((v: string) => { this.editStoreDeliveryFee = v })
              }
              .layoutWeight(1)
              Column({ space: SPACING.XS }) {
                Text('起送价（元）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '如：20', text: this.editStoreMinOrder })
                  .layoutWeight(1).height(44).type(InputType.Number)
                  .onChange((v: string) => { this.editStoreMinOrder = v })
              }
              .layoutWeight(1)
            }
            Row({ space: SPACING.MD }) {
              Button('取消')
                .layoutWeight(1).height(44).fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY).backgroundColor('#F5F5F5')
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .onClick(() => { this.showEditStore = false })
              Button('保存')
                .layoutWeight(1).height(44).fontSize(FONT_SIZE.MD)
                .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .onClick(() => { this.doEditStore() })
            }
          }
          .width('90%')
          .padding(SPACING.XL)
          .backgroundColor(Color.White)
          .borderRadius(BORDER_RADIUS.XL)
        }
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 商品管理面板（选中店铺后显示）
      if (this.selectedStoreId > 0 && !this.showAddStore) {
        Column() {
          Row() {
            Text('‹ 返回')
              .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
              .onClick(() => { this.selectedStoreId = 0 })
            Text('商品管理')
              .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
              .layoutWeight(1).textAlign(TextAlign.Center)
            Button('+ 添加商品')
              .height(32).fontSize(FONT_SIZE.SM).fontColor(Color.White)
              .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.ROUND)
              .type(ButtonType.Capsule)
              .onClick(() => { this.showAddGoods = true; this.showEditGoods = false })
          }
          .width('100%').height(50)
          .padding({ left: SPACING.LG, right: SPACING.LG })
          .backgroundColor(COLORS.BG_WHITE)

          // 添加商品表单
          if (this.showAddGoods) {
            Column({ space: SPACING.SM }) {
              Text('添加新商品').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              Text('商品名称与价格为必填项，保存后商品将在用户端上架展示')
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
              Column({ space: SPACING.XS }) {
                Text('商品名称（必填）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '请输入商品名称，如：宫保鸡丁', text: this.newGoodsName })
                  .width('100%').height(40).onChange((v: string) => { this.newGoodsName = v })
              }
              Column({ space: SPACING.XS }) {
                Text('商品描述（选填）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '请输入商品描述，如：招牌菜，微辣', text: this.newGoodsDesc })
                  .width('100%').height(40).onChange((v: string) => { this.newGoodsDesc = v })
              }
              Row({ space: SPACING.SM }) {
                Column({ space: SPACING.XS }) {
                  Text('价格（必填）')
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  TextInput({ placeholder: '如：25.00', text: this.newGoodsPrice })
                    .layoutWeight(1).height(40).type(InputType.Number)
                    .onChange((v: string) => { this.newGoodsPrice = v })
                }
                .layoutWeight(1)
                Column({ space: SPACING.XS }) {
                  Text('分类（选填，默认1）')
                    .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                  TextInput({ placeholder: '如：1', text: this.newGoodsCategory })
                    .layoutWeight(1).height(40).type(InputType.Number)
                    .onChange((v: string) => { this.newGoodsCategory = v })
                }
                .layoutWeight(1)
              }
              Text('分类对照：1热销菜 2快餐 3饮品 4甜品 5火锅 6烧烤 7面食')
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')
              Row({ space: SPACING.SM }) {
                Button('取消').layoutWeight(1).height(36).fontSize(FONT_SIZE.SM)
                  .fontColor(COLORS.TEXT_SECONDARY).backgroundColor('#F5F5F5')
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.showAddGoods = false })
                Button('添加').layoutWeight(1).height(36).fontSize(FONT_SIZE.SM)
                  .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.doAddGoods() })
              }
            }
            .width('100%')
            .padding(SPACING.MD)
            .margin({ top: SPACING.SM })
            .backgroundColor('#FFF8F0')
            .borderRadius(BORDER_RADIUS.LG)
          }

          // 编辑商品表单
          if (this.showEditGoods) {
            Column({ space: SPACING.SM }) {
              Text('编辑商品').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              Text('商品名称为必填项，保存后用户端将同步更新')
                .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
              Column({ space: SPACING.XS }) {
                Text('商品名称（必填）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '请输入商品名称，如：宫保鸡丁', text: this.editGoodsName })
                  .width('100%').height(40).onChange((v: string) => { this.editGoodsName = v })
              }
              Column({ space: SPACING.XS }) {
                Text('商品描述（选填）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '请输入商品描述，如：招牌菜，微辣', text: this.editGoodsDesc })
                  .width('100%').height(40).onChange((v: string) => { this.editGoodsDesc = v })
              }
              Column({ space: SPACING.XS }) {
                Text('价格（必填）')
                  .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                TextInput({ placeholder: '如：25.00', text: this.editGoodsPrice })
                  .width('100%').height(40).type(InputType.Number)
                  .onChange((v: string) => { this.editGoodsPrice = v })
              }
              Row({ space: SPACING.SM }) {
                Button('取消').layoutWeight(1).height(36).fontSize(FONT_SIZE.SM)
                  .fontColor(COLORS.TEXT_SECONDARY).backgroundColor('#F5F5F5')
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.showEditGoods = false })
                Button('保存').layoutWeight(1).height(36).fontSize(FONT_SIZE.SM)
                  .fontColor(Color.White).backgroundColor(COLORS.PRIMARY)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.doEditGoods() })
              }
            }
            .width('100%')
            .padding(SPACING.MD)
            .margin({ top: SPACING.SM })
            .backgroundColor('#FFF8F0')
            .borderRadius(BORDER_RADIUS.LG)
          }

          // 商品列表
          List({ space: SPACING.SM }) {
            ForEach(this.selectedStoreGoods, (goods: GoodsItem) => {
              ListItem() {
                Row({ space: SPACING.MD }) {
                  Column({ space: 4 }) {
                    Text(goods.name)
                      .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                    Text(goods.description)
                      .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Column({ space: 4 }) {
                    Text(`¥${goods.price}`)
                      .fontSize(FONT_SIZE.LG).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
                    Row({ space: SPACING.XS }) {
                      Button('删除')
                        .height(28).fontSize(FONT_SIZE.XS).fontColor(COLORS.ERROR)
                        .backgroundColor('#FFF0F0').borderRadius(BORDER_RADIUS.ROUND)
                        .type(ButtonType.Capsule)
                        .onClick(async () => {
                            const deleted: boolean = await deleteMerchantGoodsApi(goods.id)
                            if (deleted) {
                              this.selectedStoreGoods = await fetchMerchantGoodsApi(this.selectedStoreId)
                              this.storeGoodsCounts[this.selectedStoreId.toString()] = this.selectedStoreGoods.length
                            } else {
                              promptAction.showToast({ message: '删除失败，请稍后重试' })
                            }
                        })
                      Button('编辑')
                        .height(28).fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
                        .backgroundColor(COLORS.TAG_BG).borderRadius(BORDER_RADIUS.ROUND)
                        .type(ButtonType.Capsule)
                        .onClick(() => { this.startEditGoods(goods) })
                      if (goods.isOnShelf === false) {
                        Button('上架')
                          .height(28).fontSize(FONT_SIZE.XS).fontColor(COLORS.SUCCESS)
                          .backgroundColor('#E8F5E9').borderRadius(BORDER_RADIUS.ROUND)
                          .type(ButtonType.Capsule)
                          .onClick(() => { this.toggleGoodsShelf(goods, true) })
                      } else {
                        Button('下架')
                          .height(28).fontSize(FONT_SIZE.XS).fontColor(COLORS.WARNING)
                          .backgroundColor('#FFF3E0').borderRadius(BORDER_RADIUS.ROUND)
                          .type(ButtonType.Capsule)
                          .onClick(() => { this.toggleGoodsShelf(goods, false) })
                      }
                    }
                  }
                }
                .width('100%')
                .padding(SPACING.MD)
                .backgroundColor(COLORS.BG_WHITE)
                .borderRadius(BORDER_RADIUS.LG)
              }
            }, (item: GoodsItem) => item.id.toString())
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM })
          .layoutWeight(1)
          .divider({ strokeWidth: 0 })

          if (this.selectedStoreGoods.length === 0) {
            Column() {
              Text('📭').fontSize(50).margin({ top: 40 })
              Text('暂无商品')
                .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: 8 })
              Text('点击上方"添加商品"开始上架')
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).margin({ top: 4 })
            }
            .width('100%').layoutWeight(1)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%').height('100%')
        .backgroundColor(COLORS.BG_PRIMARY)
      }
    }
    .width('100%').height('100%')
  }

  async doCreateStore() {
    if (this.newStoreName === '') {
      return
    }
    const fee = Number(this.newStoreDeliveryFee) || 3
    const minOrder = Number(this.newStoreMinOrder) || 20
    const created: StoreItem | null = await createMerchantStoreApi(this.newStoreName, 1, fee, minOrder, '30分钟', this.newStoreNotice || '欢迎光临')
    if (created === null) {
      promptAction.showToast({ message: '创建失败，请检查网络或登录状态' })
      return
    }
    this.newStoreName = ''
    this.newStoreNotice = ''
    this.showAddStore = false
    this.refreshStores()
  }

  async doAddGoods() {
    if (this.newGoodsName === '' || this.newGoodsPrice === '') {
      return
    }
    const price = Number(this.newGoodsPrice) || 0
    const categoryId = Number(this.newGoodsCategory) || 1
    const goods: GoodsItem = {
      id: 0,
      name: this.newGoodsName,
      description: this.newGoodsDesc || '美味可口',
      price: price,
      image: '',
      categoryId: categoryId,
      sales: 0,
      rating: 5.0,
      tag: '新品',
    }
    const created: GoodsItem | null = await createMerchantGoodsApi(this.selectedStoreId, goods)
    if (created === null) {
      promptAction.showToast({ message: '商品创建失败，请稍后重试' })
      return
    }
    this.newGoodsName = ''
    this.newGoodsDesc = ''
    this.newGoodsPrice = ''
    this.showAddGoods = false
    this.selectedStoreGoods = await fetchMerchantGoodsApi(this.selectedStoreId)
    this.storeGoodsCounts[this.selectedStoreId.toString()] = this.selectedStoreGoods.length
  }

  startEditStore(store: StoreItem) {
    this.editingStoreId = store.id
    this.editStoreName = store.name
    this.editStoreNotice = store.notice
    this.editStoreDeliveryFee = store.deliveryFee.toString()
    this.editStoreMinOrder = store.minOrder.toString()
    this.showEditStore = true
  }

  async doEditStore() {
    if (this.editStoreName === '') {
      promptAction.showToast({ message: '店铺名称不能为空' })
      return
    }
    const originalStore = this.myStores.find(s => s.id === this.editingStoreId)
    if (originalStore === undefined || originalStore === null) {
      return
    }
    const fee = Number(this.editStoreDeliveryFee) || 0
    const minOrder = Number(this.editStoreMinOrder) || 0
    const updated: StoreItem | null = await updateMerchantStoreApi(originalStore.id, this.editStoreName, fee, minOrder, originalStore.deliveryTime, this.editStoreNotice || '欢迎光临')
    if (updated === null) {
      promptAction.showToast({ message: '保存失败，请稍后重试' })
      return
    }
    this.refreshStores()
    this.showEditStore = false
    promptAction.showToast({ message: '保存成功' })
  }

  startEditGoods(goods: GoodsItem) {
    this.editingGoodsId = goods.id
    this.editGoodsName = goods.name
    this.editGoodsDesc = goods.description
    this.editGoodsPrice = goods.price.toString()
    this.showAddGoods = false
    this.showEditGoods = true
  }

  async doEditGoods() {
    if (this.editGoodsName === '') {
      promptAction.showToast({ message: '商品名称不能为空' })
      return
    }
    const originalGoods = this.selectedStoreGoods.find(g => g.id === this.editingGoodsId)
    if (originalGoods === undefined || originalGoods === null) {
      return
    }
    const price = Number(this.editGoodsPrice) || 0
    const updatedGoods: GoodsItem = {
      id: originalGoods.id,
      name: this.editGoodsName,
      description: this.editGoodsDesc || '美味可口',
      price: price,
      originalPrice: originalGoods.originalPrice,
      image: originalGoods.image,
      categoryId: originalGoods.categoryId,
      sales: originalGoods.sales,
      rating: originalGoods.rating,
      tag: originalGoods.tag,
      isOnShelf: originalGoods.isOnShelf,
    }
    const updated: GoodsItem | null = await updateMerchantGoodsApi(updatedGoods, updatedGoods.isOnShelf !== false)
    if (updated === null) {
      promptAction.showToast({ message: '保存失败，请稍后重试' })
      return
    }
    this.showEditGoods = false
    this.selectedStoreGoods = await fetchMerchantGoodsApi(this.selectedStoreId)
    this.storeGoodsCounts[this.selectedStoreId.toString()] = this.selectedStoreGoods.length
    promptAction.showToast({ message: '保存成功' })
  }

  async toggleGoodsShelf(goods: GoodsItem, onShelf: boolean) {
    const updatedGoods: GoodsItem = {
      id: goods.id,
      name: goods.name,
      description: goods.description,
      price: goods.price,
      originalPrice: goods.originalPrice,
      image: goods.image,
      categoryId: goods.categoryId,
      sales: goods.sales,
      rating: goods.rating,
      tag: goods.tag,
      isOnShelf: onShelf,
    }
    const updated: GoodsItem | null = await updateMerchantGoodsApi(updatedGoods, onShelf)
    if (updated === null) {
      promptAction.showToast({ message: '上下架操作失败，请稍后重试' })
      return
    }
    this.selectedStoreGoods = await fetchMerchantGoodsApi(this.selectedStoreId)
    this.storeGoodsCounts[this.selectedStoreId.toString()] = this.selectedStoreGoods.length
    promptAction.showToast({ message: onShelf ? '已上架' : '已下架' })
  }
}
