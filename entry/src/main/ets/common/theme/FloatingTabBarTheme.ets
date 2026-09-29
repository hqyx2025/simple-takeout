import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';

/** 光感层与后方的模糊层分开，避免材质覆盖背景模糊。 */
export class FloatingNavigationMaterial implements AttributeModifier<RowAttribute> {
  private material: uiMaterial.ImmersiveMaterial | undefined = FloatingTabBarTheme.material();

  applyNormalAttribute(row: RowAttribute): void {
    if (this.material !== undefined) {
      row.systemMaterial(this.material);
    }
  }
}

/** 手机首页悬浮导航的局部样式；低版本保留原有 Tabs。 */
export class FloatingTabBarTheme {
  static readonly HEIGHT: number = 56;
  static readonly WIDTH: number = 272;
  static readonly SIDE_MARGIN: number = 20;
  static readonly BOTTOM_MARGIN: number = 8;
  static readonly CONTENT_INSET: number = 78;
  static readonly ICON_SIZE: number = 20;
  static readonly LABEL_SIZE: number = 11;

  public static material(): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.sdkApiVersion < 26) { return undefined; }
    try {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK, materialColor: Color.Transparent,
          colorInvert: false, applyShadow: true, interactive: true, lightEffect: { color: undefined }
        });
      }
    } catch (_) {}
    return undefined;
  }

  public static options(): FloatingTabBarStyle | undefined {
    if (deviceInfo.sdkApiVersion < 26) {
      return undefined;
    }
    try {
      if (!uiMaterial.isImmersiveMaterialSupported()) {
        return undefined;
      }
      return {
        barSideMargin: FloatingTabBarTheme.SIDE_MARGIN,
        barBottomMargin: FloatingTabBarTheme.BOTTOM_MARGIN,
        maskHeight: 0,
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          materialColor: Color.Transparent,
          colorInvert: false,
          applyShadow: false,
          interactive: true,
          lightEffect: {}
        })
      };
    } catch (err) {
      return undefined;
    }
  }
}
