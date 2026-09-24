import { common } from '@kit.AbilityKit';
import { display, mediaquery, window } from '@kit.ArkUI';

const BREAKPOINT_XS: string = 'xs';
const BREAKPOINT_SM: string = 'sm';
const BREAKPOINT_MD: string = 'md';
const BREAKPOINT_LG: string = 'lg';

const QUERY_SM: string = '(width >= 600vp) and (width < 840vp)';
const QUERY_MD: string = '(width >= 840vp) and (width < 1200vp)';
const QUERY_LG: string = '(width >= 1200vp)';

/** 折叠动画结束后多延迟复核断点，覆盖最终窗口尺寸。 */
const RECHECK_DELAYS: Array<number> = [200, 500, 1000];

/** 兜底判定用的"明显为大屏"物理宽度阈值（px）：展开态内屏远大于折叠态外屏。 */
const WIDE_PHYSICAL_WIDTH_THRESHOLD: number = 1600;

/**
 * 断点工具：输出 xs/sm/md/lg 断点，并提供统一宽屏判定 isWideForLayout()。
 * 宽屏 = 逻辑宽度 ≥840vp（md/lg）或折叠屏当前为展开态；
 * 动态监听窗口尺寸变化与折叠状态变化（分屏/横竖屏/折叠展开），
 * 事件触发后重建 mediaquery 监听并多延迟复核，保证折叠/展开时布局实时切换。
 * 断点以真实窗口宽度（px ÷ 密度）为准，mediaquery 仅作为事件触发源与兜底。
 * （移植自 CampusSports common/utils/BreakpointSystem.ets）
 */
export class BreakpointSystem {
  private currentBreakpoint: string = BREAKPOINT_XS;
  private onBreakpointChange: (breakpoint: string) => void = () => {};
  private lastNotifiedIsWide: boolean | null = null;
  private smListener: mediaquery.MediaQueryListener | null = null;
  private mdListener: mediaquery.MediaQueryListener | null = null;
  private lgListener: mediaquery.MediaQueryListener | null = null;
  private recheckTimer: number = -1;
  private context: common.UIAbilityContext | null = null;
  private mainWindow: window.Window | null = null;
  private hasWindowListener: boolean = false;
  private hasDisplayListeners: boolean = false;
  private windowSizeChangeCallback: (size: window.Size) => void = () => {
  };
  private foldStatusCallback: (foldStatus: display.FoldStatus) => void = () => {
  };
  private foldDisplayModeCallback: (mode: display.FoldDisplayMode) => void = () => {
  };
  private foldStatus: display.FoldStatus = display.FoldStatus.FOLD_STATUS_UNKNOWN;
  private foldStatusKnown: boolean = false;
  private windowPhysicalWidth: number = 0;

  public getCurrentBreakpoint(): string {
    return this.currentBreakpoint;
  }

  /**
   * 统一宽屏判定：逻辑宽度 ≥840vp（md/lg）或折叠屏处于展开态。
   * 所有页面一律调用本方法，禁止各自写 md/lg 判断。
   */
  public isWideForLayout(): boolean {
    if (this.currentBreakpoint === BREAKPOINT_MD || this.currentBreakpoint === BREAKPOINT_LG) {
      return true;
    }
    if (this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED) {
      return true;
    }
    // 兜底：折叠状态接口不可用时，按窗口物理宽度判断是否为展开内屏。
    if (!this.foldStatusKnown && this.windowPhysicalWidth >= WIDE_PHYSICAL_WIDTH_THRESHOLD) {
      return true;
    }
    return false;
  }

  public register(context: common.UIAbilityContext, onBreakpointChange: (breakpoint: string) => void): void {
    this.unregister();
    this.context = context;
    this.onBreakpointChange = onBreakpointChange;
    this.lastNotifiedIsWide = null;
    this.createListeners();
    this.scheduleRecheck(0);
    this.registerWindowAndDisplayListeners();
  }

  public unregister(): void {
    if (this.recheckTimer >= 0) {
      clearTimeout(this.recheckTimer);
      this.recheckTimer = -1;
    }
    this.removeListeners();
    this.unregisterWindowAndDisplayListeners();
  }

