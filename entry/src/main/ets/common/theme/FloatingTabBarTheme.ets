import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';

/** 手机首页悬浮导航的局部样式；低版本保留原有 Tabs。 */
export class FloatingTabBarTheme {
  static readonly HEIGHT: number = 52;
  static readonly SIDE_MARGIN: number = 20;
  static readonly BOTTOM_MARGIN: number = 6;
  static readonly CONTENT_INSET: number = 94;
  static readonly ICON_SIZE: number = 20;
  static readonly LABEL_SIZE: number = 11;

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