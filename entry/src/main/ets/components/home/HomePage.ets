import { AppButtonStyle, AppRefreshStyle, AppTheme } from '../../common/theme/AppTheme'
/**
 * 主页面 - 简单外卖App
 * 包含：搜索栏、分类导航、店铺列表、店铺详情、购物车、订单列表、个人中心、底部Tab导航
 */
import { Category, StoreItem, SpecialGoodsItem, SeckillItem, Address, Banner, Announcement } from '../../model/Models'
import { isLoggedIn, getAllStoresList, syncCategoriesFromServer, syncBannersRemote, syncAnnouncementsRemote, syncStoresFromServer, fetchSeckillsRemote } from '../../service/AppStorageManager'
import { fetchRecommendedStoresApi, fetchSpecialGoodsApi } from '../../service/ApiService'

import { FloatingTabBarTheme } from '../../common/theme/FloatingTabBarTheme'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, formatSales, merchantImageSource, DEFAULT_MERCHANT_IMAGE, MODULE_COLOR, MODULE_BG, accentFg, accentIndexFromText } from '../../common/Constants'

import { RatingStars } from '../../components/RatingStars'

import { PageHeader } from '../../components/PageHeader'
import { promptCompat as promptAction, routerCompat as router } from '../../common/UiNavigation'
import { logInfo, logError } from '../../service/AppLogger'

import { HomeTheme } from '../../common/theme/HomeTheme'
import { BreakpointSystem } from '../../common/utils/BreakpointSystem'

import { AppMotion } from '../../common/theme/AppMotion'
import { common } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { RecommendedStoreCardHost } from './RecommendedStoreCardHost'

// 定义快捷入口和订单Tab的数据类型，解决 arkts-no-untyped-obj-literals 错误
class QuickEntryItem {
  icon: Resource = $r('app.media.home_bowl')
  title: string = ''

  static create(icon: Resource, title: string): QuickEntryItem {
    let item = new QuickEntryItem()
    item.icon = icon
    item.title = title
    return item
  }
}

@Component
export struct HomePage {
  @Prop bottomInset: number = 0
  @StorageLink('appReduceMotion') reduceMotion: boolean = false
  @State bannerVisible: boolean = false
  @StorageLink('categoryList') categories: Category[] = []
  @StorageLink('isLoggedIn') @Watch('onLoginStateChange') loggedIn: boolean = false
  @State specialGoods: SpecialGoodsItem[] = []
  @State banners: Banner[] = []
  @State announcements: Announcement[] = []
  @State selectedAnnouncement: Announcement | null = null
  @State showAnnouncementSheet: boolean = false
  // 限时秒杀（服务端时间窗口内且有剩余名额的秒杀）
  @State seckills: SeckillItem[] = []
  // 秒杀倒计时秒表：每秒 +1，与实际剩余时间相减得到实时剩余（避免每个卡片各自起定时器）
  @State seckillTick: number = 0
  private seckillTimer: number = -1
  @State searchText: string = ''
  @State currentCategory: number = 0
  @State isRefreshing: boolean = false
  @StorageLink('currentAddress') @Watch('onCurrentAddressChange') currentAddress: Address | null = null
  @StorageLink('addressSyncState') addressSyncState: string = 'idle'
  @State isHeaderVisible: boolean = false
  // 附近推荐（原「发现」Tab 的能力，现并入首页）：进入首页与定位变化时刷新
  @State recommendedStores: StoreItem[] = []
  @State recommendedLoading: boolean = false
  @State homeGridColumns: number = 2
  private homeBreakpoint: BreakpointSystem = new BreakpointSystem()
  // 隐私政策同意改由独立页面 pages/ConsentPage 承载（见该文件注释），首页不再内嵌同意弹窗
  onStoreClick: (store: StoreItem) => void = () => {}
  onNavigateLogin: () => void = () => {}
  onNavigateLocationLogin: () => void = () => {}

  onLoginStateChange(): void {
    if (this.loggedIn) {
      this.refreshHomeData()
      this.refreshRecommended()
    } else {
      this.specialGoods = []
      this.recommendedStores = []
    }
  }

  onCurrentAddressChange(): void {
    this.refreshHomeData()
    this.refreshRecommended()
  }

  /** 拉取附近推荐店铺（2 公里内、平台推荐位）。 */
  private async refreshRecommended(): Promise<void> {
    if (!this.loggedIn) {
      return
    }
    if (this.recommendedLoading) {
      promptAction.showToast({ message: '推荐店铺正在刷新，请稍候', duration: 1200 })
      return
    }
    this.recommendedLoading = true
    const latitude: number | undefined = this.currentAddress !== null ? this.currentAddress.latitude : undefined
    const longitude: number | undefined = this.currentAddress !== null ? this.currentAddress.longitude : undefined
    this.recommendedStores = await fetchRecommendedStoresApi(2, 10, latitude, longitude)
    this.recommendedLoading = false
  }

