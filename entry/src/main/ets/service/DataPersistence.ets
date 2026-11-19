/**
 * 数据持久化服务
 * 普通 Preferences 只保存非敏感设置；账号资料和订单从服务端恢复。
 */
import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import { User, Order, Address, createEmptyUser } from '../model/Models'
import { logInfo, logWarn, logError } from './AppLogger'
import { initializeApiBaseUrl, setAuthTokens, getAuthSessionEpoch } from './HttpClient'
import { fetchCurrentUserApi } from './api/AuthApi'
import { clearAuthTokens, loadAuthTokens, StoredAuthTokens } from './TokenStorage'

const PERSISTENCE_NAME: string = 'takeout_app_data'

// 清理旧版本写入的账号数据，后续不再将这些值保存到普通 Preferences。
const LEGACY_ACCOUNT_KEYS: string[] = [
  'authToken',
  'cartItems',
  'isLoggedIn',
  'user',
  'orderList',
  'favoriteList',
  'addressList',
  'couponList',
  'currentAddress',
  'lastLocationPosition'
]

let prefsInstance: preferences.Preferences | null = null
let legacyAccountDataCleared: boolean = false

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

/** 隐私同意落盘后，仅从安全凭证和当前服务端资料恢复账号。 */
export async function loadAllData(): Promise<void> {
  const startingEpoch: number = getAuthSessionEpoch()
  try {
    const prefs: preferences.Preferences = await getPrefs()
    const consented: boolean = await prefs.get('privacyConsent', '') === 'true'
    AppStorage.setOrCreate<boolean>('privacyConsent', consented)
    if (!consented) {
      AppStorage.setOrCreate<boolean>('_persistenceReady', true)
      return
    }
    let storedTokens: StoredAuthTokens | null = null
    let credentialsRead: boolean = false
    try {
      storedTokens = await loadAuthTokens()
      credentialsRead = true
    } catch (_) {
      logWarn('Persistence', '安全凭证不可用，需要重新登录')
    }
    if (startingEpoch !== getAuthSessionEpoch()) { return }
    const guest: boolean = credentialsRead && (storedTokens?.accessToken ?? '') === '' &&
      (storedTokens?.refreshToken ?? '') === ''
    const backendReady: Promise<string> = initializeApiBaseUrl(async (url: string): Promise<void> => {
      const previousApiBaseUrl: string = await prefs.get('apiBaseUrl', '') as string
      if (startingEpoch !== getAuthSessionEpoch() && !guest) { throw new Error('Startup session changed') }
      if (previousApiBaseUrl !== '' && previousApiBaseUrl !== url && !guest) {
        logWarn('Persistence', '后端数据源已切换，清除旧服务器的安全凭证')
        await clearAuthTokens()
        storedTokens = null
      }
      await removeLegacyAccountData(prefs)
      if (previousApiBaseUrl !== url) {
        await prefs.put('apiBaseUrl', url)
        await prefs.flush()
      }
    })
    if (!guest) {
      await backendReady
      if (startingEpoch !== getAuthSessionEpoch()) { return }
    }
    // 未经本次服务端确认，不恢复旧昵称、余额、订单、收货地址或定位。
    AppStorage.setOrCreate<User>('user', createEmptyUser())
    AppStorage.setOrCreate<boolean>('isLoggedIn', false)
    AppStorage.setOrCreate<number>('userBalance', 0)
    AppStorage.setOrCreate<Order[]>('orderList', [])
    AppStorage.setOrCreate<Address[]>('addressList', [])
    AppStorage.setOrCreate<Address | null>('currentAddress', null)
    AppStorage.setOrCreate<number>('pendingAddressId', 0)
    AppStorage.setOrCreate<string>('addressSyncState', 'idle')
    AppStorage.setOrCreate<Object | null>('lastLocationPosition', null)
    AppStorage.setOrCreate<Object[]>('cartItems', [])
    AppStorage.setOrCreate<Object[]>('favoriteList', [])
    AppStorage.setOrCreate<Object[]>('couponList', [])
    const accessToken: string = storedTokens?.accessToken ?? ''
    setAuthTokens(accessToken, storedTokens?.refreshToken ?? '')
    AppStorage.setOrCreate<string>('authToken', accessToken)
    const restoredEpoch: number = getAuthSessionEpoch()
    if (accessToken !== '') {
      const user: User | undefined = await fetchCurrentUserApi(false)
      if (restoredEpoch !== getAuthSessionEpoch()) { return }
      if (user !== undefined) {
        AppStorage.setOrCreate<User>('user', user)
        AppStorage.setOrCreate<number>('userBalance', Number.isFinite(user.balance) ? user.balance : 0)
        AppStorage.setOrCreate<boolean>('isLoggedIn', true)
      }
    }
    AppStorage.setOrCreate<boolean>('_persistenceReady', true)
    logInfo('Persistence', '已按服务端身份恢复会话，业务数据未从本地恢复')
  } catch (err) {
    logError('Persistence', '加载安全凭证或服务端身份失败', err)
  }
}

async function removeLegacyAccountData(prefs: preferences.Preferences): Promise<void> {
  if (legacyAccountDataCleared) { return }
  for (let i: number = 0; i < LEGACY_ACCOUNT_KEYS.length; i++) {
    await prefs.delete(LEGACY_ACCOUNT_KEYS[i])
  }
  await prefs.flush()
  legacyAccountDataCleared = true
}

/** 保留既有调用入口；业务同步只清理历史缓存，不再将个人资料落盘。 */
export async function saveAllData(): Promise<void> {
  try {
    await removeLegacyAccountData(await getPrefs())
  } catch (err) {
    logError('Persistence', '清理历史账号缓存失败', err)
  }
}

/** 写盘失败必须交还调用方；同意状态未保存前不得恢复凭证或请求业务数据。 */
export async function savePrivacyConsent(granted: boolean): Promise<void> {
  const prefs: preferences.Preferences = await getPrefs()
  await prefs.put('privacyConsent', granted ? 'true' : 'false')
  await prefs.flush()
}

/** 清理在同步调用时即使旧凭证操作失效，避免 await 期间新登录被旧退出清掉。 */
export async function clearAllData(): Promise<void> {
  const clearingTokens: Promise<void> = clearAuthTokens()
  try {
    await clearingTokens
    await removeLegacyAccountData(await getPrefs())
    logInfo('Persistence', '安全凭证与历史账号缓存已清除')
  } catch (err) {
    logError('Persistence', '清除本地账号数据失败', err)
  }
}
