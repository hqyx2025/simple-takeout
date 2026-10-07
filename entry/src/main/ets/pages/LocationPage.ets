import { AppButtonStyle, AppInputStyle } from '../common/theme/AppTheme'
/**
 * 选择位置页面
 * 功能：
 * 1. 顶部展示高德地图（Web端JS API + Web组件，无native so，模拟器/真机均可运行）
 * 2. 支持拖动/双指缩放选点，地图中心固定位置图标，中心即所选位置（JS内逆地理编码自动解析地址）
 * 3. 进入页面自动实时定位手机当前位置，地图中心移动到定位点
 * 4. 展示所选位置附近的真实地点，支持点选及关键词搜索联动定位
 * 5. 实时定位与配送地址分开；服务端保存成功后才更新主页配送地址
 */
import { AppMotion } from '../common/theme/AppMotion'
import { Address, User } from '../model/Models'
import { addAddressRemoteAndGet, isLoggedIn } from '../service/AppStorageManager'
import { COLORS, SPACING, FONT_SIZE, BORDER_RADIUS } from '../common/Constants'
import { AddressSearchResult, NearbyAddressSearchResult, NearbyAddressSearchPage, GeoPosition, getCurrentPosition,
  reverseGeocodePosition, searchAddress, searchNearbyAddress } from '../service/LocationService'
import { EmptyState } from '../components/EmptyState'
import { PageHeader } from '../components/PageHeader'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { common } from '@kit.AbilityKit'
import { webview } from '@kit.ArkWeb'
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { logInfo } from '../service/AppLogger'
import { saveAllData } from '../service/DataPersistence'

// 搜索结果地点（高德输入提示，经JS桥回传）
class SearchPlace implements GeoPosition {
  name: string = ''
  district: string = ''
  address: string = ''
  latitude: number = 0
  longitude: number = 0
  distance: number = -1

  static create(name: string, district: string, address: string, latitude: number, longitude: number,
    distance: number = -1): SearchPlace {
    const place = new SearchPlace()
    place.name = name
    place.district = district
    place.address = address
    place.latitude = latitude
    place.longitude = longitude
    place.distance = distance
    return place
  }
}

// JS桥对象（javaScriptProxy 要求 class 实例，回调由组件在 aboutToAppear 中赋值）
class LocationWebBridge {
  onCenterChanged: (lngStr: string, latStr: string, address: string, source: string) => void = () => {}
  onSearchResult: (jsonStr: string) => void = () => {}
  onNearbyResult: (lngStr: string, latStr: string, jsonStr: string, success: string) => void = () => {}
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

  // Web 地图
  private webController: webview.WebviewController = new webview.WebviewController()
  private webBridge: LocationWebBridge = new LocationWebBridge()
  @State isMapReady: boolean = false
  // 定位状态
  @State isLocating: boolean = false
  @State currentAddressText: string = ''        // 地图中心/当前定位的地址文本
  @State currentPosition: GeoPosition | null = null  // 地图中心坐标（即用户选择的坐标）
  @State locateError: string = ''
  private locationRequestId: number = 0
  // 搜索状态
  @State keyword: string = ''
  @State isSearching: boolean = false
  @State searchResults: SearchPlace[] = []
  @State searched: boolean = false
  @State nearbyPlaces: SearchPlace[] = []
  @State nearbyLoading: boolean = false
  @State nearbyError: string = ''
  @State nearbyHasMore: boolean = false
  @State nearbyMoreLoading: boolean = false
  @State nearbyMoreError: string = ''
  private nearbyNextPage: number = 1
  private nearbyRestReady: boolean = false
  private nearbyRestPending: boolean = false
  private nearbyPosition: GeoPosition | null = null
  private nearbyTimer: number = -1
  private nearbyRequestId: number = 0
  private pageActive: boolean = false
  // 选中的搜索结果
  @State selectedPlace: SearchPlace | null = null
  @State showSavedDialog: boolean = false
  // 确认位置保存中标记，防止连点重复新增地址
  @State savingAddress: boolean = false

