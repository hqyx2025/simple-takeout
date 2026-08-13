import localUnitTest from './LocalUnit.test';
import orderCalculationsTest from './OrderCalculations.test';
import orderStatusTest from './OrderStatus.test';
import dataPersistenceTest from './DataPersistence.test';
import mockDataIntegrityTest from './MockDataIntegrity.test';
import authValidationTest from './AuthValidation.test';

export default function testsuite() {
  localUnitTest();
  orderCalculationsTest();
  orderStatusTest();
  dataPersistenceTest();
  mockDataIntegrityTest();
  authValidationTest();
}
