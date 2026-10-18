import { AppCardStyle, AppTheme } from '../../common/theme/AppTheme'
/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { StoreItem } from '../../model/Models'

import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, formatSales, merchantImageSource } from '../../common/Constants'

import { RatingStars } from '../../components/RatingStars'

import { HomeTheme } from '../../common/theme/HomeTheme'

@Component
export struct RecommendedStoreCardHost {
  @Prop store: StoreItem = {
    id: 0, name: '', image: '', rating: 0, monthlySales: 0, deliveryFee: 0, minOrder: 0,
    deliveryTime: '', distance: '', tags: [], notice: '', categoryId: 0, ownerId: 0
  }
  onStoreClick: (store: StoreItem) => void = () => {}

  /**
   * 距离文案：只有服务端用「用户定位 + 门店坐标」真算出来的距离才显示「距你 X」，
   * 门店没坐标或未定位时是「未知距离」——不能沿用历史值假装很近。
   */
  private distanceText(): string {
    const distance: string = this.store.distance ?? ''
    if (distance === '' || distance === '未知距离') {
      return '距离未知'
    }
    return `距你 ${distance}`
  }

  build() {
    Column({ space: SPACING.SM }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image((this.store.image ?? '').trim() === '' ? HomeTheme.STORE_PLACEHOLDER : merchantImageSource(this.store.image))
          .alt(HomeTheme.STORE_PLACEHOLDER)
          .width('100%').aspectRatio(HomeTheme.GRID_IMAGE_RATIO).objectFit(ImageFit.Cover)
          .borderRadius(BORDER_RADIUS.MD)
        Text('平台推荐').fontSize(FONT_SIZE.XS).fontColor(COLORS.PRIMARY)
          .backgroundColor(COLORS.TAG_BG).padding({ left: 5, right: 5, top: 2, bottom: 2 })
          .borderRadius(BORDER_RADIUS.ROUND).margin(SPACING.SM)
      }
      .width('100%')
      Column({ space: SPACING.XS }) {
        Text(this.store.name).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY).width('100%').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          RatingStars({ rating: this.store.rating, fontSize: FONT_SIZE.SM, showNumber: true })
          Text(`月售${formatSales(this.store.monthlySales)}`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).margin({ left: SPACING.SM })
        }
        .width('100%')
        Text(`${this.store.deliveryTime} · ${this.distanceText()}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`配送¥${this.store.deliveryFee} · ${this.store.minOrder}元起送`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.store.notice).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .attributeModifier(new AppCardStyle())
    .border({ width: 1, color: AppTheme.BORDER })
    .id(`home-recommend-card-${this.store.id}`)
    .width('100%').padding(SPACING.MD).onClick(() => { this.onStoreClick(this.store) })
  }
}

// ===================== 店铺详情 =====================