  /** 推荐区需要定位：没有经纬度时提示去定位，而不是显示空列表。 */
  private hasRecommendLocation(): boolean {
    if (this.currentAddress === null) {
      return false
    }
    const address: Address = this.currentAddress as Address
    return address.latitude !== undefined && address.longitude !== undefined
      && Number.isFinite(address.latitude) && Number.isFinite(address.longitude)
  }

  // 首页定位栏只展示“市 + 区/县/旗”，完整地址仍保留在 currentAddress 中供结算和配送使用
  private getCityDistrict(address: string): string {
    const compactAddress: string = address.replace(/\s+/g, '').replace(/^中国/, '')
    if (compactAddress === '') {
      return ''
    }
    const cityMatch = compactAddress.match(/([^省自治区特别行政区]+市)/)
    if (cityMatch !== null) {
      const cityName: string = cityMatch[1]
      const cityIndex: number = compactAddress.indexOf(cityName)
      const remainingAddress: string = compactAddress.substring(cityIndex + cityName.length)
      const districtMatch = remainingAddress.match(/([^市]+?(?:区|县|旗))/)
      if (districtMatch !== null) {
        return `${cityName}${districtMatch[1]}`
      }
      return cityName
    }
    const districtMatch = compactAddress.match(/([^省市自治区特别行政区]+(?:区|县|旗))/)
    if (districtMatch !== null) {
      return districtMatch[1]
    }
    return compactAddress
  }

  private getDisplayAddress(): string {
    if (this.currentAddress === null) {
      return '未定位，点击定位'
    }
    const address: string = this.currentAddress.address.trim()
    const coordinatePattern: RegExp = /^\(-?\d+(\.\d+)?,\s*-?\d+(\.\d+)?\)$/
    if (address !== '' && !coordinatePattern.test(address)) {
      return this.getCityDistrict(address)
    }
    const detail: string = this.currentAddress.detail.trim()
    if (detail !== '' && !coordinatePattern.test(detail)) {
      return this.getCityDistrict(detail)
    }
    return '位置已获取，点击查看地址'
  }

  aboutToAppear() {
    this.isHeaderVisible = true
    this.homeBreakpoint.register(this.getUIContext().getHostContext() as common.UIAbilityContext,
      (_breakpoint: string) => {
        this.homeGridColumns = display.isFoldable() && this.homeBreakpoint.isWideForLayout() ? 3 : 2
      })
    const initialCategories: Category[] = AppStorage.get<Category[]>('categoryList') || []
    this.categories = initialCategories.slice()
    // 秒杀倒计时：单个 1 秒定时器驱动全页秒杀卡片，避免每张卡片各起一个定时器
    this.startSeckillTicker()
    // 隐私同意前不发起网络请求（未同意时 Index 会先跳转 ConsentPage，正常不会走到这里）
    if (AppStorage.get<boolean>('privacyConsent') || false) {
      this.refreshHomeData()
      this.refreshRecommended()
    } else {
      logInfo('Home', '隐私政策未同意，等待用户确认后再加载首页数据')
    }
  }

  aboutToDisappear() {
    this.stopSeckillTicker()
    this.homeBreakpoint.unregister()
  }

  // 首页特价团购直接读取后端商品接口，避免使用本地模拟商品。
  private async refreshHomeData(): Promise<void> {
    if (!(AppStorage.get<boolean>('privacyConsent') || false)) {
      logInfo('Home', '未同意隐私政策，跳过首页数据加载')
      return
    }
    this.isRefreshing = true
    // 首页数据依赖多个接口，任一失败都不能中断后续步骤（否则秒杀/特价会整块消失），
    // 因此逐步打点并整体捕获异常，异常时保留已有数据并明确记录原因。
    try {
      logInfo('Home', '首页数据加载[1/5] 分类')
      await syncCategoriesFromServer()
      const latestCategories: Category[] = AppStorage.get<Category[]>('categoryList') || []
      this.categories = latestCategories.slice()
      logInfo('Home', '首页数据加载[2/5] 店铺')
      await syncStoresFromServer()
      logInfo('Home', '首页数据加载[3/5] 轮播')
      this.banners = await syncBannersRemote()
      logInfo('Home', '首页数据加载[4/5] 公告')
      this.announcements = await syncAnnouncementsRemote()
      logInfo('Home', '首页数据加载[5/5] 特价与秒杀')
      if (this.loggedIn) {
        const latitude: number | undefined = this.currentAddress !== null ? this.currentAddress.latitude : undefined
        const longitude: number | undefined = this.currentAddress !== null ? this.currentAddress.longitude : undefined
        this.specialGoods = await fetchSpecialGoodsApi(10, latitude, longitude)
        this.seckills = await fetchSeckillsRemote(6)
      } else {
        this.specialGoods = []
        this.seckills = []
      }
      logInfo('Home', `首页数据加载完成：轮播=${this.banners.length} 公告=${this.announcements.length} 特价=${this.specialGoods.length} 秒杀=${this.seckills.length}`)
    } catch (err) {
      logError('Home', '首页数据加载失败（已保留部分数据）', err as Object)
    } finally {
      this.isRefreshing = false
    }
  }

