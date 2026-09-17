/**
 * 骑手中心（四端改造）：上线/下线、配送统计、入口
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Rider, Address } from '../model/Models'
import { fetchRiderProfileRemote, logout, setRiderStatusRemote } from '../service/AppStorageManager'
import { updateRiderRadiusApi, updateRiderLocationApi } from '../service/ApiService'
import { GeoPosition, getCurrentPosition, requestLocationPermission } from '../service/LocationService'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { logInfo } from '../service/AppLogger'
import { common } from '@kit.AbilityKit'

/** 骑手配送半径的软阈值（公里）：低于/高于会先弹确认框，服务端仍接受 */
const RIDER_RADIUS_DEFAULT_KM: number = 25
const RIDER_RADIUS_MIN_KM: number = 5
const RIDER_RADIUS_MAX_KM: number = 50

@Entry
@Component
export struct RiderCenterPage {
  @StorageLink('isLoggedIn') loggedIn: boolean = false
  @State rider: Rider | null = null
  @State loading: boolean = false
  @State toggling: boolean = false
  // 接单范围：半径（公里输入）+ 接单位置
  @State radiusInput: string = `${RIDER_RADIUS_DEFAULT_KM}`
  @State savingRadius: boolean = false
  @State updatingLocation: boolean = false
  @State showRadiusConfirm: boolean = false
  @State radiusConfirmText: string = ''
  @State pendingRadiusMeters: number = 0

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入骑手中心 RiderCenterPage')
    if (this.loggedIn) {
      await this.loadProfile()
    }
  }

  async onPageShow(): Promise<void> {
    // 从地图选点返回：把选好的接单位置写回服务端
    const picked: Address | null = AppStorage.get<Address>('pickedRiderLocation') ?? null
    if (picked !== null) {
      AppStorage.setOrCreate<Address | null>('pickedRiderLocation', null)
      await this.saveLocation(picked.latitude ?? 0, picked.longitude ?? 0,
        `${picked.address ?? ''} ${picked.detail ?? ''}`.trim())
    }
  }

  private async loadProfile(): Promise<void> {
    this.loading = true
    this.rider = await fetchRiderProfileRemote()
    this.loading = false
    if (this.rider !== null) {
      const radiusMeters: number = this.rider.deliveryRadius ?? 0
      const km: number = radiusMeters > 0 ? radiusMeters / 1000 : RIDER_RADIUS_DEFAULT_KM
      this.radiusInput = `${km}`
    }
  }

  /** 当前生效半径（公里）：未设置时用默认 25 公里。 */
  private effectiveRadiusKm(): number {
    const radiusMeters: number = this.rider === null ? 0 : (this.rider.deliveryRadius ?? 0)
    return radiusMeters > 0 ? radiusMeters / 1000 : RIDER_RADIUS_DEFAULT_KM
  }

  private hasRiderLocation(): boolean {
    if (this.rider === null) {
      return false
    }
    const latitude: number | undefined = this.rider.latitude
    const longitude: number | undefined = this.rider.longitude
    return latitude !== undefined && longitude !== undefined
      && Number.isFinite(latitude) && Number.isFinite(longitude) && !(latitude === 0 && longitude === 0)
  }

  /** 保存半径：<5 公里 / >50 公里先弹确认（"不推荐太小哦，可能会无单可抢"）。 */
  private onSaveRadius(): void {
    const km: number = Number(this.radiusInput.trim())
    if (!Number.isFinite(km) || km <= 0) {
      promptAction.showToast({ message: '请输入有效的配送半径（公里）', duration: 2000 })
      return
    }
    const meters: number = Math.round(km * 1000)
    if (km < RIDER_RADIUS_MIN_KM) {
      this.radiusConfirmText = `不推荐太小哦，可能会无单可抢，您真的要选择吗？（当前 ${km} 公里）`
      this.pendingRadiusMeters = meters
      this.showRadiusConfirm = true
      return
    }
    if (km > RIDER_RADIUS_MAX_KM) {
      this.radiusConfirmText = `半径超过 ${RIDER_RADIUS_MAX_KM} 公里，可能会接到很远的单，确定要设置吗？（当前 ${km} 公里）`
      this.pendingRadiusMeters = meters
      this.showRadiusConfirm = true
      return
    }
    this.saveRadius(meters)
  }

  private async saveRadius(radiusMeters: number): Promise<void> {
    if (this.savingRadius) {
      return
    }
    this.savingRadius = true
    const updated: Rider | null = await updateRiderRadiusApi(radiusMeters)
    this.savingRadius = false
    if (updated === null) {
      promptAction.showToast({ message: '配送半径保存失败，请重试', duration: 2200 })
      return
    }
    this.rider = updated
    promptAction.showToast({ message: `配送半径已设为 ${radiusMeters / 1000} 公里`, duration: 1800 })
  }

  /** 地图选点设置接单位置（抢单圆心）。 */
  private openRiderLocationPicker(): void {
    AppStorage.setOrCreate<boolean>('riderLocationPickMode', true)
    router.pushUrl({ url: 'pages/LocationPage' })
  }

  /** 用设备当前定位设置接单位置。 */
  private async useCurrentLocation(): Promise<void> {
    if (this.updatingLocation) {
      return
    }
    this.updatingLocation = true
    try {
      const context: common.UIAbilityContext | undefined =
        AppStorage.get<common.UIAbilityContext>('appContext')
      if (context === undefined) {
        promptAction.showToast({ message: '定位服务不可用，请稍后重试', duration: 2000 })
        return
      }
      const granted: boolean = await requestLocationPermission(context)
      if (!granted) {
        promptAction.showToast({ message: '未获得定位权限，可在设置里开启或用地图选点', duration: 2500 })
        return
      }
      const position: GeoPosition = await getCurrentPosition(context)
      await this.saveLocation(position.latitude, position.longitude, '我的当前位置')
    } finally {
      this.updatingLocation = false
    }
  }

  private async saveLocation(latitude: number, longitude: number, address: string): Promise<void> {
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || (latitude === 0 && longitude === 0)) {
      promptAction.showToast({ message: '接单位置无效，请重新选择', duration: 2200 })
      return
    }
    const updated: Rider | null = await updateRiderLocationApi(latitude, longitude, address)
    if (updated === null) {
      promptAction.showToast({ message: '接单位置保存失败，请重试', duration: 2200 })
      return
    }
    this.rider = updated
    promptAction.showToast({ message: '接单位置已更新', duration: 1600 })
  }

  private async toggleOnline(): Promise<void> {
    if (this.rider === null || this.toggling) {
      return
    }
    this.toggling = true
    const target: number = this.rider.online === 1 ? 0 : 1
    const updated: Rider | null = await setRiderStatusRemote(target)
    this.toggling = false
    if (updated !== null) {
      this.rider = updated
      promptAction.showToast({ message: target === 1 ? '已上线，可开始抢单' : '已下线', duration: 1500 })
    } else {
      promptAction.showToast({ message: '状态更新失败，请重试', duration: 2000 })
    }
  }

  build() {
    Stack() {
    Column() {
      Row() {
        Text('退出登录')
          .fontSize(FONT_SIZE.MD)
          .fontColor(MODULE_COLOR.RIDER)
          .layoutWeight(1)
          .onClick(() => {
            logout()
            router.replaceUrl({ url: 'pages/Index' })
          })
        Text('🛵 骑手中心')
          .fontSize(FONT_SIZE.XXL)
          .fontWeight(FontWeight.Bold)
          .fontColor(MODULE_COLOR.RIDER)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(MODULE_BG.RIDER)

      if (!this.loggedIn) {
        Column() {
          Text('🔒').fontSize(60).margin({ top: 80 })
          Text('请使用骑手账号登录').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.loading) {
        Column() {
          Text('正在加载…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.rider === null) {
        Column() {
          Text('⚠️').fontSize(60).margin({ top: 80 })
          Text('骑手档案加载失败').fontSize(FONT_SIZE.LG).fontColor(COLORS.TEXT_HINT).margin({ top: SPACING.MD })
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致内容不在顶部
        List({ space: SPACING.SM }) {
          // 上线开关
          ListItem() {
            Column({ space: SPACING.SM }) {
              Row({ space: SPACING.MD }) {
                Text(this.rider!.name.substring(0, 1))
                  .width(40).height(40).textAlign(TextAlign.Center)
                  .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
                  .fontColor(accentFg(accentIndexFromText(this.rider!.name)))
                  .backgroundColor(accentBg(accentIndexFromText(this.rider!.name)))
                  .borderRadius(BORDER_RADIUS.ROUND)
                Text(this.rider!.name)
                  .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.rider!.online === 1 })
                  .id('rider-online-toggle')
                  .onChange(() => { this.toggleOnline() })
              }
              .width('100%')
              Text(this.rider!.phone).fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              Text(this.rider!.online === 1 ? '● 在线，可抢单' : '● 离线')
                .fontSize(FONT_SIZE.SM)
                .fontColor(this.rider!.online === 1 ? COLORS.SUCCESS : COLORS.TEXT_HINT)
                .id('rider-online-status')
            }
            .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
          }

          // 统计
          ListItem() {
            Row() {
              Column({ space: SPACING.XS }) {
                Text(this.rider!.totalOrders.toString())
                  .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(accentFg(0))
                Text('累计配送').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              }.layoutWeight(1).alignItems(HorizontalAlign.Center)
              Column({ space: SPACING.XS }) {
                Text(`¥${this.rider!.totalIncome.toFixed(2)}`)
                  .fontSize(FONT_SIZE.XXL).fontWeight(FontWeight.Bold).fontColor(accentFg(2))
                Text('累计收入').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY)
              }.layoutWeight(1).alignItems(HorizontalAlign.Center)
            }
            .width('100%').padding(SPACING.LG).backgroundColor(MODULE_BG.RIDER).borderRadius(BORDER_RADIUS.LG)
          }

          // 接单范围：配送半径 + 接单位置（平台配单要求订单同时落在商家半径与骑手半径内）
          ListItem() {
            Column({ space: SPACING.SM }) {
              Text('接单范围')
                .fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold)
                .fontColor(MODULE_COLOR.RIDER).width('100%')
              Row({ space: SPACING.MD }) {
                TextInput({ placeholder: `配送半径（公里），如：${RIDER_RADIUS_DEFAULT_KM}`, text: this.radiusInput })
                  .layoutWeight(1).height(44).type(InputType.Number)
                  .id('rider-radius-input')
                  .onChange((v: string) => { this.radiusInput = v })
                Button(this.savingRadius ? '保存中...' : '保存半径')
                  .height(44).fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.RIDER)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .id('rider-radius-save')
                  .onClick(() => { this.onSaveRadius() })
              }
              .width('100%')
              Text(`当前生效半径 ${this.effectiveRadiusKm()} 公里（未设置按默认 ${RIDER_RADIUS_DEFAULT_KM} 公里）`)
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
                .id('rider-radius-value')

              Text('接单位置（抢单圆心，未设置则抢不到单）')
                .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
              Text(this.hasRiderLocation()
                ? `已设置：${this.rider!.locationAddress !== '' ? this.rider!.locationAddress : '地图选点'}`
                : '未设置：请用地图选点或当前定位')
                .fontSize(FONT_SIZE.SM)
                .fontColor(this.hasRiderLocation() ? COLORS.SUCCESS : COLORS.ERROR)
                .width('100%').id('rider-location-value')
              Row({ space: SPACING.MD }) {
                Button('地图选点')
                  .layoutWeight(1).height(40).fontSize(FONT_SIZE.SM)
                  .fontColor(MODULE_COLOR.RIDER).backgroundColor(MODULE_BG.RIDER)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .id('rider-location-map')
                  .onClick(() => { this.openRiderLocationPicker() })
                Button(this.updatingLocation ? '定位中...' : '使用当前定位')
                  .layoutWeight(1).height(40).fontSize(FONT_SIZE.SM)
                  .fontColor(MODULE_COLOR.RIDER).backgroundColor(MODULE_BG.RIDER)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .id('rider-location-gps')
                  .onClick(() => { this.useCurrentLocation() })
              }
              .width('100%')
            }
            .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
          }

          ListItem() {
            Column() {
              Button('抢单大厅')
                .width('100%').height(48).fontSize(FONT_SIZE.LG)
                .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.RIDER)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .margin({ top: SPACING.MD })
                .id('rider-pool-entry')
                .onClick(() => {
                  if (this.rider!.online === 1) {
                    router.pushUrl({ url: 'pages/RiderOrderPoolPage' })
                  }
                  else {
                    promptAction.showToast({ message: '请先上线', duration: 1500 })
                  }
                })

              Button('我的配送单')
                .width('100%').height(48).fontSize(FONT_SIZE.LG)
                .fontColor(MODULE_COLOR.RIDER).backgroundColor(MODULE_BG.RIDER)
                .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                .id('rider-orders-entry')
                .onClick(() => { router.pushUrl({ url: 'pages/RiderOrdersPage' }) })
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1).scrollBar(BarState.Off)
        .padding(SPACING.LG)
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

      if (this.showRadiusConfirm) {
        ConfirmDialog({
          title: '确认配送半径',
          content: this.radiusConfirmText,
          confirmText: '仍要选择',
          cancelText: '改一下',
          onConfirm: () => {
            this.showRadiusConfirm = false
            this.saveRadius(this.pendingRadiusMeters)
          },
          onCancel: () => { this.showRadiusConfirm = false }
        })
      }
    }
    .width('100%').height('100%')
  }
}
