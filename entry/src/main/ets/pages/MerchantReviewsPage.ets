/**
 * 商户评价管理页
 * 查看本店收到的评价并回复
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Review } from '../model/Models'
import { syncMerchantReviewsRemote, replyReviewRemote } from '../service/AppStorageManager'
import { RatingStars } from '../components/RatingStars'
import { logInfo } from '../service/AppLogger'
import { PageHeader } from '../components/PageHeader'

@Entry
@Component
export struct MerchantReviewsPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State reviews: Review[] = []
  @State loading: boolean = false
  @State replyTarget: Review | null = null
  @State replyText: string = ''
  @State submitting: boolean = false

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入商户评价管理页 MerchantReviewsPage')
    if (this.loggedIn) {
      await this.loadReviews()
    }
  }

  private async loadReviews(): Promise<void> {
    this.loading = true
    this.reviews = await syncMerchantReviewsRemote()
    this.loading = false
  }

  private openReply(review: Review): void {
    this.replyTarget = review
    this.replyText = review.reply
  }

  private async submitReply(): Promise<void> {
    if (this.replyTarget === null) {
      return
    }
    if (this.submitting) {
      return
    }
    if (this.replyText.trim() === '') {
      promptAction.showToast({ message: '请输入回复内容', duration: 1500 })
      return
    }
    this.submitting = true
    const ok: boolean = await replyReviewRemote(this.replyTarget.id, this.replyText.trim())
    this.submitting = false
    if (ok) {
      promptAction.showToast({ message: '回复成功', duration: 1500 })
      this.replyTarget = null
      this.replyText = ''
      await this.loadReviews()
    } else {
      promptAction.showToast({ message: '回复失败，请重试', duration: 2200 })
    }
  }

  build() {
    Stack() {
      Column() {
        // 导航栏
        PageHeader({ title: '评价管理', backText: '‹ 返回', backId: 'merchant-reviews-back', titleColor: MODULE_COLOR.MERCHANT, headerBgColor: MODULE_BG.MERCHANT, onBack: () => { router.back() } })

        if (this.loading) {
          Column() {
            Text('正在加载评价…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.reviews.length === 0) {
          Column() {
            Text('📝').fontSize(60).margin({ top: 40 })
            Text('暂无评价')
              .fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
          List({ space: SPACING.SM }) {
            ForEach(this.reviews, (review: Review) => {
              ListItem() {
                this.ReviewCard(review)
              }
            }, (review: Review) => review.id.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      if (this.replyTarget !== null) {
        this.ReplyDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ReviewCard(review: Review) {
    Column({ space: SPACING.XS }) {
      Row({ space: SPACING.SM }) {
        Text(review.anonymous === 1 ? '匿' : review.username.substring(0, 1))
          .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
          .fontColor(accentFg(accentIndexFromText(review.username)))
          .backgroundColor(accentBg(accentIndexFromText(review.username)))
          .width(28).height(28).textAlign(TextAlign.Center)
          .borderRadius(BORDER_RADIUS.SM)
        Text(review.anonymous === 1 ? '匿名用户' : review.username)
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
        RatingStars({ rating: review.rating, fontSize: FONT_SIZE.SM, showNumber: false })
      }
      .width('100%')

      Text(review.content)
        .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      // 图文评价：展示用户上传的图片，便于商户核对出品与配送问题
      if (Array.isArray(review.images) && review.images.length > 0) {
        Row({ space: SPACING.XS }) {
          ForEach(review.images.slice(0, 3), (imageUrl: string, index: number) => {
            Image(imageUrl)
              .width(72).height(72)
              .borderRadius(BORDER_RADIUS.SM)
              .objectFit(ImageFit.Cover)
              .onClick(() => {
                AppStorage.setOrCreate<string>('reviewPreviewUrl', imageUrl)
                router.pushUrl({ url: 'pages/ReviewImagePage' })
              })
          }, (imageUrl: string, index: number) => `${index}_${imageUrl}`)
        }
        .width('100%')
      }

      if (review.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(review.tags, (tag: string) => {
            Text(tag)
              .fontSize(FONT_SIZE.XS)
              .fontColor(accentFg(accentIndexFromText(tag)))
              .backgroundColor(accentBg(accentIndexFromText(tag)))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(BORDER_RADIUS.SM)
              .margin({ right: 4, bottom: 4 })
          }, (tag: string) => tag)
        }
        .width('100%')
      }

      Text(review.createTime)
        .fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
        .width('100%')

      if (review.reply !== '') {
        Text(`已回复：${review.reply}`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.SUCCESS)
          .width('100%')
          .padding(SPACING.MD)
          .backgroundColor(COLORS.SUCCESS_LIGHT)
          .borderRadius(BORDER_RADIUS.SM)
      }

      Row() {
        Blank()
        Button(review.reply === '' ? '回复' : '修改回复')
          .height(32).fontSize(FONT_SIZE.SM)
          .fontColor(MODULE_COLOR.MERCHANT).backgroundColor(MODULE_BG.MERCHANT)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .onClick(() => { this.openReply(review) })
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  ReplyDialog() {
    Column() {
      Column({ space: SPACING.MD }) {
        Text('回复评价')
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.MERCHANT)
          .width('100%').textAlign(TextAlign.Center)
        Text('回复会展示在用户评价下方')
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
        TextArea({ placeholder: '请输入回复内容，最多200字', text: this.replyText })
          .width('100%').height(100).maxLength(200)
          .fontSize(FONT_SIZE.MD).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.MD)
          .onChange((value: string) => { this.replyText = value })
        Row({ space: SPACING.MD }) {
          Button('取消')
            .layoutWeight(1).height(42)
            .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.replyTarget = null })
          Button(this.submitting ? '提交中…' : '提交回复')
            .layoutWeight(1).height(42)
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.MERCHANT)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.submitReply() })
        }
        .width('100%')
      }
      .width('86%').padding(SPACING.XL)
      .backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    }
    .width('100%').height('100%')
    .backgroundColor(COLORS.OVERLAY)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}
