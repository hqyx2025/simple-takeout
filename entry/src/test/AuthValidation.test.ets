import { describe, it, expect } from '@ohos/hypium'
import { initAppStorage, login, register } from '../main/ets/service/AppStorageManager'
import { User, UserRole } from '../main/ets/model/Models'
import { getMockUsers } from '../main/ets/service/MockDataService'

export default function authValidationTest() {
  describe('authValidation', () => {
    it('accepts valid credentials and preserves the user role', 0, () => {
      initAppStorage()
      const customer: User | undefined = login('13800138000', '123456')
      const merchant: User | undefined = login('13600136000', '123456')
      expect(customer !== undefined).assertTrue()
      expect(customer?.role).assertEqual(UserRole.CUSTOMER)
      expect(merchant !== undefined).assertTrue()
      expect(merchant?.role).assertEqual(UserRole.MERCHANT)
    })

    it('rejects invalid credentials', 0, () => {
      initAppStorage()
      expect(login('13800138000', 'wrong-password')).assertEqual(undefined)
      expect(login('19999999999', '123456')).assertEqual(undefined)
    })

    it('rejects duplicate phone registration', 0, () => {
      AppStorage.setOrCreate<User[]>('allUsers', getMockUsers())
      const first: User | undefined = register('测试用户', '15800000001', '123456', UserRole.CUSTOMER)
      const duplicate: User | undefined = register('重复用户', '15800000001', '123456', UserRole.MERCHANT)
      expect(first !== undefined).assertTrue()
      expect(first?.role).assertEqual(UserRole.CUSTOMER)
      expect(duplicate).assertEqual(undefined)
    })
  })
}
