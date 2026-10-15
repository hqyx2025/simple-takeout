import { abilityDelegatorRegistry, Driver } from '@kit.TestKit'
import { common } from '@kit.AbilityKit'
import preferences from '@ohos.data.preferences'
import { describe, it, expect } from '@ohos/hypium'
import { clearAuthTokens, loadAuthTokens, saveAuthTokens, StoredAuthTokens } from '../../../main/ets/service/TokenStorage'
import { launchAppUnderTest } from './UiTestHelper'

export default function authTokenStorageTest(): void {
  describe('AuthTokenStorage', () => {
    it('encrypts_roundtrips_and_rejects_modified_ciphertext', 0, async () => {
      await launchAppUnderTest(Driver.create())
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const context: common.UIAbilityContext = ability.context
      AppStorage.setOrCreate<common.UIAbilityContext>('appContext', context)
      const previous: StoredAuthTokens | null = await loadAuthTokens()
      console.info('[AuthTokenStorage] Existing credential loaded; beginning save')
      const prefs: preferences.Preferences = await preferences.getPreferences(context, 'takeout_auth_tokens')
      try {
        await saveAuthTokens('sample-access-token', 'sample-refresh-token')
        console.info('[AuthTokenStorage] Encrypted token pair saved; beginning roundtrip')
        const loaded: StoredAuthTokens | null = await loadAuthTokens()
        expect(loaded !== null).assertTrue()
        expect(loaded!.accessToken).assertEqual('sample-access-token')
        expect(loaded!.refreshToken).assertEqual('sample-refresh-token')
        const ciphertext: string = await prefs.get('encrypted_tokens_v1', '') as string
        expect(ciphertext.includes('sample')).assertFalse()
        const changed: string = ciphertext.substring(0, ciphertext.length - 1)
          + (ciphertext.endsWith('0') ? '1' : '0')
        await prefs.put('encrypted_tokens_v1', changed)
        await prefs.flush()
        expect(await loadAuthTokens()).assertNull()
      } finally {
        if (previous !== null) {
          await saveAuthTokens(previous.accessToken, previous.refreshToken)
        } else {
          await clearAuthTokens()
        }
      }
    })
  })
}
