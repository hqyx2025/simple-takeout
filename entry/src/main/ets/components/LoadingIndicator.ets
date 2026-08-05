/**
 * 加载中指示组件
 * 统一各页面加载态展示（旋转圆环 + 提示文案）
 */
import { COLORS, SPACING, FONT_SIZE } from '../common/Constants'

@Component
export struct LoadingIndicator {
  text: string = '加载中...'
  @State rotateAngle: number = 0
  private rotateTimer: number = -1

  aboutToAppear() {
    this.startRotate()
  }

  aboutToDisappear() {
    this.stopRotate()
  }

  // 启动旋转动画
  private startRotate(): void {
    this.stopRotate()
    this.rotateTimer = setInterval(() => {
      this.rotateAngle = (this.rotateAngle + 45) % 360
    }, 100)
  }

  private stopRotate(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer)
      this.rotateTimer = -1
    }
  }

  build() {
    Column({ space: SPACING.MD }) {
      Stack() {
        // 外圈
        Circle()
          .width(36)
          .height(36)
          .stroke(COLORS.DIVIDER)
          .strokeWidth(3)
          .fillOpacity(0)
        // 旋转的进度弧
        Circle()
          .width(36)
          .height(36)
          .stroke(COLORS.PRIMARY)
          .strokeWidth(3)
          .fillOpacity(0)
          .strokeDashArray([24, 999])
          .rotate({ angle: this.rotateAngle })
          .animation({ duration: 100, curve: Curve.Linear })
      }
      .width(40)
      .height(40)

      if (this.text !== '') {
        Text(this.text)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
