import { describe, it, expect } from '@ohos/hypium'
import { calculateGoodsTotal, calculatePayAmount } from '../main/ets/service/OrderCalculations'

export default function orderCalculationsTest() {
  describe('orderCalculations', () => {
    it('calculates goods total from prices and quantities', 0, () => {
      expect(calculateGoodsTotal([12.5, 8], [2, 3])).assertEqual(49)
    })

    it('calculates payable amount with delivery and coupon discount', 0, () => {
      expect(calculatePayAmount(49, 5, 10)).assertEqual(44)
    })

    it('does not return a negative payable amount', 0, () => {
      expect(calculatePayAmount(10, 2, 50)).assertEqual(0)
    })

    it('ignores invalid negative calculation inputs', 0, () => {
      expect(calculatePayAmount(-10, 5, -2)).assertEqual(5)
    })
  })
}