  aboutToAppear() {
    this.pageActive = true
    if (!isLoggedIn()) {
      AppStorage.setOrCreate<boolean>('pendingLocationLoginPrompt', true)
      router.back()
      return
    }
    // JS桥回调绑定（Web页面通过 window.ohosBridge 调用）
    this.webBridge.onCenterChanged = (lngStr: string, latStr: string, address: string, source: string): void => {
      this.onCenterChangedFromJs(lngStr, latStr, address, source)
    }
    this.webBridge.onSearchResult = (jsonStr: string): void => {
      this.onSearchResultFromJs(jsonStr)
    }
    this.webBridge.onNearbyResult = (lngStr: string, latStr: string, jsonStr: string, success: string): void => {
      this.onNearbyResultFromJs(lngStr, latStr, jsonStr, success)
    }
    // 每次进入均请求实时位置，不把历史配送地址或旧 GPS 坐标当作当前定位。
    this.locateCurrent()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.locationRequestId += 1
    this.clearNearby()
  }

  private clearNearby(): void {
    this.nearbyRequestId += 1
    clearTimeout(this.nearbyTimer)
    this.nearbyTimer = -1
    this.nearbyPosition = null
    this.nearbyPlaces = []
    this.nearbyLoading = false
    this.nearbyError = ''
    this.nearbyHasMore = false
    this.nearbyMoreLoading = false
    this.nearbyMoreError = ''
    this.nearbyNextPage = 1
    this.nearbyRestReady = false
    this.nearbyRestPending = false
  }

  private samePosition(first: GeoPosition, second: GeoPosition): boolean {
    return Math.abs(first.longitude - second.longitude) + Math.abs(first.latitude - second.latitude) < 0.00001
  }

  private beginNearby(position: GeoPosition): void {
    if (this.nearbyPosition !== null && this.samePosition(this.nearbyPosition, position)) { return }
    this.clearNearby()
    this.nearbyPosition = { latitude: position.latitude, longitude: position.longitude }
    this.nearbyLoading = true
    this.nearbyTimer = setTimeout(() => {
      this.nearbyLoading = false
      if (this.nearbyPlaces.length === 0) {
        this.nearbyError = '附近地点加载超时，请重试'
      }
    }, 15000)
    this.loadNearby(position, this.nearbyRequestId)
  }

  private async loadNearby(position: GeoPosition, requestId: number, page: number = 1): Promise<void> {
    this.nearbyRestPending = true
    try {
      const result: NearbyAddressSearchPage = await searchNearbyAddress(position, page)
      if (!this.pageActive || this.nearbyRequestId !== requestId) { return }
      const places: SearchPlace[] = result.places.map((place: NearbyAddressSearchResult): SearchPlace => {
        return SearchPlace.create(place.name, place.district, place.address,
          place.latitude, place.longitude, place.distance)
      })
      if (page === 1) {
        if (places.length > 0 || this.nearbyPlaces.length === 0) { this.nearbyPlaces = places }
      } else {
        const combined: SearchPlace[] = this.nearbyPlaces.slice()
        const keys: string[] = combined.map((place: SearchPlace): string => this.placeKey(place))
        for (let i = 0; i < places.length; i++) {
          const place: SearchPlace = places[i]
          const key: string = this.placeKey(place)
          if (keys.indexOf(key) >= 0) { continue }
          keys.push(key)
          combined.push(place)
        }
        this.nearbyPlaces = combined
      }
      this.nearbyNextPage = page + 1
      this.nearbyHasMore = result.hasMore
      this.nearbyRestReady = true
      clearTimeout(this.nearbyTimer)
      this.nearbyTimer = -1
      this.nearbyLoading = false
      this.nearbyMoreLoading = false
      this.nearbyRestPending = false
      this.nearbyError = ''
      this.nearbyMoreError = ''
      logInfo('LocationPage', `附近地点加载完成：${this.nearbyPlaces.length}个`)
    } catch (_) {
      if (!this.pageActive || this.nearbyRequestId !== requestId) { return }
      clearTimeout(this.nearbyTimer)
      this.nearbyTimer = -1
      this.nearbyLoading = false
      this.nearbyMoreLoading = false
      this.nearbyRestPending = false
      if (this.nearbyPlaces.length === 0 && page === 1) {
        this.nearbyError = '附近地点加载失败，请重试'
      } else {
        this.nearbyHasMore = true
        this.nearbyMoreError = '更多地点加载失败，请重试'
      }
    }
  }

