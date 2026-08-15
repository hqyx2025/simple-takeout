/**
 * 选择位置页面
 * 功能：
 * 1. 顶部展示高德地图（Web端JS API + Web组件，无native so，模拟器/真机均可运行）
 * 2. 支持拖动/双指缩放选点，地图中心固定位置图标，中心即所选位置（JS内逆地理编码自动解析地址）
 * 3. 进入页面自动实时定位手机当前位置，地图中心移动到定位点
 * 4. 支持关键词搜索地点并在地图上联动定位
 * 5. 与主页双向绑定：进入时回显已保存的定位地址，选择后写回主页配送地址
 */
import { Address, User } from '../model/Models'
import { isLoggedIn } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { AddressSearchResult, GeoPosition, getCurrentPosition, reverseGeocodePosition, searchAddress } from '../service/LocationService'
import { EmptyState } from '../components/EmptyState'
import { common } from '@kit.AbilityKit'
import { webview } from '@kit.ArkWeb'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'
import { saveAllData } from '../service/DataPersistence'

// 搜索结果地点（高德输入提示，经JS桥回传）
class SearchPlace {
  name: string = ''
  district: string = ''
  address: string = ''
  latitude: number = 0
  longitude: number = 0

  static create(name: string, district: string, address: string, latitude: number, longitude: number): SearchPlace {
    const place = new SearchPlace()
    place.name = name
    place.district = district
    place.address = address
    place.latitude = latitude
    place.longitude = longitude
    return place
  }
}

// JS桥对象（javaScriptProxy 要求 class 实例，回调由组件在 aboutToAppear 中赋值）
class LocationWebBridge {
  onCenterChanged: (lngStr: string, latStr: string, address: string) => void = () => {}
  onSearchResult: (jsonStr: string) => void = () => {}
}

// javaScriptProxy 参数类型（SDK 声明为 object，ArkTS 禁止字面量，需显式 interface）
interface JavaScriptProxyOptions {
  object: Object
  name: string
  methodList: Array<string>
  controller: webview.WebviewController
}

@Entry
@Component
export struct LocationPage {
  // Web 地图
  private webController: webview.WebviewController = new webview.WebviewController()
  private webBridge: LocationWebBridge = new LocationWebBridge()
  @State isMapReady: boolean = false
  // 定位状态
  @State isLocating: boolean = false
  @State currentAddressText: string = ''        // 地图中心/当前定位的地址文本
  @State currentPosition: GeoPosition | null = null  // 地图中心坐标（即用户选择的坐标）
  @State locateError: string = ''
  @State hasNativeLocation: boolean = false
  // 双向绑定：进入页面时主页已有的定位地址坐标
  private savedPosition: GeoPosition | null = null
  private locationRequestId: number = 0
  // 地图首次加载会回调默认中心；仅忽略该初始点，用户拖动后的新中心要立即生效
  private initialMapPosition: GeoPosition | null = null
  // 搜索状态
  @State keyword: string = ''
  @State isSearching: boolean = false
  @State searchResults: SearchPlace[] = []
  @State searched: boolean = false
  // 选中的搜索结果
  @State selectedPlace: SearchPlace | null = null

  aboutToAppear() {
    if (!isLoggedIn()) {
      AppStorage.setOrCreate<boolean>('pendingLocationLoginPrompt', true)
      router.back()
      return
    }
    // JS桥回调绑定（Web页面通过 window.ohosBridge 调用）
    this.webBridge.onCenterChanged = (lngStr: string, latStr: string, address: string): void => {
      this.onCenterChangedFromJs(lngStr, latStr, address)
    }
    this.webBridge.onSearchResult = (jsonStr: string): void => {
      this.onSearchResultFromJs(jsonStr)
    }
    // 双向绑定：读取主页已有的定位地址（含经纬度），作为地图初始中心回显
    const saved: Address | null = AppStorage.get<Address>('currentAddress') ?? null
    if (saved !== null && saved.latitude !== undefined && saved.longitude !== undefined) {
      this.savedPosition = { latitude: saved.latitude, longitude: saved.longitude }
      this.currentPosition = this.savedPosition
      const savedText: string = `${saved.address} ${saved.detail}`.trim()
      this.currentAddressText = savedText
      logInfo('LocationPage', '回显已保存定位地址')
    }
    // 兼容用户仅完成定位但尚未确认地址的情况，优先回显本次会话最近一次定位结果。
    if (this.savedPosition === null) {
      const lastPosition: GeoPosition | undefined = AppStorage.get<GeoPosition>('lastLocationPosition')
      if (lastPosition !== undefined && lastPosition !== null &&
        lastPosition.latitude !== 0 && lastPosition.longitude !== 0) {
        this.savedPosition = lastPosition
        this.currentPosition = lastPosition
        logInfo('LocationPage', '回显最近一次定位坐标')
      }
    }
    // 实时定位手机当前位置
    this.locateCurrent()
  }

