/**
 * 登录链路回归（设备端 UiTest）。
 *
 * 前置：应用数据已清空（guest 态），由 host 脚本用
 *   hdc shell bm clean -n com.example.jiandanwaimai -d
 * 布置。用例自己走「隐私同意页 → 登录页」这条链。
 *
 * 为什么值得测：历史上「隐私同意状态存不下来」导致首页数据全空、冷启动不回登录态，
 * 而当时的 UiTest 断言写成了 `!== undefined`（findComponent 未命中返回的是 null），
 * 恒真空跑 → 这个缺陷是靠人肉看图才发现的。
 */
import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, waitAny, openQuickLoginDialog } from './UiTestHelper'

export default function loginFlowTest() {
  describe('LoginFlow', () => {
    it('LoginFlow_guest_consent_then_login_controls', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      // 首次启动落在独立同意页（pages/ConsentPage）；已同意过则直接是登录页
      const consent = await waitAny(driver, ['privacy-accept'], 8000)
      if (isFound(consent)) {
        console.info('[LoginFlow] consent page shown -> accept privacy policy')
        expect(await clickByIdOrText(driver, 'privacy-accept', '同意并继续')).assertTrue()
        await driver.delayMs(3000)
      } else {
        console.info('[LoginFlow] no consent page (already granted)')
      }

      // 登录表单三个控件必须可被驱动找到
      requireComponent(await driver.waitForComponent(ON.id('login-phone'), 15000), 'login-phone')
      requireComponent(await driver.findComponent(ON.id('login-password')), 'login-password')
      requireComponent(await driver.findComponent(ON.id('login-submit')), 'login-submit')

      // 快捷登录入口已移入弹窗：点击版本号文本3次触发
      //   第一步：确认版本号文本存在
      //   第二步：先滚动至真实可见，再连续点击并确认弹窗已出现。
      expect(await openQuickLoginDialog(driver)).assertTrue()
      //   第三步：弹窗内的四个快捷登录按钮现在应可见
      const quickIds: string[] = ['quick-login-user', 'quick-login-merchant', 'quick-login-admin', 'quick-login-rider']
      for (let i = 0; i < quickIds.length; i++) {
        const btn = await driver.findComponent(ON.id(quickIds[i]))
        console.info('[LoginFlow] ' + quickIds[i] + ' found=' + isFound(btn))
        expect(isFound(btn)).assertTrue()
      }
    })
  })
}
