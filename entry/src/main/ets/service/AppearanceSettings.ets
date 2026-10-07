import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { logWarn } from './AppLogger'

const STORE_NAME: string = 'takeout_appearance'

function validMode(mode: string): string {
  return mode === 'light' || mode === 'dark' ? mode : 'system'
}

function validScale(scale: number): number {
  return scale === 0.9 || scale === 1 || scale === 1.15 || scale === 1.3 ? scale : 1
}

function validNavigationMode(mode: string): string {
  return mode === 'left' || mode === 'right' || mode === 'center' ? mode : 'auto'
}

function apply(context: common.UIAbilityContext, mode: string, scale: number): void {
  const application: common.ApplicationContext = context.getApplicationContext()
  application.setColorMode(mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    : mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
  application.setFontSizeScale(scale)
}

/** 外观偏好独立于账号数据，退出登录和清理业务缓存不会重置它。 */
export async function loadAppearanceSettings(context: common.UIAbilityContext): Promise<void> {
  let mode: string = 'system'
  let scale: number = 1
  let navigationMode: string = 'auto'
  try {
    const prefs: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME)
    mode = validMode(await prefs.get('colorMode', 'system') as string)
    scale = validScale(await prefs.get('fontScale', 1) as number)
    navigationMode = validNavigationMode(await prefs.get('navigationHandMode', 'auto') as string)
  } catch (_) {
    logWarn('Settings', '读取外观设置失败，使用默认设置')
  }
  AppStorage.setOrCreate<string>('appearanceColorMode', mode)
  AppStorage.setOrCreate<number>('appearanceFontScale', scale)
  AppStorage.setOrCreate<string>('navigationHandMode', navigationMode)
}

/** 颜色模式要求窗口内容已加载，启动恢复在 loadContent 成功后调用。 */
export function applyAppearanceSettings(context: common.UIAbilityContext): void {
  apply(context, AppStorage.get<string>('appearanceColorMode') ?? 'system',
    AppStorage.get<number>('appearanceFontScale') ?? 1)
}

export async function saveAppearanceSettings(context: common.UIAbilityContext,
  mode: string, scale: number, navigationMode: string): Promise<void> {
  const previousMode: string = AppStorage.get<string>('appearanceColorMode') ?? 'system'
  const previousScale: number = AppStorage.get<number>('appearanceFontScale') ?? 1
  const previousNavigationMode: string = AppStorage.get<string>('navigationHandMode') ?? 'auto'
  const nextMode: string = validMode(mode)
  const nextScale: number = validScale(scale)
  const nextNavigationMode: string = validNavigationMode(navigationMode)
  const prefs: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME)
  try {
    apply(context, nextMode, nextScale)
    await prefs.put('colorMode', nextMode)
    await prefs.put('fontScale', nextScale)
    await prefs.put('navigationHandMode', nextNavigationMode)
    await prefs.flush()
    AppStorage.setOrCreate<string>('appearanceColorMode', nextMode)
    AppStorage.setOrCreate<number>('appearanceFontScale', nextScale)
    AppStorage.setOrCreate<string>('navigationHandMode', nextNavigationMode)
  } catch (_) {
    // 保存失败恢复当前外观及偏好，避免界面显示“已保存”但下次启动丢失。
    apply(context, previousMode, previousScale)
    await prefs.put('colorMode', previousMode)
    await prefs.put('fontScale', previousScale)
    await prefs.put('navigationHandMode', previousNavigationMode)
    await prefs.flush()
    throw new Error('外观设置保存失败')
  }
}