  // JS回调：地图中心坐标变化（拖动/缩放/定位联动触发）
  private onCenterChangedFromJs(lngStr: string, latStr: string, address: string): void {
    const lng: number = Number(lngStr)
    const lat: number = Number(latStr)
    if (Number.isNaN(lng) || Number.isNaN(lat)) {
      return
    }
    // 定位请求进行中时只忽略地图首次加载的默认中心。
    // 一旦中心坐标发生变化，说明用户已拖动地图（或正在回显已保存位置），应立即允许确认并停止等待系统定位。
    if (this.locationRequestId > 0 && !this.hasNativeLocation && this.currentPosition === null) {
      if (this.initialMapPosition === null) {
        this.initialMapPosition = { latitude: lat, longitude: lng }
        logInfo('LocationPage', `忽略地图默认中心，等待系统定位: ${lngStr}, ${latStr}`)
        return
      }
      const initial: GeoPosition = this.initialMapPosition as GeoPosition
      const initialDistance: number = Math.abs(initial.longitude - lng) + Math.abs(initial.latitude - lat)
      if (initialDistance < 0.00001) {
        return
      }
      this.locationRequestId = 0
      this.isLocating = false
      logInfo('LocationPage', '检测到地图中心已移动，使用用户手动选择的位置')
    }
    if (this.hasNativeLocation && this.currentPosition !== null) {
      const distance: number = Math.abs(this.currentPosition.longitude - lng) + Math.abs(this.currentPosition.latitude - lat)
      if (distance < 0.00001 && address === '') {
        return
      }
    }
    this.currentPosition = { latitude: lat, longitude: lng }
    if (this.selectedPlace !== null) {
      const place: SearchPlace = this.selectedPlace as SearchPlace
      const placeDistance: number = Math.abs(place.longitude - lng) + Math.abs(place.latitude - lat)
      if (placeDistance >= 0.00001) {
        this.selectedPlace = null
      }
    }
    if (address !== '') {
      this.currentAddressText = address
      this.locateError = ''
    } else {
      this.currentAddressText = ''
    }
    logInfo('LocationPage', `地图中心更新: ${lngStr}, ${latStr}, ${address}`)
  }

  // JS回调：搜索结果（JSON字符串）
  private onSearchResultFromJs(jsonStr: string): void {
    try {
      const parsed: Object = JSON.parse(jsonStr)
      const list: Array<Record<string, Object>> = parsed as Array<Record<string, Object>>
      const results: SearchPlace[] = []
      for (let i = 0; i < list.length; i++) {
        const item: Record<string, Object> = list[i]
        results.push(SearchPlace.create(
          String(item['name'] ?? ''),
          String(item['district'] ?? ''),
          String(item['address'] ?? ''),
          Number(item['lat'] ?? 0),
          Number(item['lng'] ?? 0)
        ))
      }
      this.applySearchResults(results)
      logInfo('LocationPage', `搜索结果数: ${results.length}`)
    } catch (err) {
      this.searchResults = []
      this.searched = true
      promptAction.showToast({ message: '搜索结果解析失败，请稍后重试', duration: 1800 })
    }
    this.isSearching = false
  }

  // 统一处理原生地理编码和 Web 地图搜索结果
  private applySearchResults(results: SearchPlace[]): void {
    this.searchResults = results
    this.searched = true
    // 搜索成功后直接将首个地点定位到顶部已有地图组件，避免额外创建地图。
    // 用户仍可在下方结果列表中切换到其他地点。
    if (results.length > 0) {
      const first: SearchPlace = results[0]
      this.selectedPlace = first
      this.currentPosition = { latitude: first.latitude, longitude: first.longitude }
      const firstAddress: string = first.district !== '' ? `${first.district} ${first.address}` : first.address
      this.currentAddressText = firstAddress !== '' ? firstAddress : first.name
      if (this.isMapReady) {
        this.moveMapCenter({ latitude: first.latitude, longitude: first.longitude })
      }
      promptAction.showToast({ message: `已找到${results.length}个地点，地图已定位`, duration: 1500 })
    } else {
      promptAction.showToast({ message: `未找到“${this.keyword.trim()}”相关地点，请换个关键词`, duration: 1800 })
    }
  }

