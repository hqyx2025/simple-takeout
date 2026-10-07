/**
 * 定位服务
 * 基于系统定位能力（@kit.LocationKit）获取设备实时位置。
 * 地图显示/选点/逆地理编码/地点搜索由高德 Web端JS API（rawfile/amap_map.html + Web组件）实现，
 * 模拟器与真机均可运行，无需 native so。
 */
import { geoLocationManager } from '@kit.LocationKit'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import axios, { AxiosResponse } from '@ohos/axios'
import { AMAP_CONFIG } from '../common/Constants'
import { logInfo, logWarn, logError } from './AppLogger'

// 经纬度坐标
export interface GeoPosition {
  latitude: number
  longitude: number
}

// 地址搜索结果（高德 POI/地理编码接口）
export interface AddressSearchResult {
  name: string
  district: string
  address: string
  latitude: number
  longitude: number
}

export interface NearbyAddressSearchResult extends AddressSearchResult {
  distance: number
}

export interface NearbyAddressSearchPage {
  places: NearbyAddressSearchResult[]
  hasMore: boolean
}

interface AmapAddressComponent {
  province?: string
  city?: string
  district?: string
}

interface AmapGeocode {
  formatted_address?: string
  location?: string
  addressComponent?: AmapAddressComponent
}

interface AmapGeocodeResponse {
  status: string
  info: string
  count: string
  geocodes?: AmapGeocode[]
}

interface AmapPoi {
  name?: string
  address?: string
  location?: string
  cityname?: string
  adname?: string
  distance?: string
}

interface AmapPoiResponse {
  status: string
  info: string
  count: string
  pois?: AmapPoi[]
}

function parseAmapLocation(value: string | undefined): GeoPosition | null {
  if (value === undefined || value === '') {
    return null
  }
  const parts: string[] = value.split(',')
  if (parts.length < 2) {
    return null
  }
  const longitude: number = Number(parts[0])
  const latitude: number = Number(parts[1])
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude) || Math.abs(longitude) > 180 ||
    Math.abs(latitude) > 90 || (longitude === 0 && latitude === 0)) {
    return null
  }
  return { longitude: longitude, latitude: latitude }
}

/** 按地图中心查询真实周边地点；直接 HTTPS 请求，避免依赖 Web 地图插件的回调时机。 */
export async function searchNearbyAddress(position: GeoPosition, page: number = 1): Promise<NearbyAddressSearchPage> {
  if (!Number.isInteger(page) || page < 1 || page > 100) {
    throw new Error('附近地点页码无效')
  }
  const pageSize: number = 20
  const url: string = `https://restapi.amap.com/v3/place/around?location=${position.longitude.toFixed(6)},${position.latitude.toFixed(6)}&radius=1000&sortrule=distance&offset=${pageSize}&page=${page}&key=${AMAP_CONFIG.MAP_JS_KEY}`
  const response: AxiosResponse<AmapPoiResponse> = await axios.get<AmapPoiResponse>(url, { timeout: AMAP_CONFIG.TIMEOUT })
  const data: AmapPoiResponse = response.data
  if (data.status !== '1' || !Array.isArray(data.pois)) {
    throw new Error('附近地点查询失败')
  }
  const results: NearbyAddressSearchResult[] = []
  const seen: string[] = []
  for (let i = 0; i < data.pois.length; i++) {
    const item: AmapPoi = data.pois[i]
    const coordinate: GeoPosition | null = parseAmapLocation(item.location)
    const name: string = (item.name ?? '').trim()
    if (coordinate === null || name === '') { continue }
    const key: string = `${name}|${coordinate.longitude}|${coordinate.latitude}`
    if (seen.indexOf(key) >= 0) { continue }
    seen.push(key)
    const distance: number = item.distance !== undefined && item.distance !== '' ? Number(item.distance) : -1
    if (Number.isFinite(distance) && distance > 1000) { continue }
    results.push({ name: name, district: item.adname ?? item.cityname ?? '',
      address: typeof item.address === 'string' ? item.address : '', latitude: coordinate.latitude,
      longitude: coordinate.longitude, distance: Number.isFinite(distance) && distance >= 0 ? distance : -1 })
  }
  const total: number = Number(data.count)
  const hasMore: boolean = page < 100 && data.pois.length === pageSize &&
    (!Number.isFinite(total) || page * pageSize < total)
  return { places: results, hasMore: hasMore }
}

