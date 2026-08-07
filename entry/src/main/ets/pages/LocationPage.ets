/**
 * 选择位置页面
 * 功能：
 * 1. 顶部展示高德地图，支持拖动/双指缩放选点，地图中心固定位置图标，中心即所选位置
 * 2. 进入页面自动实时定位手机当前位置（系统定位 + 高德逆地理编码），地图中心移动到定位点
 * 3. 支持关键词搜索地点并在地图上联动定位
 * 4. 与主页双向绑定：进入时回显已保存的定位地址，选择后写回主页配送地址
 */
import { Address } from '../model/Models'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { GeoPosition, SearchPlace, getCurrentPosition, reverseGeocode, searchPlaces } from '../service/LocationService'
import { EmptyState } from '../components/EmptyState'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import router from '@ohos.router'
import { logInfo } from '../service/AppLogger'
import {
  AMap,
  MapView,
  MapViewComponent,
  MapViewManager,
  MapViewCreateCallback,
  CameraPosition,
  LatLng,
  OnCameraChangeListener,
  CameraUpdateFactory,
  UiSettings
} from '@amap/amap_lbs_map3d'

// 地图视图名称（与 MapViewComponent 的 mapViewName 一致）
const MAP_VIEW_NAME: string = 'LocationMapView'
// 默认缩放级别（城市级到街道级之间）
const DEFAULT_MAP_ZOOM: number = 16

@Entry
@Component
export struct LocationPage {
  // 地图对象
  private mapView: MapView | undefined = undefined
  private aMap: AMap | undefined = undefined
  @State isMapReady: boolean = false
  // 定位状态
  @State isLocating: boolean = false
  @State currentAddressText: string = ''        // 地图中心/当前定位的地址文本
  @State currentPosition: GeoPosition | null = null  // 地图中心坐标（即用户选择的坐标）
  @State locateError: string = ''
  // 双向绑定：进入页面时主页已有的定位地址坐标
  private savedPosition: GeoPosition | null = null
  // 逆地理编码节流
  private lastResolvePos: GeoPosition | null = null
  private isResolving: boolean = false
  // 搜索状态
  @State keyword: string = ''
  @State isSearching: boolean = false
  @State searchResults: SearchPlace[] = []
  @State searched: boolean = false
  // 选中的搜索结果
  @State selectedPlace: SearchPlace | null = null

  // 地图创建回调（由 MapViewComponent 触发，需要 mapViewName 匹配）
  private mapViewCreateCallback: MapViewCreateCallback = (mapview: MapView | undefined, mapViewName: string | undefined) => {
    if (!mapview || mapViewName !== MAP_VIEW_NAME) {
      return
    }
    this.mapView = mapview
    this.mapView.onCreate()
    this.mapView.getMapAsync((map: AMap) => {
      this.aMap = map
      this.isMapReady = true
      this.setupMapListeners()
      this.applyMapSettings()
      this.initialMapCenter()
      logInfo('LocationPage', '高德地图加载完成')
    })
  }

  aboutToAppear() {
    // 双向绑定：读取主页已有的定位地址（含经纬度），作为地图初始中心回显
    const saved: Address | null = AppStorage.get<Address>('currentAddress') ?? null
    if (saved !== null && saved.latitude !== undefined && saved.longitude !== undefined) {
      this.savedPosition = { latitude: saved.latitude, longitude: saved.longitude }
      logInfo('LocationPage', '回显已保存定位地址')
    }
    // 注册地图创建回调
    MapViewManager.getInstance().registerMapViewCreatedCallback(this.mapViewCreateCallback)
    // 实时定位手机当前位置
    this.locateCurrent()
  }

  aboutToDisappear() {
    MapViewManager.getInstance().unregisterMapViewCreatedCallback(this.mapViewCreateCallback)
    if (this.mapView !== undefined) {
      this.mapView.onDestroy()
      this.mapView = undefined
      this.aMap = undefined
    }
  }

  // 相机监听：拖动/缩放地图结束后，地图中心即用户选择的位置，自动解析地址
  private setupMapListeners(): void {
    if (this.aMap === undefined) {
      return
    }
    const aMap: AMap = this.aMap as AMap
    aMap.setOnCameraChangeListener(new OnCameraChangeListener(
      (position: CameraPosition) => {
        // 相机移动中：不做处理
      },
      (position: CameraPosition) => {
        // 相机移动结束：解析地图中心地址
        const target: LatLng = position.target
        const pos: GeoPosition = { latitude: target.latitude, longitude: target.longitude }
        this.updateCenterAddress(pos)
      }
    ))
  }

  // 地图UI设置：保留缩放控件与缩放手势，禁用旋转/倾斜（保持地图端正便于选点）
  private applyMapSettings(): void {
    const uiSettings: UiSettings | undefined = this.aMap?.getUiSettings()
    if (uiSettings !== undefined) {
      uiSettings.setZoomControlsEnabled(true)
      uiSettings.setCompassEnabled(false)
      uiSettings.setScaleControlsEnabled(false)
      uiSettings.setRotateGesturesEnabled(false)
      uiSettings.setTiltGesturesEnabled(false)
    }
  }

