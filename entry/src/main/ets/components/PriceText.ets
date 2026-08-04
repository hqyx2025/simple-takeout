/**
 * 价格文本组件
 * 统一价格显示样式
 */
import { COLORS, FONT_SIZE } from '../common/Constants'

@Component
export struct PriceText {
  price: number = 0
  fontSize: number = FONT_SIZE.XL
  showSymbol: boolean = true

  build() {
    Row({ space: 2 }) {
      if (this.showSymbol) {
        Text('¥')
          .fontSize(this.fontSize - 4)
          .fontColor(COLORS.PRICE_RED)
          .fontWeight(FontWeight.Bold)
      }
      Text(this.price.toFixed(2))
        .fontSize(this.fontSize)
        .fontColor(COLORS.PRICE_RED)
        .fontWeight(FontWeight.Bold)
    }
    .alignItems(VerticalAlign.Bottom)
  }
}
