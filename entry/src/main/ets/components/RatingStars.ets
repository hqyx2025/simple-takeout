/**
 * 评分星星组件
 * 用★符号显示评分
 */
import { COLORS, FONT_SIZE } from '../common/Constants'

@Component
export struct RatingStars {
  rating: number = 5
  maxRating: number = 5
  fontSize: number = FONT_SIZE.MD
  showNumber: boolean = true

  build() {
    Row({ space: 2 }) {
      Text(this.getStars())
        .fontSize(this.fontSize)
        .fontColor(COLORS.PRIMARY)
      if (this.showNumber) {
        Text(this.rating.toFixed(1))
          .fontSize(this.fontSize)
          .fontColor(COLORS.PRIMARY)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 4 })
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  getStars(): string {
    let stars: string = ''
    const fullStars: number = Math.floor(this.rating)
    const hasHalf: boolean = this.rating - fullStars >= 0.5
    for (let i = 0; i < fullStars; i++) {
      stars += '★'
    }
    if (hasHalf && fullStars < this.maxRating) {
      stars += '☆'
    }
    const emptyStars: number = this.maxRating - fullStars - (hasHalf ? 1 : 0)
    for (let i = 0; i < emptyStars; i++) {
      stars += '☆'
    }
    return stars
  }
}
