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
  if (Number.isNaN(longitude) || Number.isNaN(latitude) || (longitude === 0 && latitude === 0)) {
    return null
  }
  return { longitude: longitude, latitude: latitude }
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
    const parts: string[] = []
    const append = (value: string | undefined): void => {
      if (value !== undefined && value !== '' && (parts.length === 0 || parts[parts.length - 1] !== value)) {
        parts.push(value)
      }
    }
    append(address.countryName)
    append(address.administrativeArea)
    append(address.locality)
    append(address.subLocality)
    append(address.roadName)
    append(address.premises)
    append(address.placeName)
    return parts.join('')
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
export async function requestLocationPermission(context: common.UIAbilityContext): Promise<boolean> {
  const permissions: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']
  try {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
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
export async function getCurrentPosition(context: common.UIAbilityContext): Promise<GeoPosition> {
  const granted: boolean = await requestLocationPermission(context)
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
    if (position.latitude === 0 && position.longitude === 0) {
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