  // ============ 限时秒杀 ============

  private startSeckillTicker(): void {
    if (this.seckillTimer >= 0) {
      return
    }
    this.seckillTick = 0
    this.seckillTimer = setInterval(() => {
      this.seckillTick += 1
    }, 1000)
  }

  private stopSeckillTicker(): void {
    if (this.seckillTimer >= 0) {
      clearInterval(this.seckillTimer)
      this.seckillTimer = -1
    }
  }

  /** 秒杀剩余秒数（服务端下发的 remainSeconds 减去本地秒表）。 */
  private seckillRemainSeconds(item: SeckillItem): number {
    return Math.max(item.remainSeconds - this.seckillTick, 0)
  }

  /** 秒杀倒计时文案：HH:mm:ss。 */
  private seckillCountdown(item: SeckillItem): string {
    const total: number = this.seckillRemainSeconds(item)
    const hour: number = Math.floor(total / 3600)
    const minute: number = Math.floor((total % 3600) / 60)
    const second: number = total % 60
    const hh: string = hour < 10 ? `0${hour}` : `${hour}`
    const mm: string = minute < 10 ? `0${minute}` : `${minute}`
    const ss: string = second < 10 ? `0${second}` : `${second}`
    return `${hh}:${mm}:${ss}`
  }

  /** 秒杀进度百分比（已抢名额 / 总名额）。 */
  private seckillSoldPercent(item: SeckillItem): number {
    if (item.quota <= 0) {
      return 0
    }
    return Math.min(Math.round(item.sold * 100 / item.quota), 100)
  }

  /** 点击秒杀商品：进入所属店铺详情继续选购（秒杀价由后端下单时自动套用）。 */
  private openSeckillStore(item: SeckillItem): void {
    if (item.storeId <= 0) {
      promptAction.showToast({ message: '秒杀商品所属店铺信息缺失', duration: 2500 })
      return
    }
    AppStorage.setOrCreate<number>('selectedStoreId', item.storeId)
    AppStorage.setOrCreate<string>('selectedStoreName', item.storeName)
    router.pushUrl({ url: 'pages/StoreDetailPage' })
  }

  private hasCurrentLocation(): boolean {
    if (this.currentAddress === null) {
      return false
    }
    const address: Address = this.currentAddress as Address
    return address.latitude !== undefined && address.longitude !== undefined
      && Number.isFinite(address.latitude) && Number.isFinite(address.longitude)
  }

  private parseStoreDistance(distance: string): number {
    const match: RegExpMatchArray | null = distance.match(/([0-9]+(?:\.[0-9]+)?)/)
    return match === null ? Number.MAX_VALUE : Number.parseFloat(match[1])
  }

  private getNearbyStores(): StoreItem[] {
    if (!this.hasCurrentLocation()) {
      return []
    }
    return getAllStoresList().filter((store: StoreItem) => this.parseStoreDistance(store.distance) <= 2.0)
  }

  private getCategoryRowsTemplate(): string {
    const rowCount: number = Math.max(1, Math.ceil(this.categories.length / 5))
    let template: string = ''
    for (let i = 0; i < rowCount; i++) {
      template += i === 0 ? '1fr' : ' 1fr'
    }
    return template
  }

  private getCategoryGridHeight(): number {
    const rowCount: number = Math.max(1, Math.ceil(this.categories.length / 5))
    return rowCount * 80
  }

  // 仅映射展示资源；分类名称、ID、顺序和服务器 icon 字段保持原样。
  private getCategoryIcon(category: Category): Resource {
    const label: string = category.name + (category.icon ?? '')
    if (label.includes('饮') || label.includes('茶') || label.includes('🧋')) { return $r('app.media.home_drink') }
    if (label.includes('甜') || label.includes('糕') || label.includes('🍰')) { return $r('app.media.home_cake') }
    if (label.includes('火锅') || label.includes('🍲')) { return $r('app.media.home_pot') }
    if (label.includes('烧烤') || label.includes('🍢')) { return $r('app.media.home_skewer') }
    if (label.includes('寿司') || label.includes('🍣')) { return $r('app.media.home_sushi') }
    if (label.includes('快餐') || label.includes('🍟')) { return $r('app.media.home_fries') }
    if (label.includes('美食') || label.includes('汉堡') || label.includes('🍔')) { return $r('app.media.home_burger') }
    return $r('app.media.home_bowl')
  }

