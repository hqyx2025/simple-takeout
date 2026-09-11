/**
 * 评价图片全屏预览页。
 * 评价列表缩略图点击后进入本页查看大图；点击任意位置返回。
 * 图片地址通过 AppStorage('reviewPreviewUrl') 传递（与项目内 currentOrderId 等跨页传参方式一致）。
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, FONT_SIZE, SPACING } from '../common/Constants'

@Entry
@Component
export struct ReviewImagePage {
  @StorageLink('reviewPreviewUrl') imageUrl: string = ''

  aboutToAppear(): void {
    if (this.imageUrl === '') {
      promptAction.showToast({ message: '图片地址为空，无法预览', duration: 2000 })
      router.back()
    }
  }

  private close(): void {
    AppStorage.setOrCreate<string>('reviewPreviewUrl', '')
    router.back()
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 黑色遮罩背景：全屏预览时点任意位置返回
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')

      if (this.imageUrl !== '') {
        Image(this.imageUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      }

      Text('点击任意位置返回')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ bottom: SPACING.XL })
        .align(Alignment.Bottom)
    }
    .width('100%')
    .height('100%')
    .onClick(() => { this.close() })
  }
}
