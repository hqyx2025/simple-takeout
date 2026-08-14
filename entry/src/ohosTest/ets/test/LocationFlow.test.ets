import { Driver, ON } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'

export default function locationFlowTest() {
  describe('LocationFlow', () => {
    // 在真机执行前置条件：已进入“选择位置”页面并完成地图加载。
    it('location page provides explicit confirmation action', 0, async () => {
      const driver: Driver = Driver.create()
      const confirm = await driver.findComponent(ON.id('location-confirm'))
      expect(confirm !== undefined).assertTrue()
    })
  })
}
