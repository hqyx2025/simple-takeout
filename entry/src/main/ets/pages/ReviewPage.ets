/**
 * 评价页
 * 对已完成订单进行评价：星级评分、标签选择、文字评价、图文评价（选图 → 上传 → 预览 → 删除）
 * 提交后调用 addReview 自动标记订单已评价，并返回上一页
 */
import { AppMotion } from '../common/theme/AppMotion'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { API_CONFIG, COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, REVIEW_TAGS } from '../common/Constants'
import { CartItem, Order, Review, User } from '../model/Models'
import { getCurrentUser, submitReviewRemote, syncStoreReviewsRemote, syncUserOrdersFromServer, uploadReviewImageRemote } from '../service/AppStorageManager'
import { logInfo, logWarn } from '../service/AppLogger'
import { PageHeader } from '../components/PageHeader'
import { photoAccessHelper } from '@kit.MediaLibraryKit'

/** 图文评价最多上传的图片数量 */
const MAX_REVIEW_IMAGES: number = 3
/** 图片格子宽度：一行 3 个，加上右边距后仍不超过卡片内容宽度 */
const IMAGE_TILE_WIDTH: string = '30%'

@Entry
@Component
export struct ReviewPage {
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

  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State order: Order | null = null
  @State rating: number = 0
  @State content: string = ''
  @State selectedTags: string[] = []
  @State submitting: boolean = false
  @State selectedGoodsId: number = 0
  @State anonymous: boolean = false
  // 已上传成功的图片完整地址（提交评价时传给后端）
  @State images: string[] = []
  // 上传中的占位格子：元素值为本批次图片序号，仅用于渲染与 ForEach 键
  @State pendingTiles: number[] = []
  // 页面是否存活：图片上传是异步流程，离开页面后不再回写 @State 或弹 Toast
  private pageAlive: boolean = true
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
    this.pageAlive = true
    logInfo('Page', '进入评价页 ReviewPage')
    if (!this.loggedIn) {
      return
    }
    this.orderId = AppStorage.get<number>('currentOrderId') || 0
    const orders: Order[] = AppStorage.get<Order[]>('orderList') || []
    this.order = orders.find((o: Order) => o.id === this.orderId) || null
    if (this.order !== null && this.order.items.length > 0) {
      const requestedGoodsId: number = AppStorage.get<number>('currentReviewGoodsId') || 0
      const exists: boolean = this.order.items.some((item: CartItem) => item.goods.id === requestedGoodsId)
      this.selectedGoodsId = exists ? requestedGoodsId : this.order.items[0].goods.id
    }
  }

  // 从系统图库选择图片返回时页面重新可见，恢复异步回写开关
  onPageShow(): void {
    this.pageAlive = true
  }

  aboutToDisappear(): void {
    // 图片上传是异步流程：离开页面后不再回写 @State、不再弹 Toast，清空中间状态避免内存泄漏
    this.pageAlive = false
    this.pendingTiles = []
    logInfo('Page', '离开评价页 ReviewPage')
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
    if (this.pendingTiles.length > 0) {
      promptAction.showToast({ message: '图片正在上传，请稍候再提交' })
      return
    }
    if (this.order === null) {
      promptAction.showToast({ message: '订单不存在' })
      return
    }
    if (this.selectedGoodsId <= 0 || this.order.items.length === 0) {
      promptAction.showToast({ message: '订单中没有可评价的商品' })
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
      goodsId: this.selectedGoodsId,
      userId: user.id,
      username: user.username,
      rating: this.rating,
      content: this.content,
      tags: this.selectedTags,
      images: this.images.slice(),
      anonymous: this.anonymous ? 1 : 0,
      reply: '',
      replyTime: '',
      createTime: this.formatCurrentTime()
    }
    // 调用后端提交评价（真实后端模式）
    this.submitRemote(review)
  }

  // 远程提交评价
  private async submitRemote(review: Review): Promise<void> {
    const ok: boolean = await submitReviewRemote(review.orderId, review.goodsId, review.rating, review.content, review.tags, review.images, review.anonymous)
    if (ok) {
      await syncStoreReviewsRemote(review.storeId)
      await syncUserOrdersFromServer()
      logInfo('Review', `提交评价成功 orderId=${review.orderId} 评分=${review.rating} 标签=${review.tags.length}个 图片=${review.images.length}张`)
      promptAction.showToast({ message: '评价成功' })
      this.submitting = false
      router.back()
    } else {
      this.submitting = false
      promptAction.showToast({ message: '评价提交失败，请重试' })
    }
  }

  // ============ 图文评价：选图 → 上传 → 预览 → 删除 ============

  /** 点击「添加图片」：先做前置校验，再从系统图库选图并逐张上传。 */
  private async pickAndUploadImages(): Promise<void> {
    if (this.pendingTiles.length > 0) {
      promptAction.showToast({ message: '图片正在上传，请稍候', duration: 2000 })
      return
    }
    const remain: number = MAX_REVIEW_IMAGES - this.images.length - this.pendingTiles.length
    if (remain <= 0) {
      promptAction.showToast({ message: '最多上传 3 张图片', duration: 2000 })
      return
    }
    let selectedUris: string[] = []
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = remain
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options)
      selectedUris = result.photoUris
    } catch (err) {
      // 用户主动取消一般返回空数组；进入异常分支说明图库选择器启动或返回失败
      let detail: string = ''
      if (err instanceof Error) {
        detail = err.message
      }
      logWarn('Review', `打开系统图库选择图片失败：${detail}`)
      if (this.pageAlive) {
        promptAction.showToast({ message: '选择图片失败，请重试', duration: 3000 })
      }
      return
    }
    if (!this.pageAlive) {
      return
    }
    if (selectedUris.length === 0) {
      logInfo('Review', '用户取消选择图片')
      return
    }
    // 防御：系统最多返回 remain 张，多选部分直接丢弃
    const pickedUris: string[] = selectedUris.length > remain ? selectedUris.slice(0, remain) : selectedUris
    await this.uploadImages(pickedUris)
  }

  /** 依次上传选中的图片：单张失败只跳过该张，不阻塞其余图片与页面其他操作。 */
  private async uploadImages(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return
    }
    this.pendingTiles = this.buildPendingTiles(uris.length)
    let failedCount: number = 0
    let addedCount: number = 0
    try {
      for (let i = 0; i < uris.length; i++) {
        if (!this.pageAlive) {
          return
        }
        let uploadedUrl: string = ''
        try {
          uploadedUrl = await uploadReviewImageRemote(uris[i])
        } catch (_) {
          // 服务层已把失败收敛为返回空串；这里再兜一层，避免单张异常中断整批上传
          uploadedUrl = ''
        }
        if (!this.pageAlive) {
          return
        }
        // 一张结束就移除队首占位格子（占位值即批次序号，队首始终是正在上传的那张）
        this.pendingTiles = this.pendingTiles.slice(1)
        if (uploadedUrl === '') {
          failedCount++
          logWarn('Review', `第 ${i + 1} 张评价图片上传失败，已跳过`)
          if (failedCount === 1) {
            // 只提示一次，避免多张失败时提示互相覆盖
            promptAction.showToast({ message: '图片上传失败，请重试', duration: 3000 })
          }
          continue
        }
        if (this.images.length >= MAX_REVIEW_IMAGES) {
          break
        }
        // 服务层正常返回完整地址；若返回相对地址则补全 BASE_URL（防御）
        const fullUrl: string = uploadedUrl.startsWith('/') ? API_CONFIG.BASE_URL + uploadedUrl : uploadedUrl
        this.images = this.images.concat([fullUrl])
        addedCount++
      }
    } finally {
      // 无论成功失败都清空占位格子，避免上传态卡住「添加图片」
      this.pendingTiles = []
    }
    if (this.pageAlive && addedCount > 0 && failedCount === 0) {
      promptAction.showToast({ message: `已添加 ${addedCount} 张图片`, duration: 2000 })
    }
    logInfo('Review', `评价图片上传结束：成功 ${addedCount} 张，失败 ${failedCount} 张，当前共 ${this.images.length} 张`)
  }

  /** 上传中的占位格子数组（元素值即本批次图片序号）。 */
  private buildPendingTiles(count: number): number[] {
    const tiles: number[] = []
    for (let i = 0; i < count; i++) {
      tiles.push(i)
    }
    return tiles
  }

  /** 删除已上传的图片（缩略图右上角「×」）。 */
  private removeImage(index: number): void {
    if (index < 0 || index >= this.images.length) {
      return
    }
    const next: string[] = this.images.slice()
    next.splice(index, 1)
    this.images = next
    logInfo('Review', `删除评价图片，剩余 ${this.images.length} 张`)
    promptAction.showToast({ message: '已删除', duration: 1500 })
  }

  /** 图片区提示文案：上传中显示剩余张数，空闲时显示上传规则。 */
  private getImageHint(): string {
    if (this.pendingTiles.length > 0) {
      return `正在上传 ${this.pendingTiles.length} 张图片，请稍候...`
    }
    return '选填，最多上传 3 张图片，支持 jpg/png/webp/gif，单张不超过 5MB'
  }

  build() {
    Column() {
      // 导航栏
      PageHeader({ title: '订单评价', backId: 'review-back', onBack: () => { router.back() } })

      if (!this.loggedIn) {
        Column() {
          SymbolGlyph($r('sys.symbol.lock')).fontSize(60).margin({ top: 100 })
          Text('暂无登录').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.LG })
          Text('请登录后查看和提交评价').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.SM })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.order === null) {
        Column() {
          SymbolGlyph($r('sys.symbol.gift')).fontSize(60).margin({ top: 100 })
          Text('订单不存在').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.LG })
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

            // 选择本次要评价的具体商品
            this.ProductSelectCard()

            // 评分卡片
            this.RatingCard()

            // 标签选择卡片
            this.TagsCard()

            // 匿名评价开关
            this.AnonymousCard()

            // 文字评价卡片
            this.ContentCard()

            // 图文评价：选图 / 上传 / 预览 / 删除
            this.ImageCard()
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
            .id('review-submit')
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
        SymbolGlyph($r('sys.symbol.store')).fontSize(FONT_SIZE.LG)
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
  ProductSelectCard() {
    if (this.order !== null && this.order.items.length > 0) {
      Column({ space: SPACING.SM }) {
        Text('评价商品').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY).width('100%')
        if (this.order.items.length === 1) {
          Text(this.order.items[0].goods.name).fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY)
            .width('100%').padding(SPACING.MD).backgroundColor(COLORS.TAG_BG)
            .borderRadius(BORDER_RADIUS.MD)
        } else {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.order.items, (item: CartItem) => {
              Text(item.goods.name)
                .fontSize(FONT_SIZE.MD)
                .fontColor(this.selectedGoodsId === item.goods.id ? COLORS.TEXT_WHITE : COLORS.TEXT_SECONDARY)
                .backgroundColor(this.selectedGoodsId === item.goods.id ? COLORS.PRIMARY : COLORS.TAG_BG)
                .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
                .margin({ right: SPACING.SM, bottom: SPACING.SM })
                .borderRadius(BORDER_RADIUS.ROUND)
                .onClick(() => { this.selectedGoodsId = item.goods.id })
            }, (item: CartItem) => `${item.goods.id}_${item.specId ?? 0}`)
          }.width('100%')
        }
      }
      .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE)
      .borderRadius(BORDER_RADIUS.LG)
    }
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
            .id(`review-star-${star}`)
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
        ForEach(this.tagList, (tag: string, index: number) => {
          Text(tag)
            .fontSize(FONT_SIZE.MD)
            .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.SM, bottom: SPACING.SM })
            .margin({ right: SPACING.SM, bottom: SPACING.SM })
            .borderRadius(BORDER_RADIUS.ROUND)
            .backgroundColor(this.isTagSelected(tag) ? COLORS.PRIMARY : COLORS.TAG_BG)
            .fontColor(this.isTagSelected(tag) ? COLORS.TEXT_WHITE : COLORS.TAG_TEXT)
            .id(`review-tag-${index}`)
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
  AnonymousCard() {
    Row() {
      Text('匿名评价')
        .fontSize(FONT_SIZE.LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .layoutWeight(1)
      Text('开启后其他人将看不到你的昵称')
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ right: SPACING.SM })
      Toggle({ type: ToggleType.Switch, isOn: this.anonymous })
        .onChange((isOn: boolean) => { this.anonymous = isOn })
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
        .id('review-content')
        .onChange((value: string) => {
          this.content = value
        })
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  // ============ 图文评价卡片 ============
  @Builder
  ImageCard() {
    Column({ space: SPACING.MD }) {
      Row() {
        Text('图片评价')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(`${this.images.length}/${MAX_REVIEW_IMAGES}`)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
          .id('review-image-count')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap }) {
        // 已上传成功的缩略图（右上角「×」删除）
        ForEach(this.images, (url: string, index: number) => {
          this.imageCell(url, index)
        }, (url: string, index: number) => `${index}_${url}`)

        // 上传中的占位格子
        ForEach(this.pendingTiles, (seq: number) => {
          this.uploadingCell(seq)
        }, (seq: number) => `pending_${seq}`)

        // 添加入口：始终保留，已满或上传中点击时给出提示
        this.addImageCell()
      }
      .width('100%')

      Text(this.getImageHint())
        .fontSize(FONT_SIZE.SM)
        .fontColor(COLORS.TEXT_HINT)
        .width('100%')
        .id('review-image-hint')
    }
    .width('100%')
    .padding(SPACING.LG)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  /** 已上传图片缩略图：整格铺满 + 右上角删除按钮。 */
  @Builder
  imageCell(url: string, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(url)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(BORDER_RADIUS.MD)
        .backgroundColor(COLORS.BG_PRIMARY)

      Text('×')
        .fontSize(FONT_SIZE.MD)
        .fontColor(COLORS.TEXT_WHITE)
        .width(20)
        .height(20)
        .textAlign(TextAlign.Center)
        .backgroundColor(COLORS.OVERLAY)
        .borderRadius(BORDER_RADIUS.CIRCLE)
        .margin({ top: SPACING.XS, right: SPACING.XS })
        .id(`review-image-remove-${index}`)
        .onClick(() => { this.removeImage(index) })
    }
    .width(IMAGE_TILE_WIDTH)
    .aspectRatio(1)
    .margin({ right: SPACING.SM, bottom: SPACING.SM })
    .id(`review-image-${index}`)
  }

  /** 上传中的占位格子（文案只依赖入参，避免复用时的脏状态）。 */
  @Builder
  uploadingCell(seq: number) {
    Column({ space: SPACING.XS }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(COLORS.PRIMARY)
      Text(`第${seq + 1}张`)
        .fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.TEXT_HINT)
    }
    .width(IMAGE_TILE_WIDTH)
    .aspectRatio(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(COLORS.BG_PRIMARY)
    .borderRadius(BORDER_RADIUS.MD)
    .margin({ right: SPACING.SM, bottom: SPACING.SM })
  }

  /** 添加图片入口：已满时置灰但仍可点击（点击给出「最多上传 3 张图片」提示）。 */
  @Builder
  addImageCell() {
    Column({ space: SPACING.XS }) {
      Text('+')
        .fontSize(FONT_SIZE.TITLE)
        .fontColor(this.images.length >= MAX_REVIEW_IMAGES ? COLORS.TEXT_HINT : COLORS.PRIMARY)
      Text(this.images.length >= MAX_REVIEW_IMAGES ? '已满 3 张' : '添加图片')
        .fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.TEXT_HINT)
    }
    .width(IMAGE_TILE_WIDTH)
    .aspectRatio(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(COLORS.BG_PRIMARY)
    .borderRadius(BORDER_RADIUS.MD)
    .borderWidth(1)
    .borderColor(COLORS.DIVIDER)
    .margin({ right: SPACING.SM, bottom: SPACING.SM })
    .id('review-add-image')
    .onClick(() => { this.pickAndUploadImages() })
  }
}