  // 初始地图中心：已有定位地址(双向绑定) > 本次实时定位 > 默认（并提示未定位）
  private initialMapCenter(): void {
    let target: GeoPosition | null = null
    if (this.savedPosition !== null) {
      target = this.savedPosition
    } else if (this.currentPosition !== null) {
      target = this.currentPosition
    }
    if (target === null) {
      this.locateError = '未定位，请点击"重新定位"或拖动地图选择位置'
      return
    }
    this.moveMapCenter(target)
  }

  // 移动地图中心到指定坐标（相机移动结束后自动触发地址解析）
  private moveMapCenter(pos: GeoPosition): void {
    if (this.aMap === undefined) {
      return
    }
    const aMap: AMap = this.aMap as AMap
    const latLng: LatLng = new LatLng(pos.latitude, pos.longitude)
    aMap.moveCamera(CameraUpdateFactory.newLatLngZoom(latLng, DEFAULT_MAP_ZOOM))
  }

  // 根据地图中心坐标逆地理编码更新地址文本（带节流，避免频繁请求）
  private async updateCenterAddress(pos: GeoPosition): Promise<void> {
    this.currentPosition = pos
    if (this.isResolving) {
      return
    }
    const last: GeoPosition | null = this.lastResolvePos
    if (last !== null && Math.abs(last.latitude - pos.latitude) < 0.0001 && Math.abs(last.longitude - pos.longitude) < 0.0001) {
      return
    }
    this.isResolving = true
    this.lastResolvePos = pos
    try {
      const text: string = await reverseGeocode(pos)
      this.currentAddressText = text
      this.locateError = ''
      logInfo('LocationPage', `地图中心地址解析成功: ${text}`)
    } catch (err) {
      if (this.currentAddressText === '') {
        this.locateError = '地址解析失败，请拖动地图后重试'
      }
    }
    this.isResolving = false
  }

