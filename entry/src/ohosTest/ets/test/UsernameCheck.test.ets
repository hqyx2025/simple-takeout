import { describe, it, expect } from '@ohos/hypium'
import { Driver, ON, abilityDelegatorRegistry } from '@kit.TestKit'
import { UIAbility } from '@kit.AbilityKit'
import { launchAppUnderTest, requireComponent, clickByIdOrText, isFound } from './UiTestHelper'

// Uses the experience site's existing username; this scenario sends no mail and creates no account.
export default function usernameCheckTest() {
  describe('UsernameCheck', () => {
    it('UsernameCheck_duplicate_is_reported_before_other_registration_fields', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      expect(await clickByIdOrText(driver, 'login-mode-register', '还没有账号？去注册')).assertTrue()
      const username = requireComponent(await driver.waitForComponent(ON.id('login-username'), 5000), 'username')
      await username.inputText('小王')
      const error = requireComponent(await driver.waitForComponent(ON.id('login-username-error'), 10000), 'duplicate warning')
      expect(await error.getText()).assertContain('用户名已重复')
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      expect(await driver.screenCap(ability.context.filesDir + '/username-check-duplicate.png')).assertTrue()
      await username.clearText()
      await username.inputText('username_check_' + Date.now())
      await driver.delayMs(1800)
      expect(isFound(await driver.findComponent(ON.id('login-username-error')))).assertFalse()
      expect(await clickByIdOrText(driver, 'login-mode-login', '‹ 返回登录')).assertTrue()
    })
  })
}
