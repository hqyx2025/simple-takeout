/**
 * 定位服务
 * 基于系统定位能力（@kit.LocationKit）获取设备实时位置，
 * 并通过高德地图Web服务API（逆地理编码/输入提示）将坐标转换为地址文本、按关键词搜索地点。
 * 前提：需在 common/Constants.ets 的 AMAP_CONFIG.API_KEY 中配置高德“Web服务”类型Key。
 */
import { geoLocationManager } from '@kit.LocationKit'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { AMAP_CONFIG } from '../common/Constants'
import { logInfo, logWarn, logError } from './AppLogger'

// 经纬度坐标
export interface GeoPosition {
  latitude: number
  longitude: number
}

// 搜索结果地点（高德输入提示）
export class SearchPlace {
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

// 高德逆地理编码响应结构
interface RegeoResponse {
  status: string
  info: string
  regeocode: RegeocodeInfo | undefined
}

interface RegeocodeInfo {
  formatted_address: string
}

// 高德输入提示响应结构
interface InputTipsResponse {
  status: string
  info: string
  tips: TipItem[] | undefined
}

interface TipItem {
  name: string
  district: string
  address: string
  location: string
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
    logInfo('Location', `获取当前位置成功: ${position.longitude.toFixed(6)}, ${position.latitude.toFixed(6)}`)
    return position
  } catch (err) {
    logError('Location', '获取当前位置失败', err as Object)
    throw new Error('定位失败，请检查定位服务是否开启')
  }
}

/**
 * 高德逆地理编码：经纬度 -> 地址文本
 */
export async function reverseGeocode(position: GeoPosition): Promise<string> {
  if (AMAP_CONFIG.API_KEY === '') {
    throw new Error('未配置高德API Key')
  }
  const location: string = `${position.longitude.toFixed(6)},${position.latitude.toFixed(6)}`
  const url: string = `${AMAP_CONFIG.RESTO_URL}/v3/geocode/regeo?key=${AMAP_CONFIG.API_KEY}&location=${location}&extensions=all`
  const httpRequest: http.HttpRequest = http.createHttp()
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: AMAP_CONFIG.TIMEOUT,
      readTimeout: AMAP_CONFIG.TIMEOUT
    })
    if (response.responseCode === 200) {
      const parsed: Object = JSON.parse(response.result as string)
      const data: RegeoResponse = parsed as RegeoResponse
      if (data.status === '1' && data.regeocode !== undefined && data.regeocode.formatted_address !== '') {
        logInfo('Location', `逆地理编码成功: ${data.regeocode.formatted_address}`)
        return data.regeocode.formatted_address
      }
      throw new Error('逆地理编码失败')
    }
    throw new Error('网络请求失败')
  } catch (err) {
    logError('Location', '逆地理编码失败', err as Object)
    throw new Error('地址解析失败，请稍后重试')
  } finally {
    httpRequest.destroy()
  }
}

/**
 * 高德输入提示搜索：按关键词搜索地点（传入当前位置可优先展示附近结果）
 */
export async function searchPlaces(keyword: string, position?: GeoPosition): Promise<SearchPlace[]> {
  if (AMAP_CONFIG.API_KEY === '') {
    throw new Error('未配置高德API Key')
  }
  let params: string = `key=${AMAP_CONFIG.API_KEY}&keywords=${encodeURIComponent(keyword)}&citylimit=false`
  if (position !== undefined) {
    params += `&location=${position.longitude.toFixed(6)},${position.latitude.toFixed(6)}`
  }
  const url: string = `${AMAP_CONFIG.RESTO_URL}/v3/assistant/inputtips?${params}`
  const httpRequest: http.HttpRequest = http.createHttp()
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: AMAP_CONFIG.TIMEOUT,
      readTimeout: AMAP_CONFIG.TIMEOUT
    })
    if (response.responseCode !== 200) {
      return []
    }
    const parsed: Object = JSON.parse(response.result as string)
    const data: InputTipsResponse = parsed as InputTipsResponse
    const result: SearchPlace[] = []
    if (data.status === '1' && data.tips !== undefined) {
      for (let i = 0; i < data.tips.length; i++) {
        const tip: TipItem = data.tips[i]
        if (tip.location === '') {
          continue
        }
        const parts: string[] = tip.location.split(',')
        if (parts.length !== 2) {
          continue
        }
        result.push(SearchPlace.create(tip.name, tip.district, tip.address, Number(parts[1]), Number(parts[0])))
      }
    }
    logInfo('Location', `搜索地点完成: keyword=${keyword}, 结果数=${result.length}`)
    return result
  } catch (err) {
    logError('Location', '搜索地点失败', err as Object)
    throw new Error('搜索失败，请检查网络或API Key配置')
  } finally {
    httpRequest.destroy()
  }
}
