import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { loadAllData } from '../service/DataPersistence';
import { initLogger, setPrivacyConsent, logInfo } from '../service/AppLogger';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindowStage: window.WindowStage | null = null
  private persistenceLoaded: boolean = false

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, '测试标签', '设置颜色模式失败。原因：%{public}s  Failed to set colorMode. Cause: ', JSON.stringify(err));
    }
    hilog.info(DOMAIN, '测试标签', '%{public}s', '创建能力 Ability onCreate');
    // 将 AbilityContext 存入 AppStorage，供持久化服务使用
    AppStorage.setOrCreate('appContext', this.context);
    logInfo('EntryAbility', '创建能力 Ability onCreate');
    // 先恢复持久化登录态，再加载页面，避免启动瞬间先渲染主页后才覆盖登录页。
    loadAllData().then(() => {
      const consented: boolean = AppStorage.get<boolean>('privacyConsent') || false
      setPrivacyConsent(consented)
      if (consented) {
        initLogger()
      }
      this.persistenceLoaded = true
      this.loadMainContentIfReady()
    }).catch((err: Object) => {
      hilog.error(DOMAIN, '测试标签', '加载持久化数据失败：%{public}s', JSON.stringify(err));
      this.persistenceLoaded = true
      this.loadMainContentIfReady()
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, '测试标签', '%{public}s', '破坏能力 Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, '测试标签', '%{public}s', 'Ability onWindowStageCreate');

    this.mainWindowStage = windowStage
    this.loadMainContentIfReady()
  }

  private loadMainContentIfReady(): void {
    if (!this.persistenceLoaded || this.mainWindowStage === null) {
      return
    }
    const stage: window.WindowStage = this.mainWindowStage
    this.mainWindowStage = null
    stage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, '测试标签', '无法加载内容。原因： %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, '测试标签', '内容加载成功。');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, '测试标签', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, '测试标签', '%{public}s', '前景能力');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, '测试标签', '%{public}s', '后台能力');
  }
}