  // 调用JS移动地图中心（触发moveend后JS自动逆地理编码回传地址）
  private async moveMapCenter(pos: GeoPosition): Promise<void> {
    const js: string = `moveTo(${pos.longitude.toFixed(6)}, ${pos.latitude.toFixed(6)})`
    try {
      await this.webController.runJavaScript(js)
    } catch (err) {
      logInfo('LocationPage', '调用地图JS失败（地图可能未加载完成）')
    }
  }

  // 刷新地图当前视图并重新解析中心地址
  private async refreshMap(): Promise<void> {
    if (!this.isMapReady) {
      promptAction.showToast({ message: '地图正在加载，请稍后再试', duration: 1500 })
      return
    }
    try {
      await this.webController.runJavaScript('refreshMap()')
      promptAction.showToast({ message: '地图已刷新', duration: 1200 })
    } catch (err) {
      promptAction.showToast({ message: '地图刷新失败，请稍后重试', duration: 1500 })
    }
  }

  // 构造 javaScriptProxy 配置（避免向 object 类型传对象字面量，满足 arkts-no-untyped-obj-literals）
  private getProxyOptions(): JavaScriptProxyOptions {
    const options: JavaScriptProxyOptions = {
      object: this.webBridge,
      name: 'ohosBridge',
      methodList: ['onCenterChanged', 'onSearchResult'],
      controller: this.webController
    }
    return options
  }

