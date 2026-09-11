import abilityTest from './Ability.test';
import loginFlowTest from './LoginFlow.test';
import locationFlowTest from './LocationFlow.test';
import checkoutGuardTest from './CheckoutGuard.test';
import checkoutFlowTest from './CheckoutFlow.test';
import searchFlowTest from './SearchFlow.test';
import probeTest from './Probe.test';

export default function testsuite() {
  abilityTest();
  loginFlowTest();
  locationFlowTest();
  checkoutGuardTest();
  checkoutFlowTest();
  searchFlowTest();
  probeTest();
}
