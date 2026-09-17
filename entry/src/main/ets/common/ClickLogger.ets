/**
 * 全局点击日志。
 *
 * 用 ArkUI 的 UIObserver 监听 willClick：一次注册覆盖全工程所有 onClick（含以后新增的按钮），
 * 不需要逐个按钮埋点。日志通过 AppLogger 写出，因此自带 [page=<当前页面>] 标识，
 * 可以在 hilog / filesDir/log/app-YYYY-MM-DD.log 里还原"用户在哪个页面点了哪个控件"。
 *
 * 注意：Observer 需要窗口的 UIContext，因此在 EntryAbility 内容加载完成后再注册。
 */
import { UIContext } from '@kit.ArkUI'
import { logInfo } from '../service/AppLogger'

let registered: boolean = false

/** 取被点击组件的 id（FrameNode inspector 信息里的 id 字段）；没有 id 时返回空串。 */
function componentIdOf(node?: FrameNode): string {
  if (node === undefined) {
    return ''
  }
  try {
    const info: string = JSON.stringify(node.getInspectorInfo())
    const matched: RegExpMatchArray | null = info.match(/"id":"([^"]+)"/)
    return matched === null ? '' : matched[1]
  } catch (e) {
    return ''
  }
}

/**
 * 注册全局点击日志（重复调用只生效一次）。
 * @param context 主窗口的 UIContext
 */
export function registerClickLogging(context: UIContext): void {
  if (registered) {
    return
  }
  try {
    context.getUIObserver().on('willClick', (event: ClickEvent, node?: FrameNode) => {
      const componentId: string = componentIdOf(node)
      const position: string = `x=${Math.round(event.displayX)} y=${Math.round(event.displayY)}`
      logInfo('Click', componentId === '' ? `用户点击 ${position}` : `用户点击 ${componentId} ${position}`)
    })
    registered = true
    logInfo('Click', '全局点击日志已注册')
  } catch (e) {
    registered = false
    logInfo('Click', `全局点击日志注册失败：${JSON.stringify(e)}`)
  }
}
