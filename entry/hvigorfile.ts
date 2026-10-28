import { HvigorNode } from '@ohos/hvigor';
import { hapTasks, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [{
    pluginId: 'takeout.quick-login',
    apply(node: HvigorNode) {
      node.afterNodeEvaluate(() => {
        const context = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
        const profile = context.getBuildProfileOpt();
        const testConfig = process.env.TAKEOUT_UI_TEST_CONFIG;
        const configPath = testConfig || resolve(context.getModulePath(), '../quick-login.local.json');
        let config = '';
        // 私有测试凭据只注入 debug，release 不读取本机配置。
        if (context.getBuildMode() === 'debug' && existsSync(configPath)) {
          try {
            config = JSON.stringify(JSON.parse(readFileSync(configPath, 'utf8')));
          } catch (_) {
            throw new Error('quick-login.local.json 格式错误，请检查本机快捷登录配置');
          }
        }
        profile.buildOption = profile.buildOption || {};
        profile.buildOption.arkOptions = profile.buildOption.arkOptions || {};
        profile.buildOption.arkOptions.buildProfileFields = {
          ...profile.buildOption.arkOptions.buildProfileFields,
          // Hvigor 将字段直接放进单引号字面量，需要先转义。
          QUICK_LOGIN_CONFIG: config.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
            .replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029'),
          UI_TEST_BASE_URL: context.getBuildMode() === 'debug' && testConfig && config ? JSON.parse(config).baseUrl : ''
        };
        context.setBuildProfileOpt(profile);
      });
    }
  }]
}
