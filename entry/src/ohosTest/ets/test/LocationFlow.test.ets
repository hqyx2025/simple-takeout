/**
 * 定位链路回归（设备端 UiTest）。
 *
 * 前置：guest 态（应用数据已清空）或已登录态都可以——用例会自己处理：
 *   1. 若出现隐私同意页则先同意；
 *   2. 若还在登录页则用「一键登录用户」进入首页；
 *   3. 首页点定位栏 → 断言定位页的确认按钮与搜索框都在。
 *
 * 历史教训：`location-confirm` 这条断言原来写成 `!== undefined`，而 findComponent 未命中返回
 * null → 恒真空跑；且 `aa test` 会把测试 Ability 的 Hello World 页盖在应用上，
 * 驱动根本看不到应用，所以「Pass」并不能说明定位页真的能用。
 */
import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, requireComponent, launchAppUnderTest, clickByIdOrText, waitAny } from './UiTestHelper'

export default function locationFlowTest() {
  describe('LocationFlow', () => {
    it('LocationFlow_quick_login_then_location_page', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)

      const consent = await waitAny(driver, ['privacy-accept'], 6000)
      if (isFound(consent)) {
        console.info('[LocationFlow] consent page shown -> accept privacy policy')
        await clickByIdOrText(driver, 'privacy-accept', '同意并继续')
        await driver.delayMs(3000)
      }

      // 登录页 → 一键登录用户（已登录则直接跳过）
      const quickUser = await driver.findComponent(ON.id('quick-login-user'))
      if (isFound(quickUser)) {
        console.info('[LocationFlow] guest state -> quick login as user')
        expect(await clickByIdOrText(driver, 'quick-login-user', '一键登录用户')).assertTrue()
        await driver.delayMs(6000)
      } else {
        console.info('[LocationFlow] already logged in')
      }

      // 首页定位栏 → 定位页
      expect(await clickByIdOrText(driver, 'home-location-entry', '未定位，点击定位')).assertTrue()
      await driver.delayMs(5000)

      requireComponent(await driver.waitForComponent(ON.id('location-confirm'), 20000), 'location-confirm')
      const searchBox = await driver.findComponent(ON.id('location-search'))
      console.info('[LocationFlow] location-search found=' + isFound(searchBox))
      expect(isFound(searchBox)).assertTrue()
    })
  })
}
