/**
 * 导航连点节流。
 * 快速连点同一入口会在路由栈里压入两层同名页面，返回一次后仍停留在该页面
 * （典型：连点"定位"进入两层 LocationPage，定位完成返回后看到的还是定位页）。
 * 所有 pushUrl/back 都经 UiNavigation 收口，因此在这里统一丢弃窗口内的重复请求。
 */

/** 同一目标页的重复跳转窗口 */
export const PUSH_THROTTLE_MS: number = 800
/** 返回连点窗口：比跳转更短，避免影响用户连续返回上一层 */
export const BACK_THROTTLE_MS: number = 300

export class NavigationThrottle {
  private pushWindowMs: number
  private backWindowMs: number
  private lastUrl: string = ''
  private lastPushAt: number = 0
  private lastBackAt: number = 0

  constructor(pushWindowMs: number = PUSH_THROTTLE_MS, backWindowMs: number = BACK_THROTTLE_MS) {
    this.pushWindowMs = pushWindowMs
    this.backWindowMs = backWindowMs
  }

  /** true = 放行本次跳转；窗口内跳往同一页面视为连点，返回 false */
  allowPush(url: string, now: number): boolean {
    if (url === this.lastUrl && now - this.lastPushAt < this.pushWindowMs) {
      return false
    }
    this.lastUrl = url
    this.lastPushAt = now
    return true
  }

  /** true = 放行本次返回；窗口内重复返回视为连点，返回 false */
  allowBack(now: number): boolean {
    if (now - this.lastBackAt < this.backWindowMs) {
      return false
    }
    this.lastBackAt = now
    return true
  }

  /** 路由栈发生变化（已返回上一层）后，允许再次进入同一页面 */
  reset(): void {
    this.lastUrl = ''
    this.lastPushAt = 0
  }
}

export const navigationThrottle: NavigationThrottle = new NavigationThrottle()