/**
 * 定位服务
 * 基于系统定位能力（@kit.LocationKit）获取设备实时位置。
 * 地图显示/选点/逆地理编码/地点搜索由高德 Web端JS API（rawfile/amap_map.html + Web组件）实现，
 * 模拟器与真机均可运行，无需 native so。
 */
import { geoLocationManager } from '@kit.LocationKit'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { AMAP_CONFIG } from '../common/Constants'
import { logInfo, logWarn, logError } from './AppLogger'

// 经纬度坐标
export interface GeoPosition {
  latitude: number
  longitude: number
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