  private placeKey(place: SearchPlace): string {
    return `${place.name}|${place.longitude.toFixed(6)}|${place.latitude.toFixed(6)}`
  }

  private loadMoreNearby(): void {
    if (!this.pageActive || this.nearbyPosition === null || !this.nearbyHasMore ||
      this.nearbyLoading || this.nearbyMoreLoading || this.nearbyRestPending) { return }
    this.nearbyMoreLoading = true
    this.nearbyMoreError = ''
    this.loadNearby(this.nearbyPosition, this.nearbyRequestId, this.nearbyNextPage)
  }

  private parsePlaces(jsonStr: string): SearchPlace[] {
    const parsed: Object = JSON.parse(jsonStr)
    if (!Array.isArray(parsed)) { throw new Error('地点列表格式错误') }
    const list: Array<Record<string, Object>> = parsed as Array<Record<string, Object>>
    const results: SearchPlace[] = []
    for (let i = 0; i < list.length && results.length < 20; i++) {
      const item: Record<string, Object> = list[i]
      if (item === null || typeof item !== 'object') { continue }
      const name: string = String(item['name'] ?? '').trim()
      const latitude: number = Number(item['lat'] ?? 0)
      const longitude: number = Number(item['lng'] ?? 0)
      if (name === '' || !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180 || (latitude === 0 && longitude === 0)) { continue }
      const distance: number = Number(item['distance'] ?? -1)
      results.push(SearchPlace.create(name, String(item['district'] ?? ''), String(item['address'] ?? ''),
        latitude, longitude, Number.isFinite(distance) && distance >= 0 ? distance : -1))
    }
    return results
  }

  private onNearbyResultFromJs(lngStr: string, latStr: string, jsonStr: string, success: string): void {
    const position: GeoPosition = { longitude: Number(lngStr), latitude: Number(latStr) }
    if (!this.pageActive || this.currentPosition === null || this.nearbyPosition === null ||
      !this.samePosition(this.currentPosition, position) || !this.samePosition(this.nearbyPosition, position)) { return }
    if (this.nearbyRestReady || this.nearbyMoreLoading) { return }
    if (success !== '1') { return }
    try {
      this.nearbyPlaces = this.parsePlaces(jsonStr)
      this.nearbyError = ''
      // Web 回传只是一批预览；只有 REST 成功后才推进页码。
      if (!this.nearbyRestPending) {
        this.nearbyLoading = false
        this.nearbyHasMore = this.nearbyPlaces.length > 0
        this.nearbyMoreError = this.nearbyPlaces.length > 0 ? '附近地点加载不完整，请继续加载' : ''
      }
      logInfo('LocationPage', `附近地点加载完成：${this.nearbyPlaces.length}个`)
    } catch (_) {
      if (this.nearbyPlaces.length === 0 && !this.nearbyRestPending) {
        this.nearbyError = '附近地点加载失败，请重试'
      }
    }
  }

  private retryNearby(): void {
    if (this.currentPosition === null || this.nearbyLoading) { return }
    const position: GeoPosition = this.currentPosition
    this.clearNearby()
    this.beginNearby(position)
    this.refreshMap()
  }

