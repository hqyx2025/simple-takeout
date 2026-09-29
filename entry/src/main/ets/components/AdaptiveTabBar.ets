import { motion } from '@kit.MultimodalAwarenessKit'
import { COLORS } from '../common/Constants'
import { AppButtonStyle } from '../common/theme/AppTheme'
import { FloatingNavigationMaterial, FloatingTabBarTheme } from '../common/theme/FloatingTabBarTheme'

/** 跟随系统识别的页面交互手；不支持时可手动选择导航位置。 */
@Component
export struct AdaptiveTabBar {
  @Prop selected: number = 0
  @Prop @Watch('updateListening') active: boolean = true
  @StorageLink('appForeground') @Watch('updateListening') foreground: boolean = true
  @StorageLink('appReduceMotion') reduceMotion: boolean = false
  @StorageLink('navigationHandMode') @Watch('updateListening') mode: string = 'auto'
  @State side: number = 0
  @State available: boolean = false
  @State widthVp: number = 360
  private listening: boolean = false
  private pressed: boolean = false
  private pendingSide: number = 0
  private settleTimer: number = -1
  private swipeStartIndex: number = -1
  onSelect: (index: number) => void = () => {}

  private beginSwipe(): void {
    this.swipeStartIndex = this.active && this.foreground ? this.selected : -1
  }

  private finishSwipe(offsetX: number, offsetY: number): void {
    const start: number = this.swipeStartIndex
    this.swipeStartIndex = -1
    // 每次横划只切换相邻一页；轻微抖动、竖向移动和首尾越界不切页。
    if (start < 0 || !this.active || !this.foreground || Math.abs(offsetX) < 36 ||
      Math.abs(offsetX) <= Math.abs(offsetY)) {
      return
    }
    const target: number = start + (offsetX > 0 ? 1 : -1)
    if (target >= 0 && target <= 3) { this.onSelect(target) }
  }

  private onHandChanged = (status: motion.OperatingHandStatus): void => {
    if (status !== motion.OperatingHandStatus.LEFT_HAND_OPERATED &&
      status !== motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
      return
    }
    this.pendingSide = status === motion.OperatingHandStatus.LEFT_HAND_OPERATED ? -1 : 1
    this.scheduleMove()
  }

  private scheduleMove(): void {
    clearTimeout(this.settleTimer)
    this.settleTimer = setTimeout(() => {
      this.settleTimer = -1
      if (this.listening && !this.pressed && this.active && this.foreground && this.mode === 'auto') {
        this.side = this.pendingSide
      }
    }, 450)
  }

  aboutToAppear(): void { this.updateListening() }

  updateListening(): void {
    this.stopListening()
    if (this.mode !== 'auto') {
      this.side = this.mode === 'left' ? -1 : this.mode === 'right' ? 1 : 0
      return
    }
    if (!this.active || !this.foreground || !(AppStorage.get<boolean>('privacyConsent') ?? false)) {
      return
    }
    this.pendingSide = this.side
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      this.side = 0
      return
    }
    try {
      motion.on('operatingHandChanged', this.onHandChanged)
      this.listening = true
      this.available = true
    } catch (_) {
      this.side = 0
      return
    }
    // 最近状态读取失败不影响已经成功注册的实时监听。
    try { this.onHandChanged(motion.getRecentOperatingHandStatus()) } catch (_) {}
  }

  private stopListening(): void {
    this.pressed = false
    this.available = false
    this.swipeStartIndex = -1
    clearTimeout(this.settleTimer)
    this.settleTimer = -1
    if (this.listening) {
      try { motion.off('operatingHandChanged', this.onHandChanged) } catch (_) {}
      this.listening = false
    }
  }

  aboutToDisappear(): void { this.stopListening() }

  private icon(index: number): Resource {
    if (index === 0) { return this.selected === index ? $r('app.media.home_nav_home_active') : $r('app.media.home_nav_home') }
    if (index === 1) { return this.selected === index ? $r('app.media.home_nav_assistant_active') : $r('app.media.home_nav_assistant') }
    if (index === 2) { return this.selected === index ? $r('app.media.home_nav_cart_active') : $r('app.media.home_nav_cart') }
    return this.selected === index ? $r('app.media.home_nav_profile_active') : $r('app.media.home_nav_profile')
  }

  @Builder
  tab(title: string, index: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 2 }) {
        Image(this.icon(index)).width(21).height(21).objectFit(ImageFit.Contain)
        Text(title).fontSize(11).maxLines(1)
          .fontColor(this.selected === index ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
      }.width('100%').justifyContent(FlexAlign.Center)
    }
    .attributeModifier(new AppButtonStyle()).layoutWeight(1).height(48)
    .backgroundColor(this.selected === index ? COLORS.TAG_BG : Color.Transparent)
    .borderRadius(24).id(`tab-${index}`).accessibilityText(title)
    .accessibilitySelected(this.selected === index)
    .onClick(() => { this.onSelect(index) })
  }

  build() {
    Column() {
      Stack() {
      Row() {}
        .width('100%').height('100%')
        .backgroundEffect({ radius: 20, saturation: 1.1, color: $r('app.color.navigation_glass') })
        .borderRadius(30).hitTestBehavior(HitTestMode.None)
      Row({ space: 2 }) {
        this.tab('首页', 0)
        this.tab('AI助手', 1)
        this.tab('购物车', 2)
        this.tab('我的', 3)
        Button('⋯').fontSize(20).fontColor(COLORS.TEXT_SECONDARY)
          .height(44).width(28).padding(0).backgroundColor(Color.Transparent).id('navigation-position')
          .accessibilityText('调整导航位置')
          .bindMenu([
            { value: this.mode !== 'auto' || this.available ? '跟随交互手 · 自动' : '交互手感知 · 当前不可用', action: () => { this.mode = 'auto' } },
            { value: '靠左，方便左手', action: () => { this.mode = 'left' } },
            { value: '靠右，方便右手', action: () => { this.mode = 'right' } },
            { value: '居中', action: () => { this.mode = 'center' } }
          ])
      }
      .padding(4).width('100%').height('100%')
      .attributeModifier(new FloatingNavigationMaterial()).borderRadius(30)
      }
      .height(FloatingTabBarTheme.HEIGHT)
      .width(Math.min(FloatingTabBarTheme.WIDTH, this.widthVp - 24))
      .borderRadius(30).border({ width: 0.5, color: COLORS.DIVIDER })
      .shadow({ radius: 12, color: '#18000000', offsetY: 3 })
      .translate({ x: this.side * Math.max(0, (this.widthVp - FloatingTabBarTheme.WIDTH) / 2 - 12) })
      .animation({ duration: this.reduceMotion ? 0 : 280, curve: Curve.EaseOut })
      .id('adaptive-navigation')
      .priorityGesture(
        PanGesture({ direction: PanDirection.Horizontal, fingers: 1, distance: 12 })
          .onActionStart(() => { this.beginSwipe() })
          .onActionEnd((event: GestureEvent) => { this.finishSwipe(event.offsetX, event.offsetY) })
          .onActionCancel(() => { this.swipeStartIndex = -1 })
      )
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressed = true }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false
          this.scheduleMove()
        }
      })
    }.width('100%').height(FloatingTabBarTheme.CONTENT_INSET)
    .justifyContent(FlexAlign.End).padding({ bottom: FloatingTabBarTheme.BOTTOM_MARGIN })
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((_: Area, area: Area) => { this.widthVp = Number(area.width) })
  }
}
