/**
 * 商户中心页面
 * 商户可查看自己的店铺列表、管理店铺、上架食物
 */
import { StoreItem, GoodsItem, UserRole, User } from '../model/Models'
import { getStoresByOwner, getGoodsForStore, addGoodsToStore, removeGoodsFromStore, createStore } from '../service/AppStorageManager'
import { formatSales } from '../service/MockDataService'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'

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

  aboutToAppear() {
    this.refreshStores()
  }

  refreshStores() {
    this.myStores = getStoresByOwner(this.user.id)
  }

  build() {
    Stack() {
      Column() {
        // 顶部
        Row() {
          Text('🏪 商户中心')
            .fontSize(FONT_SIZE.XXL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
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
                  Text(`${getGoodsForStore(store.id).length}种商品`)
                    .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Blank()
                Text('管理 ›')
                  .fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
              }
              .width('100%')
              .padding(SPACING.MD)
              .backgroundColor(COLORS.BG_WHITE)
              .borderRadius(BORDER_RADIUS.LG)
              .onClick(() => {
                this.selectedStoreId = store.id
                this.selectedStoreGoods = getGoodsForStore(store.id)
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
            TextInput({ placeholder: '店铺名称', text: this.newStoreName })
              .width('100%').height(44).onChange((v: string) => { this.newStoreName = v })
            TextInput({ placeholder: '店铺公告', text: this.newStoreNotice })
              .width('100%').height(44).onChange((v: string) => { this.newStoreNotice = v })
            Row({ space: SPACING.MD }) {
              TextInput({ placeholder: '配送费', text: this.newStoreDeliveryFee })
                .layoutWeight(1).height(44).type(InputType.Number)
                .onChange((v: string) => { this.newStoreDeliveryFee = v })
              TextInput({ placeholder: '起送价', text: this.newStoreMinOrder })
                .layoutWeight(1).height(44).type(InputType.Number)
                .onChange((v: string) => { this.newStoreMinOrder = v })
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
              .onClick(() => { this.showAddGoods = true })
          }
          .width('100%').height(50)
          .padding({ left: SPACING.LG, right: SPACING.LG })
          .backgroundColor(COLORS.BG_WHITE)

          // 添加商品表单
          if (this.showAddGoods) {
            Column({ space: SPACING.SM }) {
              Text('添加新商品').fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              TextInput({ placeholder: '商品名称', text: this.newGoodsName })
                .width('100%').height(40).onChange((v: string) => { this.newGoodsName = v })
              TextInput({ placeholder: '商品描述', text: this.newGoodsDesc })
                .width('100%').height(40).onChange((v: string) => { this.newGoodsDesc = v })
              Row({ space: SPACING.SM }) {
                TextInput({ placeholder: '价格', text: this.newGoodsPrice })
                  .layoutWeight(1).height(40).type(InputType.Number)
                  .onChange((v: string) => { this.newGoodsPrice = v })
                TextInput({ placeholder: '分类ID(1-8)', text: this.newGoodsCategory })
                  .layoutWeight(1).height(40).type(InputType.Number)
                  .onChange((v: string) => { this.newGoodsCategory = v })
              }
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
                    Button('删除')
                      .height(28).fontSize(FONT_SIZE.XS).fontColor(COLORS.ERROR)
                      .backgroundColor('#FFF0F0').borderRadius(BORDER_RADIUS.ROUND)
                      .type(ButtonType.Capsule)
                      .onClick(() => {
                        removeGoodsFromStore(this.selectedStoreId, goods.id)
                        this.selectedStoreGoods = getGoodsForStore(this.selectedStoreId)
                      })
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

  doCreateStore() {
    if (this.newStoreName === '') {
      return
    }
    const fee = Number(this.newStoreDeliveryFee) || 3
    const minOrder = Number(this.newStoreMinOrder) || 20
    const newStore: StoreItem = {
      id: 0,
      name: this.newStoreName,
      image: '',
      rating: 5.0,
      monthlySales: 0,
      deliveryFee: fee,
      minOrder: minOrder,
      deliveryTime: '30分钟',
      distance: '1.0km',
      tags: ['新店'],
      notice: this.newStoreNotice || '欢迎光临',
      categoryId: 1,
      ownerId: this.user.id,
    }
    createStore(newStore)
    this.newStoreName = ''
    this.newStoreNotice = ''
    this.showAddStore = false
    this.refreshStores()
  }

  doAddGoods() {
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
    addGoodsToStore(this.selectedStoreId, goods)
    this.newGoodsName = ''
    this.newGoodsDesc = ''
    this.newGoodsPrice = ''
    this.showAddGoods = false
    this.selectedStoreGoods = getGoodsForStore(this.selectedStoreId)
  }
}