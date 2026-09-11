/**
 * 驱动能力自检（设备端 UiTest）。
 *
 * 它守的是一条很容易再次踩中的坑：`aa test` 会把 ohosTest 模板生成的 TestAbility
 * （`testability/pages/Index`，页面只有 "Hello World"）拉到前台，盖住被测应用。
 * 如果不先 `AbilityDelegator.startAbility(EntryAbility)`，驱动只能看到测试 Ability 的窗口，
 * 任何 `findComponent` 都会返回 null —— 此时若断言写成 `!== undefined` 就会「全绿空跑」。
 *
 * 所以这条用例断言的是：启动被测应用后，首页 Tab 必须能被驱动看到。
 */
import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { isFound, launchAppUnderTest } from './UiTestHelper'

export default function probeTest() {
  describe('Probe', () => {
    it('Probe_app_is_visible_to_driver', 0, async () => {
      const driver: Driver = Driver.create()
      const size = await driver.getDisplaySize()
      console.info('[Probe] displaySize=' + size.x + 'x' + size.y)

      await launchAppUnderTest(driver)

      const mineTab = await driver.waitForComponent(ON.id('tab-3'), 20000)
      console.info('[Probe] tab-3 visible after launchAppUnderTest=' + isFound(mineTab))
      expect(isFound(mineTab)).assertTrue()
    })
  })
}