  @Builder
  homeEmpty(icon: Resource, title: string, description: string) {
    Column({ space: SPACING.SM }) {
      Image(icon).width(HomeTheme.EMPTY_ICON).height(HomeTheme.EMPTY_ICON)
        .accessibilityLevel('no')
      Text(title).fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Medium).fontColor(HomeTheme.TEXT)
      Text(description).fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED).textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: SPACING.XXL, bottom: SPACING.XXL, left: SPACING.XL, right: SPACING.XL })
    .alignItems(HorizontalAlign.Center)
  }

  private openProductList(mode: string, categoryId: number, title: string): void {
    const requiresLocation: boolean = mode === 'nearby' || mode === 'all'
    if (requiresLocation && !this.loggedIn) {
      this.onNavigateLocationLogin()
      return
    }
    if ((mode === 'nearby' || mode === 'all') && !this.hasCurrentLocation()) {
      promptAction.showToast({ message: '请先定位，再查看附近商品', duration: 1500 })
      router.pushUrl({ url: 'pages/LocationPage' })
      return
    }
    AppStorage.setOrCreate<string>('productListMode', mode)
    AppStorage.setOrCreate<number>('productListCategoryId', categoryId)
    AppStorage.setOrCreate<string>('productListTitle', title)
    router.pushUrl({ url: 'pages/ProductListPage' })
  }

  build() {
    // 根节点必须用 Stack 承载隐私弹窗这类覆盖层：
    // 弹窗若作为 Column 中 layoutWeight(1) 滚动区的兄弟节点，会被分配 0 高度而整块不渲染（历史 bug）。
    Stack() {
    Column() {
      // 地址与搜索分行，窄屏时仍保留完整的触控区域。
      Column({ space: SPACING.SM }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: SPACING.SM }) {
            Image($r('app.media.home_location')).width(HomeTheme.ICON).height(HomeTheme.ICON)
              .accessibilityLevel('no')
            Text(this.currentAddress !== null ? '配送至 ' + this.getDisplayAddress()
              : this.addressSyncState === 'failed' ? '地址未同步，点击选择'
              : this.addressSyncState === 'loading' ? '正在同步配送地址…' : '选择配送地址')
              .fontSize(FONT_SIZE.LG).fontColor(HomeTheme.TEXT).fontWeight(FontWeight.Bold)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Image($r('app.media.home_chevron')).width(HomeTheme.SMALL_ICON).height(HomeTheme.SMALL_ICON)
              .accessibilityLevel('no')
          }
          .width('100%')
        }
          .attributeModifier(new AppButtonStyle())
        .width('100%').height(HomeTheme.TOUCH_HEIGHT)
        .padding(0).backgroundColor(Color.Transparent)
        .animation(AppMotion.pressAnimation())
        .id('home-location-entry')
        .onClick(() => {
          if (!this.loggedIn) {
            this.onNavigateLocationLogin()
            return
          }
          router.pushUrl({ url: 'pages/LocationPage' })
        })

        // 保持可点击搜索入口，不用会吞掉路由点击的 TextInput。
        Button({ type: ButtonType.Normal }) {
          Row({ space: SPACING.SM }) {
            Image($r('app.media.home_search')).width(HomeTheme.SEARCH_ICON).height(HomeTheme.SEARCH_ICON)
              .accessibilityLevel('no')
            Text('搜索美食、店铺')
              .fontSize(FONT_SIZE.MD).fontColor(HomeTheme.MUTED)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          }
          .width('100%')
        }
          .attributeModifier(new AppButtonStyle())
        .width('100%').height(HomeTheme.SEARCH_HEIGHT)
        .padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(HomeTheme.INPUT).borderRadius(HomeTheme.CONTROL_RADIUS)
        .animation(AppMotion.pressAnimation())
        .id('home-search-entry')
        .onClick(() => { router.pushUrl({ url: 'pages/SearchPage' }) })
      }
      .width('100%')
      .padding({ left: SPACING.XL, right: SPACING.XL, top: SPACING.SM, bottom: SPACING.LG })
      .backgroundColor(HomeTheme.SURFACE)
      .opacity(this.isHeaderVisible ? 1 : 0)
      .translate({ y: this.isHeaderVisible || this.reduceMotion ? 0 : 8 })
      .animation({ duration: this.reduceMotion ? 0 : AppMotion.ENTER, curve: Curve.EaseOut })

      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll() {
          Column() {
            // 分类导航
          Grid() {
            ForEach(this.categories, (cat: Category, index: number) => {
              GridItem() {
                Column({ space: SPACING.XS }) {
                  Stack() {
                    Image(this.getCategoryIcon(cat))
                      .width(HomeTheme.CATEGORY_SIZE - SPACING.SM * 2)
                      .height(HomeTheme.CATEGORY_SIZE - SPACING.SM * 2)
                      .accessibilityLevel('no')
                  }
                  .width(HomeTheme.CATEGORY_SIZE).height(HomeTheme.CATEGORY_SIZE)
                  .backgroundColor(HomeTheme.SOFT)
                  .borderRadius(HomeTheme.CONTROL_RADIUS)
                  Text(cat.name)
                    .fontSize(FONT_SIZE.SM)
                    .fontColor(this.currentCategory === cat.id ? HomeTheme.ACCENT : HomeTheme.TEXT)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%').textAlign(TextAlign.Center)
                    .fontWeight(this.currentCategory === cat.id ? FontWeight.Bold : FontWeight.Normal)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .onClick(() => {
                  this.openProductList('category', cat.id, `${cat.name}店铺`)
                })
              }
            }, (item: Category) => item.id.toString())
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
          .rowsTemplate(this.getCategoryRowsTemplate())
          .columnsGap(0)
          .rowsGap(4)
          .width('100%')
          .height(this.getCategoryGridHeight())
          .padding({ top: SPACING.MD, bottom: SPACING.SM })
          .backgroundColor(HomeTheme.CARD)
          .margin({ top: SPACING.SM })
          .borderRadius({ topLeft: BORDER_RADIUS.LG, topRight: BORDER_RADIUS.LG })

          // 参考 sample_in_harmonyos BannerCard：仅可见且有多项时自动播放。
          if (this.banners.length > 0) {
            Swiper() {
              ForEach(this.banners, (banner: Banner) => {
                this.BannerCard(banner)
              }, (banner: Banner) => banner.id.toString())
            }
            .indicator(this.banners.length > 1 ? Indicator.dot()
              .itemWidth(6).itemHeight(6).selectedItemWidth(18).selectedItemHeight(6)
              .color(AppTheme.BORDER).selectedColor(AppTheme.ACCENT).bottom(0) : false)
            .autoPlay(this.bannerVisible && !this.reduceMotion && this.banners.length > 1)
            .interval(5000).loop(this.banners.length > 1)
            .duration(this.reduceMotion ? 0 : AppMotion.ENTER)
            .itemSpace(SPACING.SM).prevMargin(SPACING.LG).nextMargin(SPACING.LG)
            .width('100%').height(160)
            .margin({ top: SPACING.SM })
            .onVisibleAreaChange([0, 0.5], (visible: boolean, ratio: number) => {
              this.bannerVisible = visible && ratio >= 0.5
            })
          }

          // 平台公告
          if (this.announcements.length > 0) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: SPACING.SM }) {
                Image($r('app.media.home_announcement')).width(HomeTheme.SEARCH_ICON).height(HomeTheme.SEARCH_ICON)
                  .accessibilityLevel('no')
                Text(this.announcements[0].title)
                  .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED)
                  .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
            }
            .attributeModifier(new AppButtonStyle())
            .width('100%').constraintSize({ minHeight: HomeTheme.SEARCH_HEIGHT })
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
            .backgroundColor(Color.Transparent)
            .id('home-announcement-entry')
            .accessibilityGroup(true).accessibilityText(`查看公告：${this.announcements[0].title}`)
            .animation(AppMotion.pressAnimation())
            .onClick(() => {
              this.selectedAnnouncement = this.announcements[0]
              this.showAnnouncementSheet = true
            })
          }

          // 快捷入口
          Row({ space: SPACING.SM }) {
            ForEach([
              QuickEntryItem.create($r('app.media.home_clock'), '限时抢购'),
              QuickEntryItem.create($r('app.media.home_heart'), '收藏夹'),
              QuickEntryItem.create($r('app.media.home_coupon'), '领券中心'),
              QuickEntryItem.create($r('app.media.home_trophy'), '排行榜'),
            ], (item: QuickEntryItem) => {
              Column({ space: SPACING.SM }) {
                Stack() {
                  Image(item.icon)
                    .width(HomeTheme.ICON).height(HomeTheme.ICON)
                    .accessibilityLevel('no')
                }
                .width(HomeTheme.ENTRY_SIZE).height(HomeTheme.ENTRY_SIZE)
                .backgroundColor(HomeTheme.SOFT)
                .borderRadius(HomeTheme.CONTROL_RADIUS)
                Text(item.title)
                  .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.TEXT)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .padding({ top: SPACING.SM, bottom: SPACING.SM })
              .accessibilityGroup(true).accessibilityText(item.title)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                if (item.title === '收藏夹') {
                  router.pushUrl({ url: 'pages/FavoriteListPage' })
                } else if (item.title === '领券中心') {
                  router.pushUrl({ url: 'pages/CouponCenterPage' })
                } else if (item.title === '排行榜') {
                  // 榜单：店铺榜 / 菜品热销榜（服务端按月销量与评分排序）
                  router.pushUrl({ url: 'pages/RankingPage' })
                } else {
                  this.openProductList('special', 0, `${item.title}商品`)
                }
              })
            }, (item: QuickEntryItem) => item.title)
          }
          .width('100%')
          .padding({ left: SPACING.XL, right: SPACING.XL })
          .margin({ top: SPACING.MD })
          .justifyContent(FlexAlign.SpaceAround)

          // 限时秒杀：服务端时间窗口内的活动，倒计时结束或名额售罄后自动从列表消失
          if (this.seckills.length > 0) {
            Row({ space: SPACING.SM }) {
              Image($r('app.media.home_bolt')).width(HomeTheme.ICON).height(HomeTheme.ICON)
                .accessibilityLevel('no')
              Text('限时秒杀')
                .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
              Blank()
              Text('秒杀价下单自动生效')
                .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.SECKILL)
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })
            .backgroundColor(HomeTheme.SURFACE)

            Scroll() {
              Row({ space: SPACING.SM }) {
                ForEach(this.seckills, (item: SeckillItem) => {
                  this.SeckillCard(item)
                }, (item: SeckillItem) => `seckill-${item.id}`)
              }
              .padding({ left: SPACING.LG, right: SPACING.LG })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          // 附近推荐（原「发现」Tab 并入首页）：2 公里内、平台推荐位的店铺
          Row({ space: SPACING.SM }) {
            Image($r('app.media.home_location')).width(HomeTheme.ICON).height(HomeTheme.ICON)
              .accessibilityLevel('no')
            Text('附近推荐')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
              .layoutWeight(1)
            Text('刷新')
              .fontSize(FONT_SIZE.MD).fontColor(HomeTheme.ACCENT)
              .height(HomeTheme.TOUCH_HEIGHT).padding({ left: SPACING.MD, right: SPACING.MD })
              .id('home-recommend-refresh')
              .onClick(() => { this.refreshRecommended() })
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })
          .backgroundColor(HomeTheme.SURFACE)

          if (!this.loggedIn) {
            Text('登录后查看平台推荐商户')
              .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: SPACING.SM, bottom: SPACING.SM })
          } else if (!this.hasRecommendLocation()) {
            Row({ space: SPACING.SM }) {
              Text('定位后可看到附近推荐商户')
                .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED).layoutWeight(1)
              Button('去定位')
                .attributeModifier(new AppButtonStyle()).height(40).fontSize(FONT_SIZE.SM)
                .id('home-recommend-location')
                .onClick(() => { router.pushUrl({ url: 'pages/LocationPage' }) })
            }
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.SM })
          } else if (this.recommendedLoading) {
            Text('正在查询附近推荐商户…')
              .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: SPACING.SM, bottom: SPACING.SM })
          } else if (this.recommendedStores.length === 0) {
            Text('暂无附近推荐商户，平台会按距离和营业状态持续更新')
              .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: SPACING.SM, bottom: SPACING.SM })
          } else {
            GridRow({ columns: { xs: 2, sm: this.homeGridColumns },
              breakpoints: { value: ['600vp'], reference: BreakpointsReference.ComponentSize },
              gutter: { x: SPACING.SM, y: SPACING.SM } }) {
              ForEach(this.recommendedStores, (store: StoreItem) => {
                GridCol() {
                  RecommendedStoreCardHost({
                    store: store,
                    onStoreClick: (target: StoreItem) => { this.onStoreClick(target) }
                  })
                }
              }, (store: StoreItem) => `recommend-${store.id}`)
            }
            .id('home-recommend-list')
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG })
          }

          // 特价团购标题
          Row({ space: SPACING.SM }) {
            Image($r('app.media.home_tag')).width(HomeTheme.ICON).height(HomeTheme.ICON)
              .accessibilityLevel('no')
            Text('特价团购')
              .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
            Blank()
            Text('查看全部 >')
              .fontSize(FONT_SIZE.SM).fontColor(MODULE_COLOR.SPECIAL)
          }
          .width('100%')
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.SM })
          .backgroundColor(HomeTheme.SURFACE)
          .onClick(() => {
            this.openProductList('special', 0, '特价团购')
          })

          // 特价商品列表由后端数据库返回
          if (!this.loggedIn) {
            this.homeEmpty($r('app.media.home_lock'), '登录后查看特价团购', '商家上新的特价商品会展示在这里')
          } else if (this.isRefreshing && this.specialGoods.length === 0) {
            this.homeEmpty($r('app.media.home_clock'), '正在加载特价商品', '请稍候，正在读取最新团购数据')
          } else if (this.specialGoods.length === 0) {
            this.homeEmpty($r('app.media.home_bag'), '暂无特价商品', '商家上新特价商品后会展示在这里')
          } else {
            GridRow({ columns: { xs: 2, sm: this.homeGridColumns },
              breakpoints: { value: ['600vp'], reference: BreakpointsReference.ComponentSize },
              gutter: { x: SPACING.SM, y: SPACING.SM } }) {
              ForEach(this.specialGoods, (item: SpecialGoodsItem) => {
                GridCol() {
                  this.SpecialGoodsCard(item)
                }
              }, (item: SpecialGoodsItem) => `${item.goods.storeId}-${item.goods.id}`)
            }
            .id('home-special-grid')
            .width('100%')
            .padding({ left: SPACING.LG, right: SPACING.LG, bottom: SPACING.LG })
          }
          Blank().height(FloatingTabBarTheme.CONTENT_INSET + this.bottomInset)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .attributeModifier(new AppRefreshStyle())
      .onRefreshing(() => { this.refreshHomeData() })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HomeTheme.SURFACE)
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAnnouncementSheet, this.AnnouncementSheet(), {
      height: '70%',
      detents: ['70%', SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: true,
      dragBar: true,
      backgroundColor: HomeTheme.CARD,
      radius: { topLeft: AppTheme.SHEET_RADIUS, topRight: AppTheme.SHEET_RADIUS }
    })
  }

  @Builder
  AnnouncementSheet() {
    Column() {
      PageHeader({ title: '公告详情', showBack: false, topPadding: 0, headerBgColor: HomeTheme.CARD })
      Scroll() {
        Column({ space: SPACING.LG }) {
          if (this.selectedAnnouncement !== null) {
            Text(this.selectedAnnouncement.title)
              .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(HomeTheme.TEXT)
              .width('100%').id('home-announcement-title')
            if ((this.selectedAnnouncement.createTime ?? '') !== '') {
              Text(`发布时间：${this.selectedAnnouncement.createTime.replace('T', ' ')}`)
                .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED).width('100%')
            }
            Text(this.selectedAnnouncement.content)
              .fontSize(FONT_SIZE.LG).fontColor(HomeTheme.TEXT).lineHeight(26)
              .width('100%').id('home-announcement-content')
          }
        }
        .width('100%').padding(SPACING.XL).alignItems(HorizontalAlign.Start)
      }
      .width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
      Row() {
        Button('知道了')
          .attributeModifier(new AppButtonStyle())
          .width('100%').height(AppTheme.CONTROL_HEIGHT)
          .id('home-announcement-close')
          .onClick(() => { this.showAnnouncementSheet = false })
      }
      .width('100%').padding(SPACING.XL)
    }
    .width('100%').height('100%').backgroundColor(HomeTheme.CARD)
  }

  @Builder
  BannerCard(banner: Banner) {
    Column() {
      Row({ space: SPACING.MD }) {
        Column({ space: SPACING.SM }) {
          Text(banner.title).fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (banner.subtitle !== '') {
            Text(banner.subtitle).fontSize(FONT_SIZE.SM).fontColor(AppTheme.MUTED)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (banner.image !== '') {
          Image(merchantImageSource(banner.image)).alt(DEFAULT_MERCHANT_IMAGE)
            .width(88).height(88).objectFit(ImageFit.Cover).borderRadius(AppTheme.CONTROL_RADIUS)
        } else {
          Image($r('app.media.home_bowl')).width(56).height(56).objectFit(ImageFit.Contain)
            .accessibilityLevel('no')
        }
      }
      .width('100%').height(136).padding(SPACING.LG)
      .backgroundColor(AppTheme.ACCENT_SOFT).borderRadius(AppTheme.CARD_RADIUS)
      .border({ width: 1, color: AppTheme.BORDER })
    }.width('100%').height(160)
  }

  private openSpecialStore(item: SpecialGoodsItem): void {
    const storeId: number = item.goods.storeId ?? 0
    if (storeId <= 0) {
      promptAction.showToast({ message: '店铺信息暂不可用，请刷新后重试', duration: 1800 })
      return
    }
    AppStorage.setOrCreate<number>('selectedStoreId', storeId)
    AppStorage.setOrCreate<string>('selectedStoreName', item.storeName)
    router.pushUrl({ url: 'pages/StoreDetailPage' })
  }

  @Builder
  SeckillCard(item: SeckillItem) {
    Column({ space: SPACING.XS }) {
      Text(item.goodsName)
        .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: SPACING.XS }) {
        Text(`¥${item.price.toFixed(2)}`)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
        if (item.originalPrice > item.price) {
          Text(`¥${item.originalPrice.toFixed(2)}`)
            .fontSize(FONT_SIZE.XS).fontColor(HomeTheme.MUTED)
            .decoration({ type: TextDecorationType.LineThrough })
        }
      }
      .width('100%')

      // 抢购进度：已抢名额 / 总名额
      Row() {
        Text(`已抢 ${item.sold}/${item.quota}`)
          .fontSize(FONT_SIZE.XS).fontColor(HomeTheme.MUTED)
        Blank()
        Text(`${this.seckillSoldPercent(item)}%`)
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.PRICE_RED)
      }
      .width('100%')

      // 倒计时：单个页面级定时器驱动，归零后提示用户刷新（后端已结束的活动不再返回）
      Text(this.seckillRemainSeconds(item) > 0
        ? `距结束 ${this.seckillCountdown(item)}`
        : '本场已结束')
        .fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.ON_PRIMARY)
        .backgroundColor(COLORS.PRICE_RED)
        .padding({ left: SPACING.XS, right: SPACING.XS, top: 1, bottom: 1 })
        .borderRadius(BORDER_RADIUS.SM)

      Text(item.storeName)
        .fontSize(FONT_SIZE.XS).fontColor(HomeTheme.MUTED)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width(140)
    .padding(SPACING.MD)
    .backgroundColor(MODULE_BG.SECKILL)
    .borderRadius(BORDER_RADIUS.LG)
    .borderWidth(1)
    .borderColor(MODULE_COLOR.SECKILL)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => { this.openSeckillStore(item) })
  }

  @Builder
  SpecialGoodsCard(item: SpecialGoodsItem) {
    Column({ space: SPACING.SM }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(merchantImageSource(item.goods.image))
          .alt(DEFAULT_MERCHANT_IMAGE)
          .width('100%').aspectRatio(HomeTheme.GRID_IMAGE_RATIO).objectFit(ImageFit.Cover)
          .borderRadius(BORDER_RADIUS.MD)
        Text('特价')
          .fontSize(FONT_SIZE.XS).fontColor(COLORS.ON_PRIMARY)
          .backgroundColor(COLORS.PRICE_RED)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(BORDER_RADIUS.ROUND)
          .margin(SPACING.SM)
      }
      .width('100%')

      Column({ space: SPACING.XS }) {
        Text(item.goods.name)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.storeName)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.PRIMARY)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.storeDistance)
          .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text(`¥${item.goods.price.toFixed(2)}`)
            .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.PRICE_RED)
            .margin({ right: SPACING.SM })
          if (item.goods.originalPrice !== undefined && item.goods.originalPrice > item.goods.price) {
            Text(`¥${item.goods.originalPrice.toFixed(2)}`)
              .fontSize(FONT_SIZE.SM).fontColor(HomeTheme.MUTED)
              .decoration({ type: TextDecorationType.LineThrough })
          }
        }
        .width('100%')
        Text(item.goods.description)
          .fontSize(FONT_SIZE.XS).fontColor(HomeTheme.MUTED)
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(SPACING.MD).backgroundColor(MODULE_BG.SPECIAL)
    .border({ width: 1, color: AppTheme.BORDER })
    .borderRadius(BORDER_RADIUS.LG)
    .id(`home-special-card-${item.goods.storeId}-${item.goods.id}`)
    .onClick(() => { this.openSpecialStore(item) })
  }

  @Builder
  StoreCard(store: StoreItem) {
    Row({ space: SPACING.MD }) {
      // 店铺图片占位
      if (store.image !== '') {
        Image(merchantImageSource(store.image))
          .alt(DEFAULT_MERCHANT_IMAGE)
          .width(80).height(80).objectFit(ImageFit.Cover).borderRadius(BORDER_RADIUS.MD)
      } else {
        Column() {
          Text(store.name.substring(0, 1))
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLORS.ON_PRIMARY)
        }
        .width(80).height(80)
        .backgroundColor(accentFg(accentIndexFromText(store.name)))
        .borderRadius(BORDER_RADIUS.MD)
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: SPACING.XS }) {
        Text(store.name)
          .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: SPACING.SM }) {
          RatingStars({ rating: store.rating, fontSize: FONT_SIZE.SM, showNumber: true })
          Text(`月售${formatSales(store.monthlySales)}`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text('|').fontSize(FONT_SIZE.SM).fontColor(COLORS.DIVIDER)
          Text(store.deliveryTime).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }

        Row({ space: SPACING.XS }) {
          Text(`配送¥${store.deliveryFee}`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text('|').fontSize(FONT_SIZE.SM).fontColor(COLORS.DIVIDER)
          Text(`${store.minOrder}元起送`).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
          Text('|').fontSize(FONT_SIZE.SM).fontColor(COLORS.DIVIDER)
          Text(store.distance).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(store.tags, (tag: string) => {
            Text(tag)
              .fontSize(FONT_SIZE.XS).fontColor(COLORS.TAG_TEXT).backgroundColor(COLORS.TAG_BG)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(BORDER_RADIUS.ROUND)
              .margin({ top: 2 })
          }, (tag: string) => tag)
        }
        .width('100%')
        .margin({ bottom: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(SPACING.MD)
    .backgroundColor(HomeTheme.CARD)
    .borderRadius(BORDER_RADIUS.LG)
    .onClick(() => { this.onStoreClick(store) })
  }
}

// ===================== 附近推荐卡片 =====================
// 原「发现」Tab 已并入首页：推荐数据与卡片渲染都留在首页，这里只保留共享的卡片构建器
