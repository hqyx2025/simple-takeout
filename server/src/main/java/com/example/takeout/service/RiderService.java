package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.example.takeout.dao.RiderDao;
import com.example.takeout.dao.UserDao;
import com.example.takeout.model.Rider;
import com.example.takeout.model.User;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * 骑手端服务（四端改造）：骑手资料、上线/下线。
 */
@Service
public class RiderService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final RiderDao riderDao;
    private final UserDao userDao;

    public RiderService(RiderDao riderDao, UserDao userDao) {
        this.riderDao = riderDao;
        this.userDao = userDao;
    }

    /**
     * 骑手资料。账号角色必须为 RIDER(3)；档案不存在时自动建档，
     * 兼容“平台开通账号后首次进入骑手端”的场景。
     */
    @Transactional
    public Rider profile(long userId) {
        User user = userDao.findById(userId).orElseThrow(() -> new BizException("用户不存在"));
        if (user.role() != 3) {
            throw new BizException(403, "仅骑手可以访问骑手端");
        }
        Rider existing = riderDao.findByUserId(userId).orElse(null);
        if (existing != null) {
            return existing;
        }
        long id = riderDao.insert(userId, user.username(), user.phone(), LocalDateTime.now().format(FMT));
        return riderDao.findById(id).orElseThrow(() -> new BizException("骑手档案创建失败"));
    }

    /** 上线 / 下线（仅在线可抢单）。 */
    public Rider setOnline(long userId, int online) {
        Rider rider = profile(userId);
        riderDao.updateOnline(rider.id(), online == 1 ? 1 : 0);
        return riderDao.findById(rider.id()).orElseThrow(() -> new BizException("骑手不存在"));
    }

    /** 送达完成后累加骑手单量与配送收入（简化口径：按订单配送费计）。 */
    public Rider recordDelivered(long riderId, double income) {
        riderDao.addCompleted(riderId, income);
        return riderDao.findById(riderId).orElseThrow(() -> new BizException("骑手不存在"));
    }

    /** 管理端：骑手列表。 */
    public List<Rider> listAll() {
        return riderDao.listAll();
    }

    /** 管理端：启用 / 停用骑手。 */
    public Rider updateStatus(long riderId, int status) {
        riderDao.updateStatus(riderId, status == 0 ? 0 : 1);
        return riderDao.findById(riderId).orElseThrow(() -> new BizException("骑手不存在"));
    }
}
