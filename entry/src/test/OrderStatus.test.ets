import { describe, it, expect } from '@ohos/hypium'
import { canTransitionOrderStatus, getOrderStatusSequence } from '../main/ets/service/OrderStatus'

export default function orderStatusTest() {
  describe('orderStatus', () => {
    it('allows the normal lifecycle', 0, () => {
      const sequence: number[] = getOrderStatusSequence()
      for (let i = 0; i < sequence.length - 1; i++) {
        expect(canTransitionOrderStatus(sequence[i], sequence[i + 1])).assertTrue()
      }
    })

    it('allows cancellation before completion', 0, () => {
      expect(canTransitionOrderStatus(0, 5)).assertTrue()
      expect(canTransitionOrderStatus(1, 5)).assertTrue()
      expect(canTransitionOrderStatus(2, 5)).assertTrue()
    })

    it('allows refund from unpaid state', 0, () => {
      expect(canTransitionOrderStatus(0, 6)).assertTrue()
    })

    it('rejects transitions from terminal states', 0, () => {
      expect(canTransitionOrderStatus(4, 1)).assertFalse()
      expect(canTransitionOrderStatus(5, 4)).assertFalse()
      expect(canTransitionOrderStatus(6, 1)).assertFalse()
    })
  })
}
