import { describe, it, expect } from '@ohos/hypium'
import { NavigationThrottle } from '../main/ets/common/NavigationThrottle'

export default function navigationThrottleTest() {
  describe('navigationThrottle', () => {
    it('drops the second push of the same page within the window', 0, () => {
      const throttle: NavigationThrottle = new NavigationThrottle()
      expect(throttle.allowPush('pages/LocationPage', 1000)).assertTrue()
      // 连点：同页面 200ms 内第二次进入必须被丢弃，否则路由栈会叠两层
      expect(throttle.allowPush('pages/LocationPage', 1200)).assertFalse()
      expect(throttle.allowPush('pages/LocationPage', 1810)).assertTrue()
    })

    it('keeps different pages independent', 0, () => {
      const throttle: NavigationThrottle = new NavigationThrottle(800, 500)
      expect(throttle.allowPush('pages/LocationPage', 1000)).assertTrue()
      expect(throttle.allowPush('pages/StoreDetailPage', 1001)).assertTrue()
      expect(throttle.allowPush('pages/LocationPage', 1002)).assertTrue()
    })

    it('allows the same page again after going back', 0, () => {
      const throttle: NavigationThrottle = new NavigationThrottle()
      expect(throttle.allowPush('pages/LocationPage', 1000)).assertTrue()
      expect(throttle.allowBack(1100)).assertTrue()
      throttle.reset()
      expect(throttle.allowPush('pages/LocationPage', 1200)).assertTrue()
    })

    it('drops repeated back taps that would pop two pages', 0, () => {
      const throttle: NavigationThrottle = new NavigationThrottle()
      expect(throttle.allowBack(1000)).assertTrue()
      expect(throttle.allowBack(1200)).assertFalse()
      expect(throttle.allowBack(1400)).assertTrue()
    })
  })
}