  // 定位当前手机实时位置（成功后地图中心自动移动到定位点）
  private async locateCurrent(): Promise<void> {
    const requestId: number = Date.now()
    this.locationRequestId = requestId
    this.isLocating = true
    this.locateError = ''
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const position: GeoPosition = await getCurrentPosition(context)
      if (this.locationRequestId !== requestId) {
        return
      }
      this.currentPosition = position
      AppStorage.setOrCreate<GeoPosition>('lastLocationPosition', position)
      // 定位成功后立即持久化，用户即使暂未点击确认，下一次进入也能回显该位置。
      saveAllData()
      this.hasNativeLocation = true
      this.currentAddressText = await reverseGeocodePosition(position)
      if (this.isMapReady) {
        await this.moveMapCenter(position)
      }
      logInfo('LocationPage', '定位当前位置成功')
    } catch (err) {
      let msg: string = ''
      if (err instanceof Error) {
        msg = err.message
      }
      this.locateError = msg !== '' ? msg : '定位失败，请拖动地图或手动搜索选择位置'
      if (this.locationRequestId === requestId) {
        this.locationRequestId = 0
      }
    }
    if (this.locationRequestId === requestId) {
      this.isLocating = false
    }
  }

  // 按关键词搜索地点（JS输入提示）
  private async doSearch(): Promise<void> {
    if (this.isSearching) {
      return
    }
    const kw: string = this.keyword.trim()
    if (kw === '') {
      this.searchResults = []
      this.searched = false
      promptAction.showToast({ message: '请输入要搜索的地点', duration: 1500 })
      return
    }
    if (!this.isMapReady) {
      promptAction.showToast({ message: '地图正在加载，请稍后再搜索', duration: 1500 })
      return
    }
    this.isSearching = true
    this.searched = false
    promptAction.showToast({ message: `正在搜索“${kw}”…`, duration: 1200 })
    const safeKw: string = kw.replace(/"/g, '').replace(/'/g, '')
    try {
      // 先走原生 HTTPS 地理编码，确保地址关键词（如“中关村”）能返回坐标。
      const nativeResults: AddressSearchResult[] = await searchAddress(kw)
      if (nativeResults.length > 0) {
        const results: SearchPlace[] = nativeResults.map((item: AddressSearchResult): SearchPlace => {
          return SearchPlace.create(item.name, item.district, item.address, item.latitude, item.longitude)
        })
        this.applySearchResults(results)
        this.isSearching = false
        return
      }
      // 原生服务无结果时，继续使用地图 WebView 的 POI/输入提示兜底。
      await this.webController.runJavaScript(`searchKeyword("${safeKw}")`)
    } catch (err) {
      this.isSearching = false
      promptAction.showToast({ message: '搜索失败，请检查网络或API Key配置', duration: 2000 })
    }
  }

  // 选中搜索结果：高亮并将地图中心移动到该地点（JS回调自动更新地址）
  private selectPlace(place: SearchPlace): void {
    this.selectedPlace = place
    this.currentPosition = { latitude: place.latitude, longitude: place.longitude }
    const placeAddress: string = place.district !== '' ? `${place.district} ${place.address}` : place.address
    this.currentAddressText = placeAddress !== '' ? placeAddress : place.name
    this.moveMapCenter({ latitude: place.latitude, longitude: place.longitude })
  }

  // 使用当前地图中心位置作为配送地址
  private async useCenterPosition(): Promise<void> {
    if (this.currentPosition === null) {
      promptAction.showToast({ message: '请先定位或拖动地图选择位置', duration: 1500 })
      return
    }
    const pos: GeoPosition = this.currentPosition as GeoPosition
    const detail: string = this.selectedPlace !== null ? (this.selectedPlace as SearchPlace).name : ''
    let addressText: string = this.currentAddressText
    if (addressText === '') {
      addressText = await reverseGeocodePosition(pos)
    }
    if (addressText === '' && this.selectedPlace !== null) {
      const place: SearchPlace = this.selectedPlace as SearchPlace
      addressText = place.district !== '' ? `${place.district} ${place.address}` : place.address
      if (addressText === '') {
        addressText = place.name
      }
    }
    if (addressText === '') {
      promptAction.showToast({ message: '正在解析当前位置，请稍后再点击确认位置', duration: 1800 })
      if (this.isMapReady) {
        await this.refreshMap()
      }
      return
    }
    this.applyAddress(addressText, detail, pos)
  }

  // 保存配送地址并返回（含经纬度，支持双向绑定回显）
  private applyAddress(addressText: string, detail: string, pos: GeoPosition): void {
    const user: User | undefined = AppStorage.get<User>('user')
    const addr: Address = {
      id: 0,
      name: user !== undefined && user !== null ? user.username : '',
      phone: user !== undefined && user !== null ? user.phone : '',
      address: addressText,
      detail: detail,
      isDefault: false,
      tag: '定位',
      latitude: pos.latitude,
      longitude: pos.longitude
    }
    AppStorage.setOrCreate<Address>('currentAddress', addr)
    AppStorage.setOrCreate<GeoPosition>('lastLocationPosition', pos)
    saveAllData()
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
        Web({ src: $rawfile('amap_map.html'), controller: this.webController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy(this.getProxyOptions())
          .onPageEnd(() => {
            this.isMapReady = true
            // 双向绑定：回显已有定位位置，否则使用本次实时定位结果
            // 高德 JS 地图在 Web 页面结束回调后还会延迟初始化，延迟调用避免 moveTo 落在 map=null 时被丢弃。
            setTimeout(() => {
              if (this.savedPosition !== null) {
                this.moveMapCenter(this.savedPosition)
              } else if (this.currentPosition !== null) {
                this.moveMapCenter(this.currentPosition)
              }
            }, 500)
          })
          .width('100%')
          .height('100%')

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
              Button('刷新地图')
                .height(32)
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.PRIMARY)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .padding({ left: SPACING.SM, right: SPACING.SM })
                .onClick(() => { this.refreshMap() })
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
            } else if (this.currentPosition !== null) {
              Text(this.currentAddressText !== '' ? this.currentAddressText : '请拖动地图中心图标选择配送位置')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')
              Button('重新定位')
                .width('100%')
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.PRIMARY)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .onClick(() => { this.locateCurrent() })
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
              Button(this.isSearching ? '搜索中…' : '搜索')
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(Color.White)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .type(ButtonType.Capsule)
                .id('location-search')
                .enabled(!this.isSearching)
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

      // 底部固定确认区：无论系统定位是否结束，用户拖动地图后都能立即确认
      Column({ space: SPACING.SM }) {
        Text(this.currentPosition !== null ?
          (this.currentAddressText !== '' ? this.currentAddressText : '已选择地图中心位置，点击确认即可使用') :
          '请拖动地图或搜索地点选择配送位置')
          .width('100%')
          .fontSize(FONT_SIZE.SM)
          .fontColor(this.currentPosition !== null ? COLORS.TEXT_SECONDARY : COLORS.TEXT_HINT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('确认位置')
          .width('100%')
          .height(48)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(this.currentPosition !== null ? COLORS.PRIMARY : COLORS.TEXT_HINT)
          .borderRadius(BORDER_RADIUS.ROUND)
          .type(ButtonType.Capsule)
          .id('location-confirm')
          .onClick(() => { this.useCenterPosition() })
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}
