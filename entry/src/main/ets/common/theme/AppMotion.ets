import { accessibility } from '@kit.AccessibilityKit'

/** Shared motion timings; system reduced-motion changes never delay a business callback. */
export class AppMotion {
  static readonly PRESS: number = 100
  static readonly TAB: number = 220
  static readonly ENTER: number = 240
  static readonly EXIT: number = 180
  static readonly DIALOG_ENTER: number = 200
  static readonly DIALOG_EXIT: number = 150
  static readonly PAGE_OFFSET: number = 12
  static readonly RETURN_OFFSET: number = 6
  static readonly PRESSED_SCALE: number = 0.98
  static readonly PRESSED_OPACITY: number = 0.76

  private static reducedMotion: boolean = false
  private static listening: boolean = false

  /** Call once from EntryAbility.onCreate; safe to call again. */
  static init(): void {
    AppMotion.refresh()
    if (AppMotion.listening) {
      return
    }
    try {
      // API 23+: keep the same named callback for registration and removal.
      accessibility.onAnimationReduceStateChange(AppMotion.onSystemMotionChange)
      AppMotion.listening = true
    } catch (_) {
      // Unsupported devices keep native system animation scaling and can retry on a later init.
    }
  }

  /** Re-read on foreground, including changes made while this ability was suspended. */
  static refresh(): void {
    try {
      AppMotion.reducedMotion = accessibility.isAnimationReduceEnabledSync()
    } catch (_) {
      // Preserve the last known preference if the system service is temporarily unavailable.
    }
    AppStorage.setOrCreate<boolean>('appReduceMotion', AppMotion.reducedMotion)
  }

  static dispose(): void {
    if (!AppMotion.listening) {
      return
    }
    try {
      accessibility.offAnimationReduceStateChange(AppMotion.onSystemMotionChange)
    } catch (_) {
      // The ability is already shutting down; motion must not block teardown.
    }
    AppMotion.listening = false
  }

  private static onSystemMotionChange(enabled: boolean): void {
    AppMotion.reducedMotion = enabled
    AppStorage.setOrCreate<boolean>('appReduceMotion', enabled)
  }

  static isReduced(): boolean {
    return AppMotion.reducedMotion
  }

  static duration(milliseconds: number): number {
    return AppMotion.reducedMotion ? 0 : milliseconds
  }

  static distance(vp: number): number {
    return AppMotion.reducedMotion ? 0 : vp
  }

  static scale(value: number): number {
    return AppMotion.reducedMotion ? 1 : value
  }

  static pressAnimation(): AnimateParam {
    return { duration: AppMotion.duration(AppMotion.PRESS), curve: Curve.EaseOut }
  }

  static pageEnter(type: RouteType): PageTransitionOptions {
    return { type: type, duration: AppMotion.duration(AppMotion.ENTER), curve: Curve.EaseOut }
  }

  static pageExit(type: RouteType): PageTransitionOptions {
    return { type: type, duration: AppMotion.duration(AppMotion.EXIT), curve: Curve.EaseIn }
  }

  /** Appearance/removal is handled by ArkUI; callers run confirm/cancel immediately. */
  static dialogTransition(reduced: boolean): TransitionEffect {
    if (reduced) {
      return TransitionEffect.IDENTITY
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0)
        .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
        .animation({ duration: AppMotion.DIALOG_ENTER, curve: Curve.EaseOut }),
      TransitionEffect.opacity(0)
        .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
        .animation({ duration: AppMotion.DIALOG_EXIT, curve: Curve.EaseIn })
    )
  }

  static scrimTransition(reduced: boolean): TransitionEffect {
    if (reduced) {
      return TransitionEffect.IDENTITY
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).animation({ duration: AppMotion.DIALOG_ENTER, curve: Curve.EaseOut }),
      TransitionEffect.opacity(0).animation({ duration: AppMotion.DIALOG_EXIT, curve: Curve.EaseIn })
    )
  }
}
