package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.StoreDao;
import com.example.takeout.dao.GoodsDao;
import com.example.takeout.model.Store;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

/** Unit fixtures only; database transaction/locking guarantees are exercised by the MySQL tests. */
final class OrderTestFixture {
    static TransactionTemplate transactions() {
        var manager = mock(PlatformTransactionManager.class);
        when(manager.getTransaction(any())).thenAnswer(call -> new SimpleTransactionStatus());
        return new TransactionTemplate(manager);
    }
    static void admission(StoreDao stores) {
        when(stores.lockForOrderAdmission(anyLong(), anyBoolean())).thenAnswer(call -> {
            Store store = stores.findById(call.getArgument(0)).orElseThrow(() -> new BizException("店铺不存在"));
            if (!store.available() || (Boolean.TRUE.equals(call.getArgument(1)) && store.status() != 1))
                throw new BizException("店铺当前未营业");
            return store;
        });
    }
    static void goods(GoodsDao goods) {
        when(goods.findForOrder(anyLong())).thenAnswer(call -> goods.findById(call.getArgument(0)));
    }
}
