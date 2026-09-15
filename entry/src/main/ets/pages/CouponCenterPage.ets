/**
 * 优惠券中心页面
 * 支持领取优惠券、查看我的优惠券（未使用/已使用）
 */
import { Coupon } from '../model/Models'
import { claimCouponRemote, syncCouponsRemote, getLastRemoteErrorMessage } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { logInfo } from '../service/AppLogger'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'

// Tab项 - 使用class避免无类型对象字面量
class CouponTab {
  title: string = ''
  index: number = 0
  static create(title: string, index: number): CouponTab {
    let tab = new CouponTab()
    tab.title = title
    tab.index = index
    return tab
  }
}

@Entry
@Component
export struct CouponCenterPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @StorageLink('couponList') couponList: Coupon[] = []
  @StorageLink('claimableCoupons') claimableCoupons: Coupon[] = []
  @State currentTab: number = 0  // 0=可领取, 1=我的优惠券, 2=已使用
  // 渲染路径禁止调用 getter（ArkUI 求值时序问题）：未使用/已使用在数据变化时显式计算
  @State unusedCoupons: Coupon[] = []
  @State usedCoupons: Coupon[] = []
  onBack: () => void = () => { router.back() }
  onSelectCoupon: (coupon: Coupon) => void = () => {}  // 选择优惠券回调（结算页用）

  aboutToAppear() {
    logInfo('Page', '进入优惠券中心页 CouponCenterPage')
    this.applyCouponFilter()
    // 从后端拉取最新优惠券（真实后端模式）
    if (this.loggedIn) {
      syncCouponsRemote()
    }
  }

  /** 按使用状态拆分列表（显式计算，渲染路径不调用 getter）。 */
  private applyCouponFilter(): void {
    const list: Coupon[] = Array.isArray(this.couponList) ? this.couponList : []
    this.unusedCoupons = list.filter((c: Coupon) => !c.used)
    this.usedCoupons = list.filter((c: Coupon) => c.used)
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Text('‹ 返回')
          .width(80)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { this.onBack() })
        Text('优惠券中心')
          .layoutWeight(1)
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
        Text('')
          .width(80)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: 40 })
      .backgroundColor(COLORS.BG_WHITE)

      // Tab切换
      Row({ space: 0 }) {
        ForEach([
          CouponTab.create('可领取', 0),
          CouponTab.create('我的优惠券', 1),
          CouponTab.create('已使用', 2)
        ], (tab: CouponTab) => {
          Text(tab.title)
            .fontSize(FONT_SIZE.MD)
            .fontColor(this.currentTab === tab.index ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
            .fontWeight(this.currentTab === tab.index ? FontWeight.Bold : FontWeight.Normal)
            .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.SM })
            .onClick(() => { this.currentTab = tab.index })
        }, (tab: CouponTab) => tab.index.toString())
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ top: SPACING.SM, bottom: SPACING.SM })
      .backgroundColor(COLORS.BG_WHITE)

      // 内容区（用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中）
      List({ space: SPACING.MD }) {
        if (!this.loggedIn) {
          ListItem() {
            this.EmptyView('🔒', '暂无登录', '请登录后查看优惠券')
          }
        } else if (this.currentTab === 0) {
          // 可领取优惠券
          if (this.claimableCoupons.length === 0) {
            ListItem() {
              this.EmptyView('🎁', '暂无可领取的优惠券', '')
            }
          }
          ForEach(this.claimableCoupons, (coupon: Coupon) => {
            ListItem() {
              this.CouponCard(coupon)
            }
          }, (coupon: Coupon) => coupon.id.toString())
        } else if (this.currentTab === 1) {
          // 我的优惠券（未使用的）
          if (this.unusedCoupons.length === 0) {
            ListItem() {
              this.EmptyView('🎫', '暂无可用优惠券', '去"可领取"领取优惠券吧~')
            }
          }
          ForEach(this.unusedCoupons, (coupon: Coupon) => {
            ListItem() {
              this.CouponCard(coupon)
            }
          }, (coupon: Coupon) => coupon.id.toString())
        } else {
          // 已使用
          if (this.usedCoupons.length === 0) {
            ListItem() {
              this.EmptyView('📋', '暂无已使用优惠券', '')
            }
          }
          ForEach(this.usedCoupons, (coupon: Coupon) => {
            ListItem() {
              this.CouponCard(coupon)
            }
          }, (coupon: Coupon) => coupon.id.toString())
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(COLORS.BG_PRIMARY)
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }

  // 空视图
  @Builder
  EmptyView(icon: string, title: string, desc: string) {
    Column({ space: SPACING.SM }) {
      Text(icon)
        .fontSize(60)
        .margin({ top: 80 })
      Text(title)
        .fontSize(FONT_SIZE.LG)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ top: SPACING.MD })
      if (desc !== '') {
        Text(desc)
          .fontSize(FONT_SIZE.MD)
          .fontColor(COLORS.TEXT_HINT)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 优惠券卡片
  @Builder
  CouponCard(coupon: Coupon) {
    Row() {
      // 左侧金额区
      Column({ space: 4 }) {
        Text(`¥${coupon.amount}`)
          .fontSize(FONT_SIZE.BIG_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.currentTab === 2 ? COLORS.TEXT_HINT : COLORS.TEXT_WHITE)
        Text(`满${coupon.minOrder}元可用`)
          .fontSize(FONT_SIZE.XS)
          .fontColor(this.currentTab === 2 ? COLORS.TEXT_HINT : COLORS.TEXT_WHITE)
      }
      .width(100)
      .height(80)
      .backgroundColor(this.currentTab === 2 ? COLORS.DIVIDER : COLORS.PRIMARY)
      .borderRadius({ topLeft: BORDER_RADIUS.LG, bottomLeft: BORDER_RADIUS.LG })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 右侧信息区
      Column({ space: 4 }) {
        Text(coupon.storeName ? coupon.storeName : '通用券')
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.currentTab === 2 ? COLORS.TEXT_HINT : COLORS.TEXT_PRIMARY)
        Text(coupon.condition)
          .fontSize(FONT_SIZE.SM)
          .fontColor(this.currentTab === 2 ? COLORS.TEXT_HINT : COLORS.TEXT_SECONDARY)
        Text(`有效期: ${coupon.startTime} ~ ${coupon.endTime}`)
          .fontSize(FONT_SIZE.XS)
          .fontColor(COLORS.TEXT_HINT)
      }
      .layoutWeight(1)
      .padding({ left: SPACING.MD })
      .alignItems(HorizontalAlign.Start)

      // 按钮：领取/已领取/使用/已使用
      if (this.currentTab === 0) {
        Button(this.isClaimed(coupon) ? '已领取' : '领取')
          .height(32)
          .fontSize(FONT_SIZE.SM)
          .fontColor(this.isClaimed(coupon) ? COLORS.TEXT_HINT : COLORS.TEXT_WHITE)
          .backgroundColor(this.isClaimed(coupon) ? COLORS.DIVIDER : COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .margin({ right: SPACING.MD })
          .onClick(() => { this.doClaim(coupon) })
      } else if (this.currentTab === 1) {
        Button('使用')
          .height(32)
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_WHITE)
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .margin({ right: SPACING.MD })
          .onClick(() => { this.onSelectCoupon(coupon) })
      } else {
        Text('已使用')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ right: SPACING.MD })
      }
    }
    .width('100%')
    .height(80)
    .backgroundColor(COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.LG)
  }

  // 判断是否已领取
  isClaimed(coupon: Coupon): boolean {
    return this.couponList.some((c: Coupon) => c.id === coupon.id)
  }

  // 获取未使用的优惠券
  getUnusedCoupons(): Coupon[] {
    return this.couponList.filter((c: Coupon) => !c.used)
  }

  // 获取已使用的优惠券
  getUsedCoupons(): Coupon[] {
    return this.couponList.filter((c: Coupon) => c.used)
  }

  // 领取优惠券
  async doClaim(coupon: Coupon): Promise<void> {
    if (this.isClaimed(coupon)) {
      promptAction.showToast({ message: '这张优惠券已经领取过了', duration: 1500 })
      return
    }
    // 调用后端领券（真实后端模式）
    const ok: boolean = await claimCouponRemote(coupon.storeId ?? 0, coupon.condition, coupon.minOrder, coupon.amount)
    if (!ok) {
      const errorMessage: string = getLastRemoteErrorMessage()
      promptAction.showToast({ message: errorMessage === '' ? '优惠券领取失败，请稍后重试' : errorMessage, duration: 2200 })
      return
    }
    logInfo('Coupon', `领取优惠券 couponId=${coupon.id} 金额=${coupon.amount} 门槛=${coupon.minOrder}`)

    // 从可领取列表中移除
    const claimable: Coupon[] = AppStorage.get<Coupon[]>('claimableCoupons') || []
    const newClaimable = claimable.filter((c: Coupon) => c.id !== coupon.id)
    AppStorage.setOrCreate('claimableCoupons', newClaimable)
    promptAction.showToast({ message: '优惠券领取成功', duration: 1500 })
  }
}