  // 默认地图中心不回传；手动选点取消尚未结束的 GPS，避免旧结果覆盖选择。
  private onCenterChangedFromJs(lngStr: string, latStr: string, address: string, source: string): void {
    const lng: number = Number(lngStr)
    const lat: number = Number(latStr)
    if (!Number.isFinite(lng) || !Number.isFinite(lat) || Math.abs(lng) > 180 || Math.abs(lat) > 90) {
      return
    }
    if (source === 'manual') {
      this.locationRequestId += 1
      this.isLocating = false
    } else if (this.currentPosition === null ||
      Math.abs(this.currentPosition.longitude - lng) + Math.abs(this.currentPosition.latitude - lat) >= 0.00001) {
      return
    }
    if (address === '' && this.currentPosition !== null &&
      Math.abs(this.currentPosition.longitude - lng) + Math.abs(this.currentPosition.latitude - lat) < 0.00001) {
      return
    }
    this.currentPosition = { latitude: lat, longitude: lng }
    this.beginNearby(this.currentPosition)
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
      const results: SearchPlace[] = this.parsePlaces(jsonStr)
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
      this.locationRequestId += 1
      this.isLocating = false
      this.locateError = ''
      const first: SearchPlace = results[0]
      this.selectedPlace = first
      this.currentPosition = { latitude: first.latitude, longitude: first.longitude }
      this.beginNearby(this.currentPosition)
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
      methodList: ['onCenterChanged', 'onSearchResult', 'onNearbyResult'],
      controller: this.webController
    }
    return options
  }

  // 定位当前手机实时位置（成功后地图中心自动移动到定位点）
  private async locateCurrent(fromSettings: boolean = false): Promise<void> {
    const requestId: number = ++this.locationRequestId
    this.isLocating = true
    this.locateError = ''
    this.currentPosition = null
    this.currentAddressText = ''
    this.selectedPlace = null
    this.clearNearby()
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const position: GeoPosition = await getCurrentPosition(context, fromSettings)
      if (this.locationRequestId !== requestId) {
        return
      }
      this.currentPosition = position
      this.beginNearby(position)
      const address: string = await reverseGeocodePosition(position)
      if (this.locationRequestId !== requestId) {
        return
      }
      this.currentAddressText = address
      if (this.isMapReady) {
        await this.moveMapCenter(position)
      }
      logInfo('LocationPage', '实时定位完成')
    } catch (err) {
      if (this.locationRequestId !== requestId) {
        return
      }
      this.locateError = err instanceof Error ? err.message : '定位失败，请重试或手动选点'
    } finally {
      if (this.locationRequestId === requestId) {
        this.isLocating = false
      }
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
    const safeKw: string = JSON.stringify(kw)
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
      await this.webController.runJavaScript(`searchKeyword(${safeKw})`)
    } catch (err) {
      this.isSearching = false
      promptAction.showToast({ message: '搜索失败，请检查网络或API Key配置', duration: 2000 })
    }
  }

  // 选中搜索结果：高亮并将地图中心移动到该地点（JS回调自动更新地址）
  private selectPlace(place: SearchPlace): void {
    this.locationRequestId += 1
    this.isLocating = false
    this.locateError = ''
    this.selectedPlace = place
    this.currentPosition = { latitude: place.latitude, longitude: place.longitude }
    this.beginNearby(this.currentPosition)
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
    // 连点确认会重复调用新增地址接口，落库出多条重复地址；保存期间直接忽略后续点击。
    if (this.savingAddress) {
      return
    }
    this.savingAddress = true
    try {
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
      // 门店选点模式：只把「地址 + 坐标」写回上层表单，不新增用户收货地址、不改当前配送地址
      const pickStore: boolean = AppStorage.get<boolean>('storeLocationPickMode') || false
      if (pickStore) {
        AppStorage.setOrCreate<Address>('pickedStoreLocation',
          this.buildPickedLocation(addressText, detail, pos, '门店定位'))
        AppStorage.setOrCreate<boolean>('storeLocationPickMode', false)
        logInfo('LocationPage', `门店定位已选：${addressText} ${detail}（${pos.latitude},${pos.longitude}）`)
        promptAction.showToast({ message: '已选择门店位置', duration: 1500 })
        router.back()
        return
      }
      // 骑手接单位置模式：同样只回传地址+坐标，不新增收货地址
      const pickRider: boolean = AppStorage.get<boolean>('riderLocationPickMode') || false
      if (pickRider) {
        AppStorage.setOrCreate<Address>('pickedRiderLocation',
          this.buildPickedLocation(addressText, detail, pos, '接单位置'))
        AppStorage.setOrCreate<boolean>('riderLocationPickMode', false)
        logInfo('LocationPage', `骑手接单位置已选：${addressText} ${detail}（${pos.latitude},${pos.longitude}）`)
        promptAction.showToast({ message: '已选择接单位置', duration: 1500 })
        router.back()
        return
      }
      await this.applyAddress(addressText, detail, pos)
    } finally {
      this.savingAddress = false
    }
  }

  /** 把当前选点打包成上层表单可直接消费的地址对象（门店/骑手选点共用，不落库）。 */
  private buildPickedLocation(addressText: string, detail: string, pos: GeoPosition, tag: string): Address {
    const picked: Address = {
      id: 0,
      name: '',
      phone: '',
      address: addressText,
      detail: detail,
      isDefault: false,
      tag: tag,
      latitude: pos.latitude,
      longitude: pos.longitude
    }
    return picked
  }

  // 保存配送地址后明确提示用户，并由用户确认是否返回首页。
  private async applyAddress(addressText: string, detail: string, pos: GeoPosition): Promise<void> {
    const user: User | undefined = AppStorage.get<User>('user')
    const session: string = AppStorage.get<string>('authToken') ?? ''
    const name: string = user !== undefined && user !== null ? user.username : ''
    const phone: string = user !== undefined && user !== null ? user.phone : ''
    const fullAddress: string = `${addressText} ${detail}`.trim()
    const persistedAddress: Address | null = await addAddressRemoteAndGet(name, phone, fullAddress, true,
      pos.latitude, pos.longitude)
    if (!isLoggedIn() || session !== (AppStorage.get<string>('authToken') ?? '')
      || user?.id !== AppStorage.get<User>('user')?.id) {
      return
    }
    if (persistedAddress === null) {
      return
    }
    if (persistedAddress.id <= 0) {
      promptAction.showToast({ message: '定位地址保存失败，请稍后重试', duration: 1800 })
      return
    }
    const addr: Address = {
      id: persistedAddress.id,
      name: persistedAddress.name,
      phone: persistedAddress.phone,
      address: persistedAddress.address,
      detail: persistedAddress.detail,
      isDefault: true,
      tag: '定位',
      latitude: pos.latitude,
      longitude: pos.longitude
    }
    AppStorage.setOrCreate<Address>('currentAddress', addr)
    AppStorage.setOrCreate<GeoPosition>('lastLocationPosition', pos)
    await saveAllData()
    logInfo('LocationPage', `已选择并保存配送地址: ${fullAddress}`)
    this.showSavedDialog = true
  }

  private isPlaceSelected(place: SearchPlace): boolean {
    return this.selectedPlace !== null && this.selectedPlace.name === place.name &&
      this.samePosition(this.selectedPlace, place)
  }

  @Builder
  PlaceRow(place: SearchPlace, nearby: boolean) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SPACING.SM }) {
        Image($r('app.media.home_location')).width(20).height(20).objectFit(ImageFit.Contain)
          .accessibilityLevel('no')
        Column({ space: SPACING.XS }) {
          Text(place.name).fontSize(FONT_SIZE.MD)
            .fontColor(this.isPlaceSelected(place) ? COLORS.PRIMARY : COLORS.TEXT_PRIMARY)
            .fontWeight(this.isPlaceSelected(place) ? FontWeight.Bold : FontWeight.Normal)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (place.address !== '' || place.district !== '') {
            Text(place.district !== '' ? `${place.district} ${place.address}`.trim() : place.address)
              .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (nearby && place.distance >= 0) {
          Text(place.distance < 1000 ? `${Math.round(place.distance)}米` : `${(place.distance / 1000).toFixed(1)}公里`)
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT)
        }
        if (this.isPlaceSelected(place)) {
          Text('✓').fontSize(FONT_SIZE.LG).fontColor(COLORS.PRIMARY)
        }
      }.width('100%')
    }
    .attributeModifier(new AppButtonStyle())
    .width('100%').constraintSize({ minHeight: 64 }).padding(SPACING.MD)
    .backgroundColor(this.isPlaceSelected(place) ? COLORS.TAG_BG : COLORS.BG_WHITE)
    .borderRadius(BORDER_RADIUS.MD)
    .id(`location-${nearby ? 'nearby' : 'result'}-${place.longitude.toFixed(6)}-${place.latitude.toFixed(6)}`)
    .onClick(() => { this.selectPlace(place) })
  }

  @Builder
  NearbyPlaces() {
    if (this.currentPosition !== null) {
      Column({ space: SPACING.SM }) {
        Row() {
          Text('附近地点').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          Blank()
          Button('刷新')
            .attributeModifier(new AppButtonStyle()).height(32).fontSize(FONT_SIZE.SM)
            .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND).enabled(!this.nearbyLoading)
            .id('location-nearby-refresh').onClick(() => { this.retryNearby() })
        }.width('100%')
        Text(`搜索地图中心1公里内的地点，已加载${this.nearbyPlaces.length}个，按距离排列。`)
          .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
        if (this.nearbyLoading) {
          Row({ space: SPACING.SM }) {
            LoadingProgress().width(20).height(20).color(COLORS.PRIMARY)
            Text('正在加载附近地点…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
          }.width('100%').padding({ top: SPACING.MD, bottom: SPACING.MD })
        } else if (this.nearbyError !== '') {
          Text(this.nearbyError).fontSize(FONT_SIZE.MD).fontColor(COLORS.ERROR).width('100%')
          Button('重试')
            .attributeModifier(new AppButtonStyle()).fontColor(COLORS.PRIMARY).backgroundColor(COLORS.TAG_BG)
            .id('location-nearby-retry').onClick(() => { this.retryNearby() })
        } else if (this.nearbyPlaces.length > 0) {
          ForEach(this.nearbyPlaces, (place: SearchPlace) => {
            this.PlaceRow(place, true)
          }, (place: SearchPlace) => `${place.name}|${place.longitude}|${place.latitude}`)
        } else {
          Text(this.nearbyHasMore ? '这批地点暂无可选结果，请继续加载。' :
            '附近暂无可选地点，可拖动地图或搜索其他地点。')
            .fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT).width('100%')
        }
        if (this.nearbyMoreError !== '') {
          Text(this.nearbyMoreError).fontSize(FONT_SIZE.SM).fontColor(COLORS.ERROR).width('100%')
        }
        if (this.nearbyHasMore && !this.nearbyLoading && this.nearbyError === '') {
          Button(this.nearbyMoreLoading ? '正在加载更多地点…' :
            (this.nearbyMoreError !== '' ? '重试加载' : '加载更多地点'))
            .attributeModifier(new AppButtonStyle()).width('100%').height(40)
            .fontColor(COLORS.PRIMARY).backgroundColor(COLORS.TAG_BG)
            .enabled(!this.nearbyMoreLoading)
            .id('location-nearby-load-more').onClick(() => { this.loadMoreNearby() })
        } else if (!this.nearbyLoading && this.nearbyError === '' && this.nearbyPlaces.length > 0) {
          Text('已显示地图返回的周边地点，可搜索更多地点。')
            .fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
            .id('location-nearby-end')
        }
      }
      .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE)
      .borderRadius(BORDER_RADIUS.LG).alignItems(HorizontalAlign.Start).id('location-nearby-list')
    }
  }

  build() {
    Stack() {
      Column() {
      // 顶部导航栏
      PageHeader({ title: '选择位置', onBack: () => { router.back() } })

      // 地图区域：拖动/缩放地图，中心图标即所选位置
      Stack() {
        Web({ src: $rawfile('amap_map.html'), controller: this.webController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy(this.getProxyOptions())
          .onPageEnd(() => {
            this.isMapReady = true
            // 地图加载后只移动到本次实时定位或用户主动选择的位置
            // 高德 JS 地图在 Web 页面结束回调后还会延迟初始化，延迟调用避免 moveTo 落在 map=null 时被丢弃。
            setTimeout(() => {
              if (this.currentPosition !== null) {
                this.moveMapCenter(this.currentPosition)
              }
            }, 500)
          })
          .width('100%')
          .height('100%')

        // 中心位置图标（固定在地图中间，跟随地图中心）
        Column() {
          Image($r('app.media.home_location'))
            .width(32).height(32).objectFit(ImageFit.Contain)
        }
        .height(56)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height(240)
      .backgroundColor(COLORS.BG_WHITE)
      .clip(true)

      Scroll() {
        Column({ space: SPACING.MD }) {
          // 当前位置卡片（显示地图中心解析出的地址）
          Column({ space: SPACING.SM }) {
            Row() {
              Image($r('app.media.home_location'))
                .width(24).height(24).objectFit(ImageFit.Contain)
              Text('当前选择')
                .fontSize(FONT_SIZE.LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
                .margin({ left: SPACING.SM })
              Blank()
              Button('刷新地图')
          .attributeModifier(new AppButtonStyle())
                .height(32)
                .fontSize(FONT_SIZE.SM)
                .fontColor(COLORS.PRIMARY)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
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
              if (this.selectedPlace !== null) {
                Text(this.selectedPlace.name).fontSize(FONT_SIZE.MD).fontColor(COLORS.PRIMARY).width('100%')
              }
              Text(this.currentAddressText !== '' ? this.currentAddressText : '请拖动地图中心图标选择配送位置')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')
            } else {
              Text(this.locateError !== '' ? this.locateError : '尚未获取当前位置，请定位或手动选点')
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.ERROR)
                .width('100%')
            }
            if (!this.isLocating) {
              Button(this.locateError.indexOf('权限') >= 0 ? '设置定位权限' : '重新定位')
          .attributeModifier(new AppButtonStyle())
                .width('100%')
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.PRIMARY)
                .backgroundColor(COLORS.BG_PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
                .id('location-relocate')
                .onClick(() => { this.locateCurrent(this.locateError.indexOf('权限') >= 0) })
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
          .attributeModifier(new AppInputStyle())
                .id('location-keyword')
                .layoutWeight(1)
                .onChange((value: string) => { this.keyword = value })
                .onSubmit(() => { this.doSearch() })
              Button(this.isSearching ? '搜索中…' : '搜索')
          .attributeModifier(new AppButtonStyle())
                .height(40)
                .fontSize(FONT_SIZE.MD)
                .fontColor(COLORS.ON_PRIMARY)
                .backgroundColor(COLORS.PRIMARY)
                .borderRadius(BORDER_RADIUS.ROUND)
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
                    this.PlaceRow(place, false)
                  }
                }, (place: SearchPlace) => `${place.name}|${place.longitude}|${place.latitude}`)
              }
              .width('100%')
              .divider({ strokeWidth: 0 })
              .scrollBar(BarState.Off)
            } else if (this.searched) {
              EmptyState({ icon: $r('app.media.home_search'), title: '未找到相关地点', description: '换个关键词再试试' })
            }
          }
          .width('100%')
          .padding(SPACING.LG)
          .backgroundColor(COLORS.BG_WHITE)
          .borderRadius(BORDER_RADIUS.LG)
          .alignItems(HorizontalAlign.Start)
          this.NearbyPlaces()
        }
        .width('100%')
        .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .onReachEnd(() => {
        if (this.nearbyMoreError === '') { this.loadMoreNearby() }
      })

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
        Button(this.savingAddress ? '正在保存…' : '确认位置')
          .attributeModifier(new AppButtonStyle())
          .width('100%')
          .height(48)
          .fontSize(FONT_SIZE.LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.currentPosition !== null ? COLORS.ON_PRIMARY : COLORS.TEXT_HINT)
          .backgroundColor(this.currentPosition !== null ? COLORS.PRIMARY : COLORS.DIVIDER)
          .borderRadius(BORDER_RADIUS.ROUND)
          .id('location-confirm')
          .enabled(this.currentPosition !== null && !this.savingAddress && !this.isLocating)
          .onClick(() => { this.useCenterPosition() })
      }
      .width('100%')
      .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.MD, bottom: SPACING.LG })
      .backgroundColor(COLORS.BG_WHITE)
    }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BG_PRIMARY)

      if (this.showSavedDialog) {
        ConfirmDialog({
          title: '地址已保存',
          content: '当前定位地址已保存，可用于主页配送和下单。是否返回首页？',
          confirmText: '返回首页',
          cancelText: '留在此页',
          onConfirm: () => {
            this.showSavedDialog = false
            router.back()
          },
          onCancel: () => {
            this.showSavedDialog = false
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BG_PRIMARY)
  }
}
