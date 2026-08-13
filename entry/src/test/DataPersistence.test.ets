import { describe, it, expect } from '@ohos/hypium'
import { normalizeData } from '../main/ets/service/DataPersistence'
import { User, Order, CartItem, Address, Coupon, Favorite } from '../main/ets/model/Models'

export default function dataPersistenceTest() {
  describe('dataPersistence', () => {
    it('normalizes malformed user collections and scalar fields', 0, () => {
      const raw: Object = JSON.parse('{"id":"bad","username":12,"coupons":null,"orders":null,"storeIds":null,"balance":"bad"}') as Object
      const result: User = normalizeData('user', raw) as User
      expect(Array.isArray(result.coupons)).assertTrue()
      expect(Array.isArray(result.orders)).assertTrue()
      expect(Array.isArray(result.storeIds)).assertTrue()
      expect(result.balance).assertEqual(0)
      expect(result.id).assertEqual(0)
    })

    it('drops malformed orders and supplies safe nested fields', 0, () => {
      const raw: Object = JSON.parse('[{"id":"bad"},{"id":100,"items":null,"status":"bad","address":null}]') as Object
      const result: Order[] = normalizeData('orderList', raw) as Order[]
      expect(result.length).assertEqual(1)
      expect(Array.isArray(result[0].items)).assertTrue()
      expect(result[0].status).assertEqual(1)
      expect(result[0].address !== null).assertTrue()
    })

    it('falls back to safe arrays for damaged persisted values', 0, () => {
      const empty: Object = JSON.parse('null') as Object
      const cart: CartItem[] = normalizeData('cartItems', empty) as CartItem[]
      const addresses: Address[] = normalizeData('addressList', empty) as Address[]
      const coupons: Coupon[] = normalizeData('couponList', empty) as Coupon[]
      const favorites: Favorite[] = normalizeData('favoriteList', empty) as Favorite[]
      expect(cart.length).assertEqual(0)
      expect(addresses.length > 0).assertTrue()
      expect(coupons.length > 0).assertTrue()
      expect(favorites.length >= 0).assertTrue()
    })
  })
}
