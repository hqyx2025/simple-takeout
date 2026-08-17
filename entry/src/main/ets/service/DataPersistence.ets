/**
 * 数据持久化服务
 * 基于 @ohos.data.preferences 实现 AppStorage 关键数据的持久化
 * 确保 App 重启后用户数据不丢失
 */
import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import { User, Order, createEmptyUser } from '../model/Models'
import { logInfo, logWarn, logError } from './AppLogger'
import { setAuthToken } from './HttpClient'

const PERSISTENCE_NAME: string = 'takeout_app_data'

// 需要持久化的 AppStorage 键列表
const PERSISTENCE_KEYS: string[] = [
  'privacyConsent',
  'authToken',
  'isLoggedIn',
  'user',
  'cartItems',
  'orderList',
  'favoriteList',
  'addressList',
  'couponList',
  'currentAddress',
  'lastLocationPosition'
]

let prefsInstance: preferences.Preferences | null = null

/**
 * 获取或初始化 preferences 实例
 */
async function getPrefs(): Promise<preferences.Preferences> {
  if (prefsInstance !== null) {
    return prefsInstance
  }
  const context: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('appContext') as common.UIAbilityContext
  if (context === undefined || context === null) {
    throw new Error('appContext not set in AppStorage')
  }
  prefsInstance = await preferences.getPreferences(context, PERSISTENCE_NAME)
  return prefsInstance
}

/**
 * 数据归一化：兼容旧版本持久化数据（缺字段/格式异常），避免渲染崩溃
 */
function normalizeUser(value: Object): Object {
  if (value === null || typeof value !== 'object') {
    return createEmptyUser()
  }
  const user: User = value as User
  user.coupons = []
  user.orders = []
  if (!Array.isArray(user.storeIds)) {
    user.storeIds = []
  }
  if (typeof user.balance !== 'number') {
    user.balance = 0
  }
  if (typeof user.id !== 'number') {
    user.id = 0
  }
  if (typeof user.username !== 'string') {
    user.username = '用户'
  }
  if (typeof user.phone !== 'string') {
    user.phone = ''
  }
  return user
}

function normalizeOrderList(value: Object): Object {
  const emptyOrders: Order[] = []
  return emptyOrders
}

// 归一化入口：按 key 处理对应数据
export function normalizeData(key: string, value: Object): Object {
  if (key === 'authToken') {
    return typeof value === 'string' ? value : ''
  }
  if (key === 'user') {
    return normalizeUser(value)
  }
  if (key === 'orderList') {
    return normalizeOrderList(value)
  }
  if (key === 'cartItems') {
    if (Array.isArray(value)) {
      return value
    }
    const empty: Object[] = []
    return empty
  }
  if (key === 'favoriteList' || key === 'couponList' || key === 'addressList') {
    if (Array.isArray(value)) {
      return value
    }
    const empty: Object[] = []
    return empty
  }
  return value
}

/**
 * 从持久化存储中加载所有数据到 AppStorage
 * 通常在 App 启动时调用
 */
export async function loadAllData(): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPrefs()
    const consentJson: string = await prefs.get('privacyConsent', '') as string
    const consented: boolean = consentJson === 'true'
    AppStorage.setOrCreate<boolean>('privacyConsent', consented)
    // 未同意隐私政策前不恢复用户、订单、地址和 Token 等敏感数据。
    if (!consented) {
      AppStorage.setOrCreate<boolean>('_persistenceReady', true)
      return
    }
    for (let i = 0; i < PERSISTENCE_KEYS.length; i++) {
      const key: string = PERSISTENCE_KEYS[i]
      if (key === 'privacyConsent') {
        continue
      }
      const json: string = await prefs.get(key, '') as string
      if (json !== '') {
        try {
          const value: Object = JSON.parse(json)
          // 归一化：确保数据格式与模型一致，兼容旧版本数据
          const normalized: Object = normalizeData(key, value)
          AppStorage.setOrCreate(key, normalized)
          if (key === 'authToken' && typeof normalized === 'string') {
            setAuthToken(normalized)
          }
          logInfo('Persistence', `恢复数据 key=${key} 成功`)
        } catch (parseErr) {
          logWarn('Persistence', `恢复数据 key=${key} 解析失败，使用默认值`)
          console.error(`DataPersistence: Failed to parse ${key}`, JSON.stringify(parseErr))
        }
      } else {
        logInfo('Persistence', `恢复数据 key=${key} 无持久化记录，使用默认值`)
      }
    }
    const restoredToken: string = AppStorage.get<string>('authToken') || ''
    const restoredLoggedIn: boolean = AppStorage.get<boolean>('isLoggedIn') || false
    if (restoredLoggedIn && restoredToken === '') {
      AppStorage.setOrCreate<boolean>('isLoggedIn', false)
      AppStorage.setOrCreate<User>('user', createEmptyUser())
    }
    AppStorage.setOrCreate<boolean>('_persistenceReady', true)
    logInfo('Persistence', '持久化数据全部加载完成')
  } catch (err) {
    logError('Persistence', '加载持久化数据失败', err)
  }
}

/**
 * 将 AppStorage 中所有关键数据保存到持久化存储
 * 在每次数据变更后调用
 */
export async function saveAllData(): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPrefs()
    for (let i = 0; i < PERSISTENCE_KEYS.length; i++) {
      const key: string = PERSISTENCE_KEYS[i]
      if (AppStorage.has(key)) {
        const value: Object = AppStorage.get<Object>(key) as Object
        if (value !== undefined && value !== null) {
          await prefs.put(key, JSON.stringify(value))
        }
      }
    }
    await prefs.flush()
    logInfo('Persistence', '数据保存完成（全部 key）')
  } catch (err) {
    logError('Persistence', '保存持久化数据失败', err)
  }
}

/**
 * 清除所有持久化数据（用于登出或重置）
 */
export async function clearAllData(): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPrefs()
    for (let i = 0; i < PERSISTENCE_KEYS.length; i++) {
      await prefs.delete(PERSISTENCE_KEYS[i])
    }
    await prefs.flush()
    AppStorage.setOrCreate<boolean>('_persistenceReady', false)
    logInfo('Persistence', '持久化数据已全部清除')
  } catch (err) {
    logError('Persistence', '清除持久化数据失败', err)
  }
}
