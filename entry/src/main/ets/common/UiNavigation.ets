/**
 * API 24 UI 导航与提示适配层。
 * 通过当前 UIContext 调用新路由/提示 API，避免继续依赖已废弃的全局 router/promptAction。
 * UIContext.getCallingScopeUIContext() 在 await 后可能无法取得调用作用域，因此缓存首次获取到的上下文，
 * 确保异步请求完成后的返回、跳转和 Toast 仍然使用同一个页面上下文。
 */
import { UIContext } from '@kit.ArkUI'
import { navigationThrottle } from './NavigationThrottle'
import { setCurrentPage, setPageResolver } from '../service/AppLogger'

let cachedUiContext: UIContext | undefined = undefined

function resolveUiContext(): UIContext | undefined {
  const callingContext: UIContext | undefined = UIContext.getCallingScopeUIContext()
  if (callingContext !== undefined) {
    cachedUiContext = callingContext
    return callingContext
  }
  return cachedUiContext
}

/**
 * 读取路由栈顶页面名（如 pages/CartPage）。
 * 直接读 UIContext 路由状态，因此系统返回键、replaceUrl、冷启动都准确；
 * 非 UI 作用域或路由未就绪时返回空串，由 AppLogger 回退到上一次已知页面。
 */
function readRouterPageName(): string {
  const context: UIContext | undefined = resolveUiContext()
  if (context === undefined) {
    return ''
  }
  try {
    const state = context.getRouter().getState()
    return state.name ?? ''
  } catch (_) {
    return ''
  }
}

// 注册给日志服务：每条日志写之前实时解析页面标识（点击/操作日志因此自动带上页面）。
setPageResolver((): string => readRouterPageName())

export interface RouterOptionsCompat {
  url: string
}

export interface ToastOptionsCompat {
  message: string
  duration?: number
}

export function navigate(url: string): void {
  const context: UIContext | undefined = resolveUiContext()
  if (context === undefined) {
    return
  }
  if (!navigationThrottle.allowPush(url, Date.now())) {
    // 连点同一入口：丢弃重复跳转，避免路由栈里叠两层同名页面。
    return
  }
  try {
    context.getRouter().pushUrl({ url })
    setCurrentPage(url)
  } catch (_) {
    // 页面销毁或路由栈异常时忽略导航请求，避免影响当前页面生命周期。
    navigationThrottle.reset()
  }
}

export function goBack(): void {
  const context: UIContext | undefined = resolveUiContext()
  if (context === undefined) {
    return
  }
  if (!navigationThrottle.allowBack(Date.now())) {
    // 连点返回：丢弃重复返回，避免一次点击弹出两层页面。
    return
  }
  try {
    context.getRouter().back()
  } catch (_) {
    // 页面已经退出时忽略返回请求。
  }
  navigationThrottle.reset()
}

export function showToast(message: string, duration?: number): void {
  const context: UIContext | undefined = resolveUiContext()
  if (context !== undefined) {
    const options: ToastOptionsCompat = duration === undefined
      ? { message }
      : { message, duration }
    try {
      context.getPromptAction().showToast(options)
    } catch (_) {
      // 当前 UI 实例不可用时忽略提示。
    }
  }
}

class RouterCompat {
  pushUrl(options: RouterOptionsCompat): void {
    navigate(options.url)
  }

  replaceUrl(options: RouterOptionsCompat): void {
    const context: UIContext | undefined = resolveUiContext()
    if (context !== undefined) {
      try {
        context.getRouter().replaceUrl({ url: options.url })
        setCurrentPage(options.url)
      } catch (_) {
        navigate(options.url)
      }
    }
  }

  back(): void {
    goBack()
  }
}

class PromptCompat {
  showToast(options: ToastOptionsCompat): void {
    showToast(options.message, options.duration)
  }
}

export const routerCompat: RouterCompat = new RouterCompat()
export const promptCompat: PromptCompat = new PromptCompat()
