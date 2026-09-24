/**
 * 透明文字、图标入口和可折叠标题的轻按压反馈。
 * 只改变内容明度，避免默认 Button 状态层覆盖整块透明触区。
 * 不用于有色主按钮、系统分段控件或带原生材质的导航按钮。
 * （移植自 CampusSports common/theme/SoftPressModifier.ets）
 */
export class SoftPressModifier implements AttributeModifier<ButtonAttribute> {
  private static readonly PRESSED_OPACITY: number = 0.72;
  private static readonly DISABLED_OPACITY: number = 0.45;

  public applyNormalAttribute(instance: ButtonAttribute): void {
    instance.stateEffect(false).hoverEffect(HoverEffect.None).opacity(1);
  }

  public applyPressedAttribute(instance: ButtonAttribute): void {
    instance.opacity(SoftPressModifier.PRESSED_OPACITY);
  }

  public applyDisabledAttribute(instance: ButtonAttribute): void {
    instance.opacity(SoftPressModifier.DISABLED_OPACITY);
  }
}