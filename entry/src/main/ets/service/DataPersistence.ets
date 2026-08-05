/**
 * 数据持久化服务
 * 基于 @ohos.data.preferences 实现 AppStorage 关键数据的持久化
 * 确保 App 重启后用户数据不丢失
 */
import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'

const PERSISTENCE_NAME: string = 'takeout_app_data'

// 需要持久化的 AppStorage 键列表
const PERSISTENCE_KEYS: string[] = [
  'isLoggedIn',
  'user',
  'cartItems',
  'orderList',
  'favoriteList',
  'addressList',
  'couponList'
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
 * 从持久化存储中加载所有数据到 AppStorage
 * 通常在 App 启动时调用
 */
export async function loadAllData(): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPrefs()
    for (let i = 0; i < PERSISTENCE_KEYS.length; i++) {
      const key: string = PERSISTENCE_KEYS[i]
      const json: string = await prefs.get(key, '') as string
      if (json !== '') {
        try {
          const value: Object = JSON.parse(json)
          AppStorage.setOrCreate(key, value)
        } catch (parseErr) {
          console.error(`DataPersistence: Failed to parse ${key}`, JSON.stringify(parseErr))
        }
      }
    }
    AppStorage.setOrCreate<boolean>('_persistenceReady', true)
    console.info('DataPersistence: All data loaded successfully')
  } catch (err) {
    console.error('DataPersistence: Failed to load data', JSON.stringify(err))
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
    console.info('DataPersistence: All data saved successfully')
  } catch (err) {
    console.error('DataPersistence: Failed to save data', JSON.stringify(err))
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
    console.info('DataPersistence: All data cleared')
  } catch (err) {
    console.error('DataPersistence: Failed to clear data', JSON.stringify(err))
  }
}