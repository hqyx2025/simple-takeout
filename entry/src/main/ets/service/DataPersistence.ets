/**
 * 数据持久化服务
 * 基于 @ohos.data.preferences 实现 AppStorage 关键数据的持久化
 * 确保 App 重启后用户数据不丢失
 */
import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import { User, Order, Address, createEmptyUser } from '../model/Models'
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

/**
 * 订单不从本地持久化恢复，一律返回空数组。
 *
 * 这是有意设计：订单列表必须以后端为准，前端不缓存订单状态，
 * 否则会出现"本地有订单但服务端已取消/超时取消"的不一致。
 * 每次进入相关页面时通过 syncMerchantOrdersFromServer / syncUserOrdersFromServer
 * 从服务端实时拉取最新订单列表。
 *
 * 如果觉得这条规则需要修改，请先确认：
 * - 本地恢复的订单可能状态已过期（超时取消、退款、骑手完成等）
 * - 展示过期订单会让用户做出错误操作（如对已取消订单申请退款）
 */
function normalizeOrderList(value: Object): Object {
  const emptyOrders: Order[] = []
  return emptyOrders
}

/**
 * 地址逐字段归一：旧版本持久化的地址可能缺 address/detail，
 * 而渲染路径直接 `currentAddress.address.trim()`（Index.getDisplayAddress）→ 冷启动白屏。
 */
function normalizeAddress(value: Object): Address {
  const address: Address = value as Address
  if (typeof address.id !== 'number') {
    address.id = 0
  }
  if (typeof address.name !== 'string') {
    address.name = ''
  }
  if (typeof address.phone !== 'string') {
    address.phone = ''
  }
  if (typeof address.address !== 'string') {
    address.address = ''
  }
  if (typeof address.detail !== 'string') {
    address.detail = ''
  }
  if (typeof address.isDefault !== 'boolean') {
    address.isDefault = false
  }
  return address
}

function normalizeAddressList(value: Object): Object {
  if (!Array.isArray(value)) {
    const empty: Address[] = []
    return empty
  }
  const result: Address[] = []
  for (let i = 0; i < value.length; i++) {
    const item: Object = value[i] as Object
    if (item === null || typeof item !== 'object') {
      continue
    }
    result.push(normalizeAddress(item))
  }
  return result
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
  if (key === 'favoriteList' || key === 'couponList') {
    if (Array.isArray(value)) {
      return value
    }
    const empty: Object[] = []
    return empty
  }
  if (key === 'addressList') {
    return normalizeAddressList(value)
  }
  if (key === 'currentAddress') {
    // 兼容持久化的 null（未定位）：保持 null，界面按「未定位」展示
    if (value === null || typeof value !== 'object') {
      return value
    }
    return normalizeAddress(value)
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
    // 同意状态只允许单向升级：本次运行中已同意（内存为 true）时，绝不能被持久化里的空值/旧值覆盖回 false
    const consented: boolean = consentJson === 'true' || AppStorage.get<boolean>('privacyConsent') === true
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
    const restoredUser: User | undefined = AppStorage.get<User>('user')
    const restoredBalance: number = restoredUser !== undefined && restoredUser !== null
      && Number.isFinite(restoredUser.balance) ? restoredUser.balance : 0
    AppStorage.setOrCreate<number>('userBalance', restoredBalance)
    const restoredToken: string = AppStorage.get<string>('authToken') || ''
    const restoredLoggedIn: boolean = AppStorage.get<boolean>('isLoggedIn') || false
    if (restoredLoggedIn && restoredToken === '') {
      AppStorage.setOrCreate<boolean>('isLoggedIn', false)
      AppStorage.setOrCreate<User>('user', createEmptyUser())
      AppStorage.setOrCreate<number>('userBalance', 0)
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
 * 单独持久化隐私政策同意状态。
 * 必须在 loadAllData() 之前调用：loadAllData 会依据该标记决定是否恢复用户/令牌等敏感数据。
 */
export async function savePrivacyConsent(granted: boolean): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPrefs()
    await prefs.put('privacyConsent', granted ? 'true' : 'false')
    await prefs.flush()
    logInfo('Persistence', `隐私政策同意状态已保存：${granted}`)
  } catch (err) {
    logError('Persistence', '保存隐私政策同意状态失败', err)
  }
}

/**
 * 清除所有持久化数据（用于登出或重置）
 */
export async function clearAllData(): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPrefs()
    for (let i = 0; i < PERSISTENCE_KEYS.length; i++) {
      // 隐私同意状态单一权威且单向升级：登出不得清除已同意状态，
      // 否则退出登录后冷启动会重新被判为未同意、又被赶回同意页
      if (PERSISTENCE_KEYS[i] === 'privacyConsent') {
        continue
      }
      await prefs.delete(PERSISTENCE_KEYS[i])
    }
    await prefs.flush()
    AppStorage.setOrCreate<boolean>('_persistenceReady', false)
    logInfo('Persistence', '持久化数据已全部清除')
  } catch (err) {
    logError('Persistence', '清除持久化数据失败', err)
  }
}
