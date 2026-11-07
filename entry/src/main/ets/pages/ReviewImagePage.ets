import { PageHeader } from '../components/PageHeader'
/**
 * 评价图片全屏预览页。
 * 评价列表缩略图点击后进入本页查看大图；点击任意位置返回。
 * 图片地址通过 AppStorage('reviewPreviewUrl') 传递（与项目内 currentOrderId 等跨页传参方式一致）。
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, FONT_SIZE, SPACING } from '../common/Constants'

@Entry
@Component
export struct ReviewImagePage {
  pageTransition() {
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Push))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Push))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionEnter(AppMotion.pageEnter(RouteType.Pop))
      .translate({ x: -AppMotion.distance(AppMotion.RETURN_OFFSET) })
      .opacity(0)
    PageTransitionExit(AppMotion.pageExit(RouteType.Pop))
      .translate({ x: AppMotion.distance(AppMotion.PAGE_OFFSET) })
      .opacity(0)
  }

  @StorageLink('reviewPreviewUrl') imageUrl: string = ''
  @State imageFailed: boolean = false

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
    Column() {
      PageHeader({ title: '评价图片', onBack: () => { this.close() } })
      Stack({ alignContent: Alignment.Center }) {
        if (this.imageUrl !== '') {
          Image(this.imageUrl)
            .width('100%').height('100%')
            .objectFit(ImageFit.Contain)
            .id('review-image-preview')
            .accessibilityText('评价原图')
            .onError(() => { this.imageFailed = true })
            .onComplete(() => { this.imageFailed = false })
        }
        if (this.imageFailed) {
          Text('图片暂时无法加载')
            .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_SECONDARY)
            .padding(SPACING.XL).id('review-image-error')
        }
      }.width('100%').layoutWeight(1)
      Text('点击任意位置返回')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
        .padding({ top: SPACING.MD, bottom: SPACING.XL })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
    .id('review-image-page')
    .onClick(() => { this.close() })
  }
}
