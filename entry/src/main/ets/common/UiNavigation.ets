/**
 * API 24 UI 导航与提示适配层。
 * 通过当前 UIContext 调用新路由/提示 API，避免继续依赖已废弃的全局 router/promptAction。
 */
import { UIContext } from '@kit.ArkUI'

export interface RouterOptionsCompat {
  url: string
}

export interface ToastOptionsCompat {
  message: string
  duration?: number
}

export function navigate(url: string): void {
  const context: UIContext | undefined = UIContext.getCallingScopeUIContext()
  if (context !== undefined) {
    try {
      context.getRouter().pushUrl({ url })
    } catch (_) {
      // 页面销毁或路由栈异常时忽略导航请求，避免影响当前页面生命周期。
    }
  }
}

export function goBack(): void {
  const context: UIContext | undefined = UIContext.getCallingScopeUIContext()
  if (context !== undefined) {
    try {
      context.getRouter().back()
    } catch (_) {
      // 页面已经退出时忽略返回请求。
    }
  }
}

export function showToast(message: string, duration?: number): void {
  const context: UIContext | undefined = UIContext.getCallingScopeUIContext()
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
