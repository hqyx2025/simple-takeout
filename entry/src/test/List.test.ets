import localUnitTest from './LocalUnit.test';
import orderCalculationsTest from './OrderCalculations.test';
import orderStatusTest from './OrderStatus.test';
import dataPersistenceTest from './DataPersistence.test';

export default function testsuite() {
  localUnitTest();
  orderCalculationsTest();
  orderStatusTest();
  dataPersistenceTest();
}
