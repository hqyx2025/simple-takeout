import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'

export default function loginFlowTest() {
  describe('LoginFlow', () => {
    // 在真机执行前置条件：应用已启动并停留在登录表单。
    it('login form exposes stable controls', 0, async () => {
      const driver: Driver = Driver.create()
      const phone = await driver.findComponent(ON.id('login-phone'))
      const password = await driver.findComponent(ON.id('login-password'))
      const submit = await driver.findComponent(ON.id('login-submit'))
      expect(phone !== undefined).assertTrue()
      expect(password !== undefined).assertTrue()
      expect(submit !== undefined).assertTrue()
    })
  })
}
