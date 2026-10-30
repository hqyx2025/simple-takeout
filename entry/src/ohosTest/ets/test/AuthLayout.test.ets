import { describe, it, expect } from '@ohos/hypium'
import { Driver, ON, Component, abilityDelegatorRegistry } from '@kit.TestKit'
import { window } from '@kit.ArkUI'
import { UIAbility } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { launchAppUnderTest, requireComponent, clickByIdOrText, scrollUntilVisible, isFound } from './UiTestHelper'
import { saveAppearanceSettings } from '../../../main/ets/service/AppearanceSettings'

async function verifyForm(driver: Driver, ids: string[], submitId: string, full: boolean): Promise<void> {
  await driver.delayMs(500)
  const size = await driver.getDisplaySize()
  const submit: Component = requireComponent(await driver.findComponent(ON.id(submitId)), submitId)
  const footer = await submit.getBounds()
  const scroll = requireComponent(await driver.findComponent(ON.type('Scroll')), 'form scroll')
  const viewport = await scroll.getBounds()
  expect(footer.top > 0 && footer.bottom <= size.y).assertTrue()
  for (const id of ids) {
    let found = await driver.findComponent(ON.id(id))
    for (let attempt = 0; attempt < 8; attempt++) {
      if (found !== null && found !== undefined) {
        const bounds = await found.getBounds()
        if (bounds.bottom - bounds.top > 70) { break }
      }
      // Swipe inside this page's actual scroll area, above the fixed footer.
      await driver.swipe(Math.floor(size.x / 2), viewport.bottom - 60,
        Math.floor(size.x / 2), Math.max(viewport.top + 60, viewport.bottom - 500), 500)
      await driver.delayMs(400)
      found = await driver.findComponent(ON.id(id))
    }
    const field: Component = requireComponent(found, id)
    const rect = await field.getBounds()
    expect(rect.top >= 0 && rect.bottom <= footer.top && rect.right <= size.x).assertTrue()
    expect(rect.bottom - rect.top > 70).assertTrue()
  }
}

export default function authLayoutTest() {
  describe('AuthLayout', () => {
    it('AuthLayout_compact_forms_light_dark_and_large_text', 0, async () => {
      const driver: Driver = Driver.create()
      await launchAppUnderTest(driver)
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const ui = (await window.getLastWindow(ability.context)).getUIContext()
      const previousMode: string = AppStorage.get<string>('appearanceColorMode') ?? 'system'
      const previousScale: number = AppStorage.get<number>('appearanceFontScale') ?? 1
      const previousHand: string = AppStorage.get<string>('navigationHandMode') ?? 'auto'
      const directory: string = ability.context.filesDir + '/native-auth-layout'
      try { fileIo.mkdirSync(directory) } catch (_) {}
      try {
        for (const variant of ['light', 'dark', 'large']) {
          const full: boolean = variant !== 'large'
          await saveAppearanceSettings(ability.context, variant === 'dark' ? 'dark' : 'light', full ? 1 : 1.3, previousHand)
          await driver.delayMs(500)
          expect(await clickByIdOrText(driver, 'login-mode-login', '登录')).assertTrue()
          expect(await clickByIdOrText(driver, 'login-method-password', '密码登录')).assertTrue()
          await verifyForm(driver, ['login-phone', 'login-password'], 'login-submit', full)
          expect(await driver.screenCap(directory + '/' + variant + '-password.png')).assertTrue()
          expect(await clickByIdOrText(driver, 'login-method-email', '验证码登录')).assertTrue()
          await verifyForm(driver, ['login-phone', 'login-email', 'email-captcha-input', 'login-email-code'], 'login-submit', full)
          expect(await driver.screenCap(directory + '/' + variant + '-email.png')).assertTrue()
          expect(await clickByIdOrText(driver, 'login-mode-register', '注册')).assertTrue()
          let routeName: string = ''
          ui.runScopedTask((): void => { routeName = ui.getRouter().getState().name ?? '' })
          expect(routeName.includes('RegisterPage')).assertTrue()
          await verifyForm(driver, ['login-username', 'login-email', 'login-phone', 'email-captcha-input', 'register-email-code',
            'login-password', 'login-confirm-password'], 'register-submit', full)
          expect(isFound(await driver.findComponent(ON.text('注册账号')))).assertFalse()
          expect(await driver.screenCap(directory + '/' + variant + '-register.png')).assertTrue()
          const topMode = requireComponent(await scrollUntilVisible(driver, 'login-mode-login'), 'login mode')
          await topMode.click()
          expect(await clickByIdOrText(driver, 'login-method-password', '密码登录')).assertTrue()
          expect(await clickByIdOrText(driver, 'login-forgot-password', '忘记登录密码？')).assertTrue()
          await verifyForm(driver, ['password-reset-phone', 'password-reset-email', 'email-captcha-input',
            'password-reset-code', 'password-reset-new', 'password-reset-confirm'], 'password-reset-submit', full)
          expect(await driver.screenCap(directory + '/' + variant + '-recovery.png')).assertTrue()
          expect(await clickByIdOrText(driver, 'password-reset-back', '‹ 返回')).assertTrue()
          console.info('[AuthLayout] PASS ' + variant + ' password/email/register/recovery')
        }
      } finally {
        ui.runScopedTask((): void => {
          if ((ui.getRouter().getState().name ?? '').includes('PasswordResetPage')) { ui.getRouter().back() }
        })
        await saveAppearanceSettings(ability.context, previousMode, previousScale, previousHand)
      }
    })
  })
}
