import localUnitTest from './LocalUnit.test';
import orderCalculationsTest from './OrderCalculations.test';

export default function testsuite() {
  localUnitTest();
  orderCalculationsTest();
}
