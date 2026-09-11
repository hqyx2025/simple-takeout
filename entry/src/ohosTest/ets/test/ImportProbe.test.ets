/**
 * 跨源集能力探针：确认设备端用例能否直接调用应用自身代码（entry/src/main 下的服务/常量）。
 *
 * 若能调用，设备端用例就不只能"点界面"，还能直接驱动被测代码（例如用真实文件调用上传函数），
 * 这对图库为空、无法通过系统选图器取图的模拟器尤其关键。
 *
 * 同时也探一下 AbilityDelegator.getAppContext() 拿到的沙箱目录（用于生成测试图片文件）。
 */
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, it, expect } from '@ohos/hypium'
import { getOrderStatusText } from '../../../main/ets/common/Constants'

export default function importProbeTest() {
  describe('ImportProbe', () => {
    it('ImportProbe_can_call_app_module_code', 0, async () => {
      const statusText: string = getOrderStatusText(0, 0)
      console.info('[ImportProbe] getOrderStatusText(0)=' + statusText)
      expect(statusText).assertEqual('待付款')

      const other: string = getOrderStatusText(4, 0)
      console.info('[ImportProbe] getOrderStatusText(4,0)=' + other)
      expect(other).assertEqual('已送达，待确认收货')

      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const appContext = delegator.getAppContext()
      const filesDir: string = appContext.filesDir
      console.info('[ImportProbe] filesDir=' + filesDir)
      expect(filesDir.length > 0).assertTrue()
    })
  })
}