/**
 * 使用高德 Web 服务 POI/地理编码接口搜索地址。
 * 相比 WebView 内的输入提示，该接口可以直接将“中关村”等地名转换为坐标，
 * 由页面复用顶部地图组件进行定位。
 */
export async function searchAddress(keyword: string): Promise<AddressSearchResult[]> {
  const value: string = keyword.trim()
  if (value === '') {
    return []
  }
  try {
    // POI 文本搜索优先返回“中关村”这类地名/地标，而不是只返回道路级地理编码。
    const placeUrl: string = `https://restapi.amap.com/v3/place/text?keywords=${encodeURIComponent(value)}&offset=20&page=1&extensions=all&key=${AMAP_CONFIG.MAP_JS_KEY}`
    const placeResponse: AxiosResponse<AmapPoiResponse> = await axios.get<AmapPoiResponse>(placeUrl, {
      timeout: AMAP_CONFIG.TIMEOUT
    })
    const placeData: AmapPoiResponse = placeResponse.data
    const placeResults: AddressSearchResult[] = []
    if (placeData.status === '1' && placeData.pois !== undefined) {
      for (let i = 0; i < placeData.pois.length && i < 20; i++) {
        const item: AmapPoi = placeData.pois[i]
        const position: GeoPosition | null = parseAmapLocation(item.location)
        if (position === null) {
          continue
        }
        const address: string = item.address ?? ''
        placeResults.push({
          name: item.name ?? value,
          district: item.adname ?? item.cityname ?? '',
          address: address !== '' ? address : (item.adname ?? item.cityname ?? value),
          latitude: position.latitude,
          longitude: position.longitude
        })
      }
    }
    if (placeResults.length > 0) {
      logInfo('Location', `地点搜索成功 keyword=${value} 结果=${placeResults.length}`)
      return placeResults
    }

    // POI 无结果时再尝试地理编码，兼容道路、门牌号等纯地址关键词。
    const geocodeUrl: string = `https://restapi.amap.com/v3/geocode/geo?address=${encodeURIComponent(value)}&output=JSON&key=${AMAP_CONFIG.MAP_JS_KEY}`
    const response: AxiosResponse<AmapGeocodeResponse> = await axios.get<AmapGeocodeResponse>(geocodeUrl, {
      timeout: AMAP_CONFIG.TIMEOUT
    })
    const data: AmapGeocodeResponse = response.data
    if (data.status !== '1' || data.geocodes === undefined) {
      logWarn('Location', `地址搜索无结果 keyword=${value} info=${data.info}`)
      return []
    }
    const results: AddressSearchResult[] = []
    for (let i = 0; i < data.geocodes.length && i < 20; i++) {
      const item: AmapGeocode = data.geocodes[i]
      const position: GeoPosition | null = parseAmapLocation(item.location)
      if (position === null) {
        continue
      }
      const component: AmapAddressComponent = item.addressComponent ?? {}
      const district: string = component.district ?? component.city ?? component.province ?? ''
      const address: string = item.formatted_address ?? value
      results.push({
        name: address,
        district: district,
        address: address,
        latitude: position.latitude,
        longitude: position.longitude
      })
    }
    logInfo('Location', `地址搜索成功 keyword=${value} 结果=${results.length}`)
    return results
  } catch (err) {
    logWarn('Location', `地址搜索请求失败 keyword=${value}`)
    return []
  }
}

interface LocationFailure {
  code?: number
  message?: string
}

/**
 * 拼地址时去掉重叠前缀。
 * 系统逆地理编码会把"完整地址"塞进 roadName/premises，直接首尾相接会出现
 * "中国辽宁省沈阳市沈河区辽宁省沈阳市沈河区杏林街…" 这种重复（设备实测）。
 * 取"已有串后缀 与 新片段前缀"的最长重叠，只追加不重叠的尾巴。
 */
function overlapRemainder(joined: string, value: string): string {
  const maxLength: number = Math.min(joined.length, value.length)
  for (let length = maxLength; length > 0; length--) {
    if (joined.substring(joined.length - length) === value.substring(0, length)) {
      return value.substring(length)
    }
  }
  return value
}

