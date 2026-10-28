import { describe, it, expect } from '@ohos/hypium'
import { OrderActionSource } from '../main/ets/model/Models'
import { canOrderAction } from '../main/ets/service/OrderStatus'

export default function orderStatusTest() {
  describe('orderActions', () => {
    it('only missing server capabilities allow legacy behavior', 0, () => {
      const legacy: OrderActionSource = {}
      const denied: OrderActionSource = { capabilities: { allowedActions: [], refundRemaining: 0,
        afterSalesDeadline: '', fulfillmentMode: 'RIDER' } }
      expect(canOrderAction(legacy, 'PAY', true)).assertTrue()
      expect(canOrderAction(denied, 'PAY', true)).assertFalse()
    })

    it('merchant acceptance and rejection are independent server actions', 0, () => {
      const order: OrderActionSource = { capabilities: { allowedActions: ['MERCHANT_REJECT'], refundRemaining: 0,
        afterSalesDeadline: '', fulfillmentMode: 'RIDER' } }
      expect(canOrderAction(order, 'MERCHANT_REJECT', false)).assertTrue()
      expect(canOrderAction(order, 'MERCHANT_ACCEPT', true)).assertFalse()
      expect(canOrderAction(order, 'MERCHANT_COMPLETE', true)).assertFalse()
    })
  })
}
