import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { MapsInitializer } from '@amap/amap_lbs_map3d';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';
import { loadAllData } from '../service/DataPersistence';
import { initLogger, logInfo, logWarn } from '../service/AppLogger';
import { AMAP_CONFIG } from '../common/Constants';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 将 AbilityContext 存入 AppStorage，供持久化服务使用
    AppStorage.setOrCreate('appContext', this.context);
    // 初始化应用日志服务（控制台 + 日志文件）
    initLogger();
    logInfo('EntryAbility', 'Ability onCreate');
    // 初始化高德地图SDK（隐私合规 + API Key）
    this.initAMapSDK();
    // 异步加载持久化数据
    loadAllData();
  }

  // 初始化高德地图SDK：必须在任何地图SDK接口调用之前完成隐私合规声明与Key设置
  private initAMapSDK(): void {
    try {
      // 1. 隐私政策合规声明（必须在 MapView 创建之前调用）
      MapsInitializer.updatePrivacyShow(AMapPrivacyShowStatus.DidShow, AMapPrivacyInfoStatus.DidContain, this.context);
      MapsInitializer.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, this.context);
      // 2. 设置高德地图SDK Key（需在高德开放平台创建“HarmonyOS”平台应用获取）
      MapsInitializer.setApiKey(AMAP_CONFIG.MAP_SDK_KEY);
      logInfo('EntryAbility', '高德地图SDK初始化完成');
    } catch (err) {
      logWarn('EntryAbility', `高德地图SDK初始化失败: ${JSON.stringify(err)}`);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}