/** 拼接地址主体与详情（去重叠），避免"沈阳市沈河区沈阳市沈河区xx路"这类重复。 */
export function joinAddressParts(primary: string, detail: string): string {
  const head: string = (primary ?? '').trim()
  const tail: string = (detail ?? '').trim()
  if (head === '') {
    return tail
  }
  if (tail === '') {
    return head
  }
  return head + overlapRemainder(head, tail)
}

/** 将经纬度转换为可展示的中文地址（逆地理编码）。 */
export async function reverseGeocodePosition(position: GeoPosition): Promise<string> {
  try {
    const request: geoLocationManager.ReverseGeoCodeRequest = {
      latitude: position.latitude,
      longitude: position.longitude,
      maxItems: 1,
      locale: 'zh'
    }
    const addresses: Array<geoLocationManager.GeoAddress> = await geoLocationManager.getAddressesFromLocation(request)
    if (addresses.length === 0) {
      return ''
    }
    const address: geoLocationManager.GeoAddress = addresses[0]
    let result: string = ''
    const append = (value: string | undefined): void => {
      if (value !== undefined && value !== '') {
        result += overlapRemainder(result, value)
      }
    }
    append(address.countryName)
    append(address.administrativeArea)
    append(address.locality)
    append(address.subLocality)
    append(address.roadName)
    append(address.premises)
    append(address.placeName)
    return result
  } catch (err) {
    logWarn('Location', '逆地理编码失败')
    return ''
  }
}

// 权限授权结果码
const GRANTED: number = 0

/**
 * 请求定位权限（模糊+精确），返回是否获得至少一种定位授权
 */
export async function requestLocationPermission(context: common.UIAbilityContext, fromSettings: boolean = false): Promise<boolean> {
  const permissions: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    if (fromSettings) {
      const settingsResults: abilityAccessCtrl.GrantStatus[] = await atManager.requestPermissionOnSetting(context, permissions)
      return settingsResults.some((status: abilityAccessCtrl.GrantStatus) => status === GRANTED)
    }
    const result = await atManager.requestPermissionsFromUser(context, permissions)
    const results: Array<number> = result.authResults
    for (let i = 0; i < results.length; i++) {
      if (results[i] === GRANTED) {
        return true
      }
    }
    return false
  } catch (err) {
    logWarn('Location', '请求定位权限失败')
    return false
  }
}

/**
 * 获取设备当前实时位置（一次性定位，超时由 AMAP_CONFIG.TIMEOUT 控制）
 * 注意：模拟器可能定位失败或返回固定位置，失败时用户可拖动地图手动选点
 */
export async function getCurrentPosition(context: common.UIAbilityContext, fromSettings: boolean = false): Promise<GeoPosition> {
  const granted: boolean = await requestLocationPermission(context, fromSettings)
  if (!granted) {
    throw new Error('未获得定位权限，无法获取当前位置')
  }
  try {
    const requestInfo: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      scenario: geoLocationManager.LocationRequestScenario.UNSET,
      maxAccuracy: 0,
      timeoutMs: AMAP_CONFIG.TIMEOUT
    }
    const location = await geoLocationManager.getCurrentLocation(requestInfo)
    const position: GeoPosition = {
      latitude: location.latitude,
      longitude: location.longitude
    }
    if (!Number.isFinite(position.latitude) || !Number.isFinite(position.longitude)
      || Math.abs(position.latitude) > 90 || Math.abs(position.longitude) > 180
      || (position.latitude === 0 && position.longitude === 0)) {
      throw new Error('系统未返回有效的当前位置，请稍后重试或手动选择位置')
    }
    logInfo('Location', `获取当前位置成功: ${position.longitude.toFixed(6)}, ${position.latitude.toFixed(6)}`)
    return position
  } catch (err) {
    const failure: LocationFailure = err as LocationFailure
    logError('Location', '获取当前位置失败', err as Object)
    if (failure.code === 3301100 || (failure.message !== undefined && failure.message.indexOf('location switch is off') >= 0)) {
      throw new Error('系统定位服务已关闭，请打开设备定位开关后重试；也可以拖动地图或搜索地点选择位置')
    }
    if (failure.message !== undefined && failure.message.indexOf('未返回有效') >= 0) {
      throw new Error('系统未返回有效的当前位置，请稍后重试或手动选择位置')
    }
    throw new Error('定位失败，请拖动地图或手动搜索选择位置')
  }
}