  private createListeners(): void {
    this.smListener = mediaquery.matchMediaSync(QUERY_SM);
    this.mdListener = mediaquery.matchMediaSync(QUERY_MD);
    this.lgListener = mediaquery.matchMediaSync(QUERY_LG);
    this.smListener.on('change', () => {
      this.refreshBreakpoints();
    });
    this.mdListener.on('change', () => {
      this.refreshBreakpoints();
    });
    this.lgListener.on('change', () => {
      this.refreshBreakpoints();
    });
  }

  private removeListeners(): void {
    this.smListener?.off('change');
    this.mdListener?.off('change');
    this.lgListener?.off('change');
    this.smListener = null;
    this.mdListener = null;
    this.lgListener = null;
  }

  /**
   * 注册折叠状态/显示模式监听（回调绑定到本实例，off 时只移除自己的回调），
   * 并立即用真实窗口尺寸做一次权威重算。
   */
  private registerWindowAndDisplayListeners(): void {
    this.foldStatusCallback = (foldStatus: display.FoldStatus) => {
      this.updateFoldStatus(foldStatus);
      this.refreshBreakpoints();
    };
    this.foldDisplayModeCallback = (mode: display.FoldDisplayMode) => {
      this.updateFoldMode(mode);
      this.refreshBreakpoints();
    };
    try {
      display.on('foldStatusChange', this.foldStatusCallback);
      this.hasDisplayListeners = true;
    } catch (err) {
      this.hasDisplayListeners = false;
    }
    try {
      display.on('foldDisplayModeChange', this.foldDisplayModeCallback);
      this.hasDisplayListeners = true;
    } catch (err) {
      // 模拟器/部分设备不支持该接口时静默降级，窗口尺寸监听仍生效。
    }
    this.refreshFromWindowSize();
  }

  private unregisterWindowAndDisplayListeners(): void {
    if (this.hasWindowListener && this.mainWindow !== null) {
      try {
        this.mainWindow.off('windowSizeChange', this.windowSizeChangeCallback);
      } catch (err) {
      }
    }
    this.mainWindow = null;
    this.hasWindowListener = false;

    if (this.hasDisplayListeners) {
      try {
        display.off('foldStatusChange', this.foldStatusCallback);
      } catch (err) {
      }
      try {
        display.off('foldDisplayModeChange', this.foldDisplayModeCallback);
      } catch (err) {
      }
    }
    this.hasDisplayListeners = false;
    this.context = null;
  }

  private updateFoldStatus(status: display.FoldStatus): void {
    this.foldStatus = status;
    this.foldStatusKnown = status === display.FoldStatus.FOLD_STATUS_EXPANDED ||
      status === display.FoldStatus.FOLD_STATUS_FOLDED ||
      status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED;
    this.notifyLayoutChange();
  }

  /** foldDisplayModeChange 兜底：仅在折叠状态未知时用显示模式推断展开态。 */
  private updateFoldMode(mode: display.FoldDisplayMode): void {
    if (this.foldStatusKnown) {
      return;
    }
    if (mode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      this.foldStatus = display.FoldStatus.FOLD_STATUS_EXPANDED;
      this.foldStatusKnown = true;
      this.notifyLayoutChange();
    }
  }

  /**
   * 用真实窗口尺寸重算断点：getLastWindow 始终取当前主窗口并挂窗口尺寸监听，
   * 以 px ÷ 密度得到 vp 宽度，再按 600/840/1200vp 原阈值判定。
   * mediaquery 在部分场景（入口页创建初期、模拟器折叠）matches 不刷新，
   * 因此以窗口尺寸为权威来源；mediaquery 只负责触发与兜底。
   */
  private refreshFromWindowSize(): void {
    const context: common.UIAbilityContext | null = this.context;
    if (context === null) {
      return;
    }
    window.getLastWindow(context).then((win: window.Window) => {
      if (this.context !== context) {
        return;
      }
      this.attachWindowListener(win);
      const props: window.WindowProperties = win.getWindowProperties();
      const widthPx: number = props.windowRect.width;
      this.windowPhysicalWidth = widthPx;
      const density: number = display.getDefaultDisplaySync().densityPixels;
      if (widthPx > 0 && density > 0) {
        const bp: string = this.getBreakpointFromWidth(widthPx / density);
        this.applyBreakpoint(bp);
      }
      this.queryFoldStatus();
    }).catch(() => {
      // getLastWindow 不可用时的兜底：退回 mediaquery matches 判定。
      this.handleBreakpointChange();
    });
  }

