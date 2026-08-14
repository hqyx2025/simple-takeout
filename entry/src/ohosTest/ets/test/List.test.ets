import abilityTest from './Ability.test';
import loginFlowTest from './LoginFlow.test';
import locationFlowTest from './LocationFlow.test';
import checkoutGuardTest from './CheckoutGuard.test';

export default function testsuite() {
  abilityTest();
  loginFlowTest();
  locationFlowTest();
  checkoutGuardTest();
}
