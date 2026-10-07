import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';

/** 胶囊原生材质；按压光带由导航统一绘制，避免设备材质支持差异。 */
export class FloatingNavigationMaterial implements AttributeModifier<StackAttribute> {
  private material: uiMaterial.ImmersiveMaterial | undefined = FloatingTabBarTheme.material();

  applyNormalAttribute(stack: StackAttribute): void {
    if (this.material !== undefined) {
      stack.systemMaterial(this.material);
    }
  }
}

/** 首页悬浮导航与底部操作区共用的玻璃颜色和布局尺寸。 */
export class FloatingTabBarTheme {
  static readonly GLASS_COLOR: Resource = $r('app.color.navigation_glass');
  static readonly PRESS_LIGHT: Resource = $r('app.color.navigation_press_light');
  static readonly GLASS_BLUR_RADIUS: number = 20;
  static readonly GLASS_SATURATION: number = 1.1;
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
          colorInvert: false, applyShadow: true, interactive: false, lightEffect: null
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