  private queryFoldStatus(): void {
    try {
      this.updateFoldStatus(display.getFoldStatus());
    } catch (err) {
    }
  }

  private attachWindowListener(win: window.Window): void {
    if (this.mainWindow !== win) {
      if (this.mainWindow !== null && this.hasWindowListener) {
        try {
          this.mainWindow.off('windowSizeChange', this.windowSizeChangeCallback);
        } catch (err) {
        }
      }
      this.mainWindow = win;
      this.hasWindowListener = false;
    }
    if (!this.hasWindowListener) {
      this.windowSizeChangeCallback = (size: window.Size) => {
        this.refreshBreakpoints();
      };
      win.on('windowSizeChange', this.windowSizeChangeCallback);
      this.hasWindowListener = true;
    }
  }

  /**
   * 事件触发后的统一刷新：重建 mediaquery 监听（作为后续触发源），
   * 重置多延迟复核，并用真实窗口尺寸重算断点。
   */
  private refreshBreakpoints(): void {
    if (this.recheckTimer >= 0) {
      clearTimeout(this.recheckTimer);
      this.recheckTimer = -1;
    }
    this.removeListeners();
    this.createListeners();
    this.scheduleRecheck(0);
    this.refreshFromWindowSize();
  }

  private getBreakpointFromWidth(widthVp: number): string {
    if (widthVp >= 1200) {
      return BREAKPOINT_LG;
    }
    if (widthVp >= 840) {
      return BREAKPOINT_MD;
    }
    if (widthVp >= 600) {
      return BREAKPOINT_SM;
    }
    return BREAKPOINT_XS;
  }

  private applyBreakpoint(breakpoint: string): void {
    if (breakpoint !== this.currentBreakpoint) {
      this.currentBreakpoint = breakpoint;
    }
    this.notifyLayoutChange();
  }

  /** 宽屏判定（isWideForLayout）变化时通知页面，即使断点字符串未变（折叠状态变化）。 */
  private notifyLayoutChange(): void {
    const wide: boolean = this.isWideForLayout();
    if (wide !== this.lastNotifiedIsWide) {
      this.lastNotifiedIsWide = wide;
      this.onBreakpointChange(this.currentBreakpoint);
    }
  }

  /**
   * 折叠动画结束后多延迟复核：按 200/500/1000ms 重建监听并重读真实窗口尺寸，
   * 确保最终布局对应折叠/展开动画结束后的最终尺寸。
   */
  private scheduleRecheck(attempt: number): void {
    if (attempt >= RECHECK_DELAYS.length) {
      return;
    }
    this.recheckTimer = setTimeout(() => {
      this.recheckTimer = -1;
      this.removeListeners();
      this.createListeners();
      this.refreshFromWindowSize();
      this.scheduleRecheck(attempt + 1);
    }, RECHECK_DELAYS[attempt]);
  }

  /** mediaquery 兜底判定（仅在 getLastWindow 不可用时使用）。 */
  private handleBreakpointChange(): void {
    let nextBreakpoint: string = BREAKPOINT_XS;
    if (this.lgListener?.matches === true) {
      nextBreakpoint = BREAKPOINT_LG;
    } else if (this.mdListener?.matches === true) {
      nextBreakpoint = BREAKPOINT_MD;
    } else if (this.smListener?.matches === true) {
      nextBreakpoint = BREAKPOINT_SM;
    }
    this.applyBreakpoint(nextBreakpoint);
  }
}