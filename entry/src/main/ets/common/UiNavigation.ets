/**
 * API 24 UI 导航与提示适配层。
 * 通过当前 UIContext 调用新路由/提示 API，避免继续依赖已废弃的全局 router/promptAction。
 * UIContext.getCallingScopeUIContext() 在 await 后可能无法取得调用作用域，因此缓存首次获取到的上下文，
 * 确保异步请求完成后的返回、跳转和 Toast 仍然使用同一个页面上下文。
 */
import { UIContext } from '@kit.ArkUI'

let cachedUiContext: UIContext | undefined = undefined

function resolveUiContext(): UIContext | undefined {
  const callingContext: UIContext | undefined = UIContext.getCallingScopeUIContext()
  if (callingContext !== undefined) {
    cachedUiContext = callingContext
    return callingContext
  }
  return cachedUiContext
}

export interface RouterOptionsCompat {
  url: string
}

export interface ToastOptionsCompat {
  message: string
  duration?: number
}

export function navigate(url: string): void {
  const context: UIContext | undefined = resolveUiContext()
  if (context !== undefined) {
    try {
      context.getRouter().pushUrl({ url })
    } catch (_) {
      // 页面销毁或路由栈异常时忽略导航请求，避免影响当前页面生命周期。
    }
  }
}

export function goBack(): void {
  const context: UIContext | undefined = resolveUiContext()
  if (context !== undefined) {
    try {
      context.getRouter().back()
    } catch (_) {
      // 页面已经退出时忽略返回请求。
    }
  }
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
