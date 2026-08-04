/**
 * 偏好存储工具
 * 基于 @ohos.data.preferences 实现
 * 用于存储搜索历史等轻量数据
 */
import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'

const PREFERENCES_NAME: string = 'takeout_preferences'
const SEARCH_HISTORY_KEY: string = 'search_history'
const MAX_HISTORY_SIZE: number = 10

// 获取preferences实例
async function getPreferences(): Promise<preferences.Preferences> {
  const context: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('appContext') as common.UIAbilityContext
  if (context === null || context === undefined) {
    throw new Error('AppContext not available')
  }
  return await preferences.getPreferences(context, PREFERENCES_NAME)
}

// 获取搜索历史
export async function getSearchHistory(): Promise<string[]> {
  try {
    const prefs: preferences.Preferences = await getPreferences()
    const history: string = await prefs.get(SEARCH_HISTORY_KEY, '') as string
    if (history === '') return []
    return history.split(',')
  } catch (e) {
    return []
  }
}

// 添加搜索历史
export async function addSearchHistory(keyword: string): Promise<void> {
  if (keyword.trim() === '') return
  try {
    const prefs: preferences.Preferences = await getPreferences()
    let history: string[] = await getSearchHistory()

    // 去重
    history = history.filter(item => item !== keyword)
    // 添加到头部
    history.unshift(keyword)
    // 限制数量
    if (history.length > MAX_HISTORY_SIZE) {
      history = history.slice(0, MAX_HISTORY_SIZE)
    }

    await prefs.put(SEARCH_HISTORY_KEY, history.join(','))
    await prefs.flush()
  } catch (e) {
    // 忽略错误
  }
}

// 清空搜索历史
export async function clearSearchHistory(): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPreferences()
    await prefs.delete(SEARCH_HISTORY_KEY)
    await prefs.flush()
  } catch (e) {
    // 忽略错误
  }
}

// 保存通用键值对
export async function savePreference(key: string, value: string): Promise<void> {
  try {
    const prefs: preferences.Preferences = await getPreferences()
    await prefs.put(key, value)
    await prefs.flush()
  } catch (e) {
    // 忽略错误
  }
}

// 获取通用键值对
export async function getPreference(key: string, defaultValue: string = ''): Promise<string> {
  try {
    const prefs: preferences.Preferences = await getPreferences()
    return await prefs.get(key, defaultValue) as string
  } catch (e) {
    return defaultValue
  }
}
