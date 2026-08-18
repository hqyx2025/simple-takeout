/**
 * 商户中心页面
 * 商户可查看自己的店铺列表、管理店铺、上架食物
 */
import { StoreItem, GoodsItem, UserRole, User, Category } from '../model/Models'
import { fetchMerchantStoresApi, fetchMerchantGoodsApi, createMerchantStoreApi, updateMerchantStoreApi,
  updateMerchantGoodsApi, deleteMerchantGoodsApi,
  fetchMerchantCategoriesApi, createMerchantCategoryApi, updateMerchantCategoryApi, deleteMerchantCategoryApi } from '../service/ApiService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, formatSales } from '../common/Constants'
import { promptCompat as promptAction } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'
import { routerCompat as router } from '../common/UiNavigation'

@Entry
@Component
export struct MerchantCenterPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('user') user: User = {
    id: 0, username: '未登录', avatar: '', phone: '', password: '', role: UserRole.CUSTOMER,
    balance: 0, coupons: [], orders: [], storeIds: []
  }
  @State myStores: StoreItem[] = []
  @State showAddStore: boolean = false
  @State selectedStoreId: number = 0
  @State selectedStoreGoods: GoodsItem[] = []
  @State storeGoodsCounts: Record<string, number> = {}

  // 新增店铺表单
  @State newStoreName: string = ''
  @State newStoreNotice: string = ''
  @State newStoreDeliveryFee: string = '3'
  @State newStoreMinOrder: string = '20'

  // 商户分类管理（演进项，见大纲 8.3）
  @State merchantCategories: Category[] = []
  @State showManageCategories: boolean = false
  @State newCategoryName: string = ''
  @State editingCategoryId: number = 0
  @State editCategoryName: string = ''

  // 编辑店铺表单
  @State showEditStore: boolean = false
  @State editStoreName: string = ''
  @State editStoreNotice: string = ''
  @State editStoreDeliveryFee: string = ''
  @State editStoreMinOrder: string = ''
  @State editingStoreId: number = 0

  aboutToAppear() {
    logInfo('Page', '进入商户中心页 MerchantCenterPage')
    if (!this.loggedIn || this.user.role !== UserRole.MERCHANT) {
      promptAction.showToast({ message: '请使用商户账号登录后管理店铺', duration: 1800 })
      router.back()
      return
    }
    this.refreshStores()
    this.refreshCategories()
  }

  async refreshCategories() {
    this.merchantCategories = await fetchMerchantCategoriesApi()
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

  async onPageShow(): Promise<void> {
    if (!this.loggedIn || this.user.role !== UserRole.MERCHANT) {
      return
    }
    await this.refreshStores()
    await this.refreshSelectedStoreGoods()
  }

  private async refreshSelectedStoreGoods(): Promise<void> {
    if (this.selectedStoreId <= 0) {
      return
    }
    this.selectedStoreGoods = await fetchMerchantGoodsApi(this.selectedStoreId)
    this.storeGoodsCounts[this.selectedStoreId.toString()] = this.selectedStoreGoods.length
  }

  private openAddGoodsPage(): void {
    if (this.selectedStoreId <= 0) {
      promptAction.showToast({ message: '请先选择要管理的店铺', duration: 1800 })
      return
    }
    AppStorage.setOrCreate<number>('merchantGoodsStoreId', this.selectedStoreId)
    router.pushUrl({ url: 'pages/MerchantAddGoodsPage' })
  }

  private openEditGoodsPage(goods: GoodsItem): void {
    if (this.selectedStoreId <= 0 || goods.id <= 0) {
      promptAction.showToast({ message: '商品信息暂不可用，请刷新后重试', duration: 1800 })
      return
    }
    AppStorage.setOrCreate<number>('merchantGoodsStoreId', this.selectedStoreId)
    AppStorage.setOrCreate<number>('merchantEditGoodsId', goods.id)
    router.pushUrl({ url: 'pages/MerchantEditGoodsPage' })
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
          })

        // 我的店铺
        Row() {
          Text('我的店铺')
            .fontSize(FONT_SIZE.LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
          Text('分类管理')
            .fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.PRIMARY)
            .onClick(() => { this.showManageCategories = true })
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.LG, bottom: SPACING.SM })

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

      // 商户分类管理弹窗（演进项，见大纲 8.3）
      if (this.showManageCategories) {
        Column() {
          Column({ space: SPACING.MD }) {
            Row() {
              Text('分类管理')
                .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
              Text('✕')
                .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT)
                .onClick(() => { this.showManageCategories = false })
            }
            .width('100%')
            Text('店内分类用于用户端商品分组展示，创建后可在商品编辑中选择')
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT).width('100%')

            Row({ space: SPACING.SM }) {
              TextInput({ placeholder: '新分类名称', text: this.newCategoryName })
                .layoutWeight(1).height(40)
                .onChange((v: string) => { this.newCategoryName = v })
              Button('新增')
                .height(40).fontSize(FONT_SIZE.SM).fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY).borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.doAddCategory() })
            }
            .width('100%')

            Scroll() {
              Column({ space: SPACING.SM }) {
                if (this.merchantCategories.length === 0) {
                  Text('暂无分类，请先新增')
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
                }
                ForEach(this.merchantCategories, (category: Category) => {
                  Row({ space: SPACING.SM }) {
                    if (this.editingCategoryId === category.id) {
                      TextInput({ placeholder: '分类名称', text: this.editCategoryName })
                        .layoutWeight(1).height(36)
                        .onChange((v: string) => { this.editCategoryName = v })
                      Button('保存')
                        .height(30).fontSize(FONT_SIZE.XS).fontColor(Color.White)
                        .backgroundColor(COLORS.SUCCESS).borderRadius(BORDER_RADIUS.ROUND)
                        .type(ButtonType.Capsule)
                        .onClick(() => { this.doEditCategory(category) })
                      Button('取消')
                        .height(30).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_SECONDARY)
                        .backgroundColor('#F5F5F5').borderRadius(BORDER_RADIUS.ROUND)
                        .type(ButtonType.Capsule)
                        .onClick(() => { this.editingCategoryId = 0 })
                    } else {
                      Text(category.name)
                        .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
                      Text('改名')
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
                        .onClick(() => {
                          this.editingCategoryId = category.id
                          this.editCategoryName = category.name
                        })
                      Text('删除')
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.ERROR)
                        .onClick(() => { this.doDeleteCategory(category) })
                    }
                  }
                  .width('100%')
                  .padding(SPACING.SM)
                  .backgroundColor(COLORS.BG_PRIMARY)
                  .borderRadius(BORDER_RADIUS.MD)
                }, (category: Category) => category.id.toString())
              }
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          .width('90%')
          .height('70%')
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
              .onClick(() => { this.openAddGoodsPage() })
          }
          .width('100%').height(50)
          .padding({ left: SPACING.LG, right: SPACING.LG })
          .backgroundColor(COLORS.BG_WHITE)

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
                    if (goods.isSpecial === true) {
                      Text('特价团购')
                        .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRICE_RED)
                        .backgroundColor('#FFF0F0')
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(BORDER_RADIUS.ROUND)
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Column({ space: 4 }) {
                    Text(`¥${goods.price}`)
                      .fontSize(FONT_SIZE.LG).fontColor(COLORS.PRICE_RED).fontWeight(FontWeight.Bold)
                    Text(`库存 ${goods.stock ?? 999}`)
                      .fontSize(FONT_SIZE.XS).fontColor(goods.stock !== undefined && goods.stock === 0 ? COLORS.ERROR : COLORS.TEXT_HINT)
                    Row({ space: SPACING.XS }) {
                      Button('删除')
                        .height(28).fontSize(FONT_SIZE.XS).fontColor(COLORS.ERROR)
                        .backgroundColor('#FFF0F0').borderRadius(BORDER_RADIUS.ROUND)
                        .type(ButtonType.Capsule)
                        .onClick(async () => {
                            const deleted: boolean = await deleteMerchantGoodsApi(goods.id)
                            if (deleted) {
                              await this.refreshSelectedStoreGoods()
                              promptAction.showToast({ message: '商品已删除', duration: 1400 })
                            } else {
                              promptAction.showToast({ message: '删除失败，请稍后重试' })
                            }
                        })
                      Button('编辑')
                        .height(28).fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
                        .backgroundColor(COLORS.TAG_BG).borderRadius(BORDER_RADIUS.ROUND)
                        .type(ButtonType.Capsule)
                        .onClick(() => { this.openEditGoodsPage(goods) })
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
    await this.refreshStores()
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
    await this.refreshStores()
    this.showEditStore = false
    promptAction.showToast({ message: '保存成功' })
  }

  async toggleGoodsShelf(goods: GoodsItem, onShelf: boolean) {
    const updatedGoods: GoodsItem = {
      id: goods.id,
      name: goods.name,
      description: goods.description,
      price: goods.price,
      originalPrice: goods.originalPrice ?? goods.price,
      image: goods.image,
      categoryId: goods.categoryId,
      merchantCategoryId: goods.merchantCategoryId ?? 0,
      stock: goods.stock ?? 999,
      sales: goods.sales,
      rating: goods.rating,
      tag: goods.tag,
      isOnShelf: onShelf,
      isSpecial: goods.isSpecial === true,
    }
    const updated: GoodsItem | null = await updateMerchantGoodsApi(updatedGoods, onShelf)
    if (updated === null) {
      promptAction.showToast({ message: '上下架操作失败，请稍后重试' })
      return
    }
    await this.refreshSelectedStoreGoods()
    promptAction.showToast({ message: onShelf ? '已上架' : '已下架' })
  }

  // ============ 商户分类管理（演进项，见大纲 8.3） ============

  async doAddCategory() {
    if (this.newCategoryName.trim() === '') {
      promptAction.showToast({ message: '分类名称不能为空' })
      return
    }
    const created: Category | null = await createMerchantCategoryApi(this.newCategoryName.trim(), this.merchantCategories.length + 1)
    if (created === null) {
      return
    }
    this.newCategoryName = ''
    await this.refreshCategories()
    promptAction.showToast({ message: '分类创建成功' })
  }

  async doEditCategory(category: Category) {
    if (this.editCategoryName.trim() === '') {
      promptAction.showToast({ message: '分类名称不能为空' })
      return
    }
    const updated: Category | null = await updateMerchantCategoryApi(category.id, this.editCategoryName.trim(), category.sort ?? 0)
    if (updated === null) {
      return
    }
    this.editingCategoryId = 0
    await this.refreshCategories()
    promptAction.showToast({ message: '分类已更新' })
  }

  async doDeleteCategory(category: Category) {
    const deleted: boolean = await deleteMerchantCategoryApi(category.id)
    if (!deleted) {
      return
    }
    await this.refreshCategories()
    promptAction.showToast({ message: '分类已删除' })
  }
}
