import { describe, it, expect } from '@ohos/hypium'
import { getCategories, getStores, getGoodsByStore, getDefaultOrders, getDefaultCoupons, getMockUsers } from '../main/ets/service/MockDataService'
import { StoreItem, GoodsItem, Order, Coupon, User } from '../main/ets/model/Models'

function hasUniqueIds(ids: number[]): boolean {
  for (let i = 0; i < ids.length; i++) {
    for (let j = i + 1; j < ids.length; j++) {
      if (ids[i] === ids[j]) {
        return false
      }
    }
  }
  return true
}

function hasText(value: string): boolean {
  return typeof value === 'string' && value.trim().length > 0
}

export default function mockDataIntegrityTest() {
  describe('mockDataIntegrity', () => {
    it('provides complete categories and stores with unique ids', 0, () => {
      const categories = getCategories()
      const stores: StoreItem[] = getStores()
      const categoryIds: number[] = categories.map(item => item.id)
      const storeIds: number[] = stores.map(item => item.id)
      expect(categories.length).assertEqual(8)
      expect(stores.length).assertEqual(30)
      expect(hasUniqueIds(categoryIds)).assertTrue()
      expect(hasUniqueIds(storeIds)).assertTrue()
      for (let i = 0; i < stores.length; i++) {
        expect(hasText(stores[i].name)).assertTrue()
        expect(stores[i].deliveryFee >= 0).assertTrue()
        expect(stores[i].minOrder >= 0).assertTrue()
        expect(stores[i].tags.length > 0).assertTrue()
      }
    })

    it('provides 30 goods for every store with complete fields', 0, () => {
      const stores: StoreItem[] = getStores()
      for (let i = 0; i < stores.length; i++) {
        const goods: GoodsItem[] = getGoodsByStore(stores[i].id)
        const goodsIds: number[] = goods.map(item => item.id)
        expect(goods.length).assertEqual(30)
        expect(hasUniqueIds(goodsIds)).assertTrue()
        for (let j = 0; j < goods.length; j++) {
          expect(hasText(goods[j].name)).assertTrue()
          expect(hasText(goods[j].description)).assertTrue()
          expect(goods[j].price > 0).assertTrue()
          expect(goods[j].rating >= 0 && goods[j].rating <= 5).assertTrue()
        }
      }
    })

    it('provides complete orders and coupons with unique ids', 0, () => {
      const orders: Order[] = getDefaultOrders()
      const coupons: Coupon[] = getDefaultCoupons()
      const orderIds: number[] = orders.map(item => item.id)
      const couponIds: number[] = coupons.map(item => item.id)
      expect(orders.length).assertEqual(30)
      expect(coupons.length).assertEqual(30)
      expect(hasUniqueIds(orderIds)).assertTrue()
      expect(hasUniqueIds(couponIds)).assertTrue()
      for (let i = 0; i < orders.length; i++) {
        expect(orders[i].items.length > 0).assertTrue()
        expect(orders[i].payAmount >= 0).assertTrue()
        expect(orders[i].address !== null).assertTrue()
      }
      for (let i = 0; i < coupons.length; i++) {
        expect(coupons[i].amount > 0).assertTrue()
        expect(coupons[i].minOrder >= 0).assertTrue()
        expect(hasText(coupons[i].condition)).assertTrue()
      }
    })

    it('provides five login fixtures with unique accounts', 0, () => {
      const users: User[] = getMockUsers()
      const userIds: number[] = users.map(item => item.id)
      const phones: string[] = users.map(item => item.phone)
      expect(users.length).assertEqual(5)
      expect(hasUniqueIds(userIds)).assertTrue()
      for (let i = 0; i < users.length; i++) {
        expect(hasText(users[i].username)).assertTrue()
        expect(hasText(users[i].phone)).assertTrue()
        expect(hasText(users[i].password)).assertTrue()
        expect(phones[i].length).assertEqual(11)
      }
      for (let i = 0; i < phones.length; i++) {
        for (let j = i + 1; j < phones.length; j++) {
          expect(phones[i] === phones[j]).assertFalse()
        }
      }
    })
  })
}
