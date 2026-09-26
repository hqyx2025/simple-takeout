import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { loadAllData } from '../service/DataPersistence';
import { initLogger, setPrivacyConsent, logInfo } from '../service/AppLogger';
import { registerClickLogging } from '../common/ClickLogger';
import { User, UserRole } from '../model/Models';
import { AppMotion } from '../common/theme/AppMotion';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindowStage: window.WindowStage | null = null
  private mainWindow: window.Window | null = null
  private windowContentReady: boolean = false
  private persistenceLoaded: boolean = false

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppMotion.init()
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
    AppMotion.dispose()
    hilog.info(DOMAIN, '测试标签', '%{public}s', '破坏能力 Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, '测试标签', '%{public}s', 'Ability onWindowStageCreate');

    this.mainWindowStage = windowStage
    this.mainWindow = windowStage.getMainWindowSync()
    this.loadMainContentIfReady()
  }

  // 保留系统安全区，让窗口底色延续到手势区域，不额外挤压 Tab 内容。
  private updateWindowAppearance(): void {
    if (this.mainWindow === null || !this.windowContentReady) {
      return
    }
    try {
      const surface: string = '#' + this.context.resourceManager.getColorByNameSync('home_surface')
        .toString(16).padStart(8, '0')
      const content: string = '#' + this.context.resourceManager.getColorByNameSync('home_text')
        .toString(16).padStart(8, '0')
      this.mainWindow.setWindowBackgroundColor(surface)
      this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: surface,
        navigationBarColor: surface,
        statusBarContentColor: content,
        navigationBarContentColor: content
      }).catch(() => {
        hilog.warn(DOMAIN, 'WindowAppearance', '当前窗口不支持系统栏配色，保留系统默认值');
      })
    } catch (_) {
      hilog.warn(DOMAIN, 'WindowAppearance', '窗口配色暂不可用，保留系统安全区');
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.updateWindowAppearance()
  }

  private loadMainContentIfReady(): void {
    if (!this.persistenceLoaded || this.mainWindowStage === null) {
      return
    }
    const stage: window.WindowStage = this.mainWindowStage
    this.mainWindowStage = null
    const loggedIn: boolean = AppStorage.get<boolean>('isLoggedIn') || false
    const user: User | undefined = AppStorage.get<User>('user')
    const initialPage: string = loggedIn && user !== undefined && user.role === UserRole.ADMIN
      ? 'pages/AdminCenterPage'
      : 'pages/Index'
    logInfo('EntryAbility', `启动页面=${initialPage} loggedIn=${loggedIn}`)
    stage.loadContent(initialPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, '测试标签', '无法加载内容。原因： %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, '测试标签', '内容加载成功。');
      // Window 背景 API 必须在 loadContent 成功之后调用。
      this.windowContentReady = true
      this.updateWindowAppearance()
      // 内容就绪后注册全局点击日志：之后每次用户点击都会记录当前页面标识
      try {
        registerClickLogging(stage.getMainWindowSync().getUIContext());
      } catch (e) {
        hilog.error(DOMAIN, '测试标签', '注册全局点击日志失败：%{public}s', JSON.stringify(e));
      }
    });
  }

  onWindowStageDestroy(): void {
    this.windowContentReady = false
    this.mainWindow = null
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, '测试标签', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    AppMotion.refresh()
    this.updateWindowAppearance()
    // Ability has brought to foreground
    hilog.info(DOMAIN, '测试标签', '%{public}s', '前景能力');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, '测试标签', '%{public}s', '后台能力');
  }
}