  // 定位当前手机实时位置（成功后地图中心自动移动到定位点）
  private async locateCurrent(): Promise<void> {
    this.isLocating = true
    this.locateError = ''
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const position: GeoPosition = await getCurrentPosition(context)
      this.currentPosition = position
      if (this.isMapReady) {
        this.moveMapCenter(position)
      }
      logInfo('LocationPage', '定位当前位置成功')
    } catch (err) {
      let msg: string = ''
      if (err instanceof Error) {
        msg = err.message
      }
      this.locateError = msg !== '' ? msg : '定位失败，请拖动地图或手动搜索选择位置'
    }
    this.isLocating = false
  }

  // 按关键词搜索地点
  private async doSearch(): Promise<void> {
    const kw: string = this.keyword.trim()
    if (kw === '') {
      this.searchResults = []
      this.searched = false
      return
    }
    this.isSearching = true
    try {
      const results: SearchPlace[] = await searchPlaces(kw, this.currentPosition !== null ? this.currentPosition : undefined)
      this.searchResults = results
      this.searched = true
    } catch (err) {
      this.searchResults = []
      this.searched = true
      promptAction.showToast({ message: '搜索失败，请检查网络或API Key配置', duration: 2000 })
    }
    this.isSearching = false
  }

  // 选中搜索结果：高亮并将地图中心移动到该地点（相机回调自动更新地址）
  private selectPlace(place: SearchPlace): void {
    this.selectedPlace = place
    const pos: GeoPosition = { latitude: place.latitude, longitude: place.longitude }
    this.moveMapCenter(pos)
  }

  // 使用当前地图中心位置作为配送地址
  private useCenterPosition(): void {
    if (this.currentPosition === null) {
      promptAction.showToast({ message: '请先定位或拖动地图选择位置', duration: 1500 })
      return
    }
    const pos: GeoPosition = this.currentPosition as GeoPosition
    const detail: string = this.selectedPlace !== null ? (this.selectedPlace as SearchPlace).name : ''
    const addressText: string = this.currentAddressText !== ''
      ? this.currentAddressText
      : `(${pos.latitude.toFixed(6)}, ${pos.longitude.toFixed(6)})`
    this.applyAddress(addressText, detail, pos)
  }

  // 保存配送地址并返回（含经纬度，支持双向绑定回显）
  private applyAddress(addressText: string, detail: string, pos: GeoPosition): void {
    const addr: Address = {
      id: 0,
      name: '当前位置',
      phone: '',
      address: addressText,
      detail: detail,
      isDefault: false,
      tag: '定位',
      latitude: pos.latitude,
      longitude: pos.longitude
    }
    AppStorage.setOrCreate<Address>('currentAddress', addr)
    logInfo('LocationPage', `已选择配送地址: ${addressText} ${detail}`)
    router.back()
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('‹')
          .fontSize(FONT_SIZE.XXL)
          .fontColor(COLORS.TEXT_PRIMARY)
          .onClick(() => { router.back() })
        Text('选择位置')
          .fontSize(FONT_SIZE.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('‹')
          .fontSize(FONT_SIZE.XXL)
          .fontColor(Color.Transparent)
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.LG, right: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)

      // 地图区域：拖动/缩放地图，中心图标即所选位置
      Stack() {
        MapViewComponent({ mapViewName: MAP_VIEW_NAME })
          .width('100%')
          .height('100%')

        // 顶部操作提示
        Text('拖动地图或双指缩放，中心图标即为所选位置')
          .fontSize(FONT_SIZE.SM)
          .fontColor(COLORS.TEXT_PRIMARY)
          .backgroundColor('rgba(255,255,255,0.92)')
          .padding({ left: SPACING.MD, right: SPACING.MD, top: 5, bottom: 5 })
          .borderRadius(BORDER_RADIUS.ROUND)
          .position({ x: 16, y: 12 })

        // 中心位置图标（固定在地图中间，跟随地图中心）
        Column() {
          Text('📍')
            .fontSize(32)
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(300)
      .backgroundColor(COLORS.BG_WHITE)
      .clip(true)

      Scroll() {
        Column({ space: SPACING.MD }) {
          // 当前位置卡片（显示地图中心解析出的地址）
          Column({ space: SPACING.SM }) {
            Row() {
              Text('📍')
                .fontSize(FONT_SIZE.XL)
              Text('当前选择')
                .fontSize(FONT_SIZE.LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
                .margin({ left: SPACING.SM })
              Blank()
              Text('重新定位')
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.PRIMARY)
                .onClick(() => { this.locateCurrent() })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.isLocating) {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(COLORS.PRIMARY)
                Text('正在定位当前实时位置...')
                  .fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.TEXT_HINT)
                  .margin({ left: SPACING.SM })
              }
              .width('100%')
            } else if (this.currentAddressText !== '') {
              Text(this.currentAddressText)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')
              Button(this.selectedPlace !== null ? '使用所选位置' : '使用地图中心位置')
                .width('100%')
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.useCenterPosition() })
            } else {
              Text(this.locateError !== '' ? this.locateError : '正在加载地图...')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.ERROR)
                .width('100%')
            }
          }
          .width('100%')
          .padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
          .alignItems(HorizontalAlign.Start)

          // 搜索区域
          Column({ space: SPACING.SM }) {
            Row({ space: SPACING.SM }) {
              TextInput({ placeholder: '搜索地点，如：中关村', text: this.keyword })
                .layoutWeight(1)
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .onChange((value: string) => { this.keyword = value })
                .onSubmit(() => { this.doSearch() })
              Button('搜索')
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.doSearch() })
            }
            .width('100%')

            if (!this.searched && this.searchResults.length === 0) {
              Text('可直接拖动地图选点，或搜索后选择一个地点作为配送地址')
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.TEXT_HINT)
                .width('100%')
            }

            if (this.isSearching) {
              Column() {
                LoadingProgress()
                  .width(32)
                  .height(32)
                  .color(COLORS.PRIMARY)
                Text('搜索中...')
                  .fontSize(FONT_SIZE.MD)
                  .fontColor(COLORS.TEXT_HINT)
                  .margin({ top: SPACING.SM })
              }
              .width('100%')
              .padding({ top: SPACING.XL, bottom: SPACING.XL })
            } else if (this.searchResults.length > 0) {
              List({ space: SPACING.XS }) {
                ForEach(this.searchResults, (place: SearchPlace) => {
                  ListItem() {
                    Row({ space: SPACING.SM }) {
                      Text(this.selectedPlace === place ? '📍' : '📌')
                        .fontSize(FONT_SIZE.MD)
                      Column({ space: 2 }) {
                        Text(place.name)
                          .fontSize(FONT_SIZE.MD)
                          .fontColor(this.selectedPlace === place ? COLORS.PRIMARY : COLORS.TEXT_PRIMARY)
                          .fontWeight(this.selectedPlace === place ? FontWeight.Bold : FontWeight.Normal)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(place.district !== '' ? `${place.district} ${place.address}` : place.address)
                          .fontSize(FONT_SIZE.SM)
                          .fontColor(COLORS.TEXT_HINT)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      if (this.selectedPlace === place) {
                        Text('✓')
                          .fontSize(FONT_SIZE.LG)
                          .fontColor(COLORS.PRIMARY)
                      }
                    }
                    .width('100%')
                    .padding(SPACING.MD)
                    .backgroundColor(this.selectedPlace === place ? '#FFF3E0' : COLORS.BG_WHITE)
                    .borderRadius(BORDER_RADIUS.MD)
                    .onClick(() => { this.selectPlace(place) })
                  }
                }, (place: SearchPlace) => `${place.name}|${place.district}|${place.address}`)
              }
              .width('100%')
              .divider({ strokeWidth: 0 })
              .scrollBar(BarState.Off)
            } else if (this.searched) {
              EmptyState({ icon: '🔍', title: '未找到相关地点', description: '换个关键词再试试' })
            }
          }
          .width('100%')
          .padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}
