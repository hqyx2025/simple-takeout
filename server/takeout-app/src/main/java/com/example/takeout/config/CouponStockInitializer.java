package com.example.takeout.config;

import com.example.takeout.dao.CouponStockDao;
import com.example.takeout.service.UserCenterService;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** 完成结构升级后初始化限量名额；库存由数据库持久化，重启不补回已领取的名额。 */
@Component
@Order(200)
public class CouponStockInitializer implements ApplicationRunner {
    private final CouponStockDao stock;
    private final UserCenterService center;

    public CouponStockInitializer(CouponStockDao stock, UserCenterService center) {
        this.stock = stock;
        this.center = center;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        for (var campaign : center.listCouponActivities()) {
            stock.initialize(campaign.name(), campaign.threshold(), campaign.amount());
        }
    }
}
