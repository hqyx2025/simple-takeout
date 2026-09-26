/**
 * 透明文字、图标入口和可折叠标题的轻按压反馈。
 * 透明度与可选轻缩放；按钮声明处接 AppMotion.pressAnimation() 控制 100ms 反馈。
 * 系统分段控件与带原生材质的导航按钮仍使用各自的状态动画。
 * （移植自 CampusSports common/theme/SoftPressModifier.ets）
 */
import { AppMotion } from './AppMotion'

export class SoftPressModifier implements AttributeModifier<ButtonAttribute> {
  private static readonly DISABLED_OPACITY: number = 0.45;
  private allowScale: boolean;

  constructor(allowScale: boolean = true) {
    this.allowScale = allowScale;
  }

  public applyNormalAttribute(instance: ButtonAttribute): void {
    instance.stateEffect(false).hoverEffect(HoverEffect.None).opacity(1).scale({ x: 1, y: 1 });
  }

  public applyPressedAttribute(instance: ButtonAttribute): void {
    const scale: number = this.allowScale ? AppMotion.scale(AppMotion.PRESSED_SCALE) : 1;
    instance.opacity(AppMotion.PRESSED_OPACITY).scale({ x: scale, y: scale });
  }

  public applyDisabledAttribute(instance: ButtonAttribute): void {
    instance.opacity(SoftPressModifier.DISABLED_OPACITY).scale({ x: 1, y: 1 });
  }
}
