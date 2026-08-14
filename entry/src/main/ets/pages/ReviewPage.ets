/**
 * 评价页
 * 对已完成订单进行评价：星级评分、标签选择、文字评价
 * 提交后调用 addReview 自动标记订单已评价，并返回上一页
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, REVIEW_TAGS } from '../common/Constants'
import { Order, Review, User } from '../model/Models'
import { getCurrentUser, submitReviewRemote, syncStoreReviewsRemote } from '../service/AppStorageManager'
import { logInfo, logWarn } from '../service/AppLogger'

@Entry
@Component
export struct ReviewPage {
  @State order: Order | null = null
  @State rating: number = 0
  @State content: string = ''
  @State selectedTags: string[] = []
  @State submitting: boolean = false
  orderId: number = 0

  // 评价标签列表（来自 Constants.REVIEW_TAGS）
  private tagList: string[] = [
    REVIEW_TAGS.GOOD_TASTE,
    REVIEW_TAGS.FAST_DELIVERY,
    REVIEW_TAGS.FRESH,
    REVIEW_TAGS.GOOD_SERVICE,
    REVIEW_TAGS.LARGE_PORTION,
    REVIEW_TAGS.CLEAN,
    REVIEW_TAGS.RECOMMEND,
    REVIEW_TAGS.WILL_REORDER
  ]

  // 星级可点击值列表
  private starList: number[] = [1, 2, 3, 4, 5]

  aboutToAppear() {
    logInfo('Page', '进入评价页 ReviewPage')
    this.orderId = AppStorage.get<number>('currentOrderId') || 0
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    this.order = orders.find((o: Order) => o.id === this.orderId) || null
  }

  // ============ 评分文案 ============
  private getRatingText(): string {
    if (this.rating === 1) { return '很不满意' }
    if (this.rating === 2) { return '不满意' }
    if (this.rating === 3) { return '一般' }
    if (this.rating === 4) { return '满意' }
    if (this.rating === 5) { return '很满意' }
    return '请选择评分'
  }

  // ============ 商品简略信息 ============
  private getItemSummary(): string {
    if (this.order === null) { return '' }
    const count: number = this.order.items.length
    if (count === 0) { return '' }
    const firstName: string = this.order.items[0].goods.name
    if (count === 1) { return firstName }
    return `${firstName} 等${count}件商品`
  }

  // ============ 标签选择 ============
  private isTagSelected(tag: string): boolean {
    return this.selectedTags.indexOf(tag) >= 0
  }

  private toggleTag(tag: string): void {
    if (this.isTagSelected(tag)) {
      this.selectedTags = this.selectedTags.filter((t: string) => t !== tag)
    } else {
      this.selectedTags = this.selectedTags.concat([tag])
    }
  }

  // ============ 时间格式化 YYYY-MM-DD HH:mm:ss ============
  private formatCurrentTime(): string {
    const date: Date = new Date()
    const y: number = date.getFullYear()
    const m: string = String(date.getMonth() + 1).padStart(2, '0')
    const d: string = String(date.getDate()).padStart(2, '0')
    const h: string = String(date.getHours()).padStart(2, '0')
    const min: string = String(date.getMinutes()).padStart(2, '0')
    const s: string = String(date.getSeconds()).padStart(2, '0')
    return `${y}-${m}-${d} ${h}:${min}:${s}`
  }

  // ============ 提交评价 ============
  private submitReview(): void {
    if (this.submitting) { return }
    if (this.order === null) {
      promptAction.showToast({ message: '订单不存在' })
      return
    }
    if (this.rating === 0) {
      promptAction.showToast({ message: '请先选择评分' })
      logWarn('Review', '提交评价失败：未选择评分')
      return
    }
    const user: User | undefined = getCurrentUser()
    if (user === undefined || user === null) {
      promptAction.showToast({ message: '请先登录' })
      return
    }

    this.submitting = true
    const review: Review = {
      id: Date.now(),
      orderId: this.order.id,
      storeId: this.order.storeId,
      userId: user.id,
      username: user.username,
      rating: this.rating,
      content: this.content,
      tags: this.selectedTags,
      createTime: this.formatCurrentTime()
    }
    // 调用后端提交评价（真实后端模式）
    this.submitRemote(review)
  }

  // 远程提交评价
  private async submitRemote(review: Review): Promise<void> {
    const ok: boolean = await submitReviewRemote(review.orderId, review.rating, review.content, review.tags)
    if (ok) {
      await syncStoreReviewsRemote(review.storeId)
      logInfo('Review', `提交评价成功 orderId=${review.orderId} 评分=${review.rating} 标签=${review.tags.length}个`)
      promptAction.showToast({ message: '评价成功' })
      this.submitting = false
      router.back()
    } else {
      this.submitting = false
      promptAction.showToast({ message: '评价提交失败，请重试' })
    }
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('订单评价')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
          .fontSize(28)
          .width(28)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
      .alignItems(VerticalAlign.Center)

      if (this.order === null) {
        Column() {
          Text('📦').fontSize(60).margin({ top: 100 })
          Text('订单不存在').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: SPACING.SM }) {
            // 店铺与商品简略信息
            this.StoreInfoCard()

            // 评分卡片
            this.RatingCard()

            // 标签选择卡片
            this.TagsCard()

            // 文字评价卡片
            this.ContentCard()
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XL })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(COLORS.BG_PRIMARY)

        // 底部提交按钮
        Row() {
          Button('提交评价')
            .width('100%')
            .height(48)
            .fontSize(FONT_SIZE.LG)
            .fontColor(COLORS.TEXT_WHITE)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND)
            .type(ButtonType.Capsule)
            .onClick(() => { this.submitReview() })
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.MD })
        .backgroundColor(COLORS.BG_WHITE)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  @Builder
  StoreInfoCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('🏪')
          .fontSize(FONT_SIZE.LG)
        Text(this.order!.storeName)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .margin({ left: SPACING.SM })
      }
      .width('100%')

      Text(this.getItemSummary())
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  RatingCard() {
    Column({ space: SPACING.MD }) {
      Text('整体评分')
        .fontSize(FONT_SIZE.LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      Row({ space: SPACING.XS }) {
        ForEach(this.starList, (star: number) => {
          Text('★')
            .fontSize(FONT_SIZE.BIG_TITLE)
            .fontColor(star <= this.rating ? COLORS.PRIMARY : COLORS.DIVIDER)
            .padding({ left: SPACING.XS, right: SPACING.XS })
            .onClick(() => { this.rating = star })
        }, (star: number) => star.toString())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text(this.getRatingText())
        .fontSize(FONT_SIZE.MD)
        .fontColor(this.rating === 0 ? COLORS.TEXT_HINT : COLORS.PRIMARY)
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  TagsCard() {
    Column({ space: SPACING.MD }) {
      Text('评价标签')
        .fontSize(FONT_SIZE.LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.tagList, (tag: string) => {
          Text(tag)
            .fontSize(FONT_SIZE.MD)
            .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
            .margin({ right: SPACING.SM, bottom: SPACING.SM })
            .borderRadius(BORDER_RADIUS.ROUND)
            .backgroundColor(this.isTagSelected(tag) ? COLORS.PRIMARY : COLORS.TAG_BG)
            .fontColor(this.isTagSelected(tag) ? COLORS.TEXT_WHITE : COLORS.TAG_TEXT)
            .onClick(() => { this.toggleTag(tag) })
        }, (tag: string) => tag)
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  ContentCard() {
    Column({ space: SPACING.SM }) {
      Row() {
        Text('文字评价')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(`${this.content.length}/200`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
      }
      .width('100%')

      TextArea({ placeholder: '请写下您对本次订餐的评价...' })
        .width('100%')
        .height(120)
        .maxLength(200)
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_PRIMARY)
        .borderRadius(BORDER_RADIUS.MD)
        .backgroundColor(COLORS.BG_PRIMARY)
        .padding(SPACING.MD)
        .onChange((value: string) => {
          this.content = value
        })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }
}
