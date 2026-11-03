package com.example.takeout.model;

/** 入驻申请及审核的追加记录，0=提交、1=通过、2=驳回。 */
public record StoreReview(long id, long storeId, int status, long operatorId, String reason, String createTime) {
}
