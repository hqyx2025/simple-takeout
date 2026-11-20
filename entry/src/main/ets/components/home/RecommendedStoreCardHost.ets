import { AppCardStyle, AppTheme } from '../../common/theme/AppTheme'
/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { StoreItem } from '../../model/Models'
import { storeRatingText } from '../../common/StorePresentation'

import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, merchantImageSource } from '../../common/Constants'

import { RatingStars } from '../../components/RatingStars'

import { HomeTheme } from '../../common/theme/HomeTheme'

@Component
export struct RecommendedStoreCardHost {
  @Prop store: StoreItem = {
    id: 0, name: '', image: '', rating: 0, monthlySales: 0, deliveryFee: 0, minOrder: 0,
    deliveryTime: '', distance: '', tags: [], notice: '', categoryId: 0, ownerId: 0
  }
  @Prop deliveryText: string = ''
  onStoreClick: (store: StoreItem) => void = () => {}

  build() {
    Row({ space: SPACING.MD }) {
      Image((this.store.image ?? '').trim() === '' ? HomeTheme.STORE_PLACEHOLDER : merchantImageSource(this.store.image))
        .alt(HomeTheme.STORE_PLACEHOLDER).width(82).height(82).objectFit(ImageFit.Cover)
        .borderRadius(BORDER_RADIUS.MD)
      Column({ space: SPACING.XS }) {
        Text(this.store.name).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          if ((this.store.ratingCount ?? 0) > 0) {
            RatingStars({ rating: this.store.rating, fontSize: FONT_SIZE.SM, showNumber: false })
          }
          Text(storeRatingText(this.store.rating, this.store.ratingCount ?? 0)).fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.TEXT_SECONDARY).margin({ left: (this.store.ratingCount ?? 0) > 0 ? SPACING.XS : 0 })
        }.width('100%')
        Text(this.deliveryText)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .attributeModifier(new AppCardStyle())
    .border({ width: 1, color: AppTheme.BORDER })
    .id('home-recommend-card-' + this.store.id.toString())
    .width('100%').padding(SPACING.MD).onClick(() => { this.onStoreClick(this.store) })
  }
}
