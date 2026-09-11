/**
 * 商户评价管理页
 * 查看本店收到的评价并回复
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { Review } from '../model/Models'
import { syncMerchantReviewsRemote, replyReviewRemote } from '../service/AppStorageManager'
import { RatingStars } from '../components/RatingStars'
import { logInfo } from '../service/AppLogger'

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
        Row() {
          Text('‹ 返回')
            .fontSize(FONT_SIZE.MD)
            .fontColor(COLORS.TEXT_PRIMARY)
            .onClick(() => { router.back() })
          Text('评价管理')
            .fontSize(FONT_SIZE.XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text(' ')
            .fontSize(FONT_SIZE.MD)
            .width(28)
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(COLORS.BG_WHITE)

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
          Scroll() {
            Column({ space: SPACING.SM }) {
              ForEach(this.reviews, (review: Review) => {
                this.ReviewCard(review)
              }, (review: Review) => review.id.toString())
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
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
        Text(review.anonymous === 1 ? '匿名用户' : review.username)
          .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
        RatingStars({ rating: review.rating, fontSize: FONT_SIZE.SM, showNumber: false })
      }
      .width('100%')

      Text(review.content)
        .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      if (review.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(review.tags, (tag: string) => {
            Text(tag)
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT).backgroundColor(COLORS.TAG_BG)
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
          .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.TAG_BG)
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
          .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
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
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(COLORS.PRIMARY)
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
