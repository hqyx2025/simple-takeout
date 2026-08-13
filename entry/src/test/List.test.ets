import localUnitTest from './LocalUnit.test';
import orderCalculationsTest from './OrderCalculations.test';
import orderStatusTest from './OrderStatus.test';

export default function testsuite() {
  localUnitTest();
  orderCalculationsTest();
  orderStatusTest();
}
