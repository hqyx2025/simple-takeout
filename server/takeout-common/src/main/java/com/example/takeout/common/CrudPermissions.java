package com.example.takeout.common;

import com.example.takeout.model.User;

/** 账号级限制叠加于现有角色和数据归属规则；授权不能扩大角色的业务范围。 */
public record CrudPermissions(Boolean canCreate, Boolean canRead, Boolean canUpdate, Boolean canDelete) {
    public CrudPermissions {
        if (canCreate == null || canRead == null || canUpdate == null || canDelete == null) {
            throw new BizException(400, "请完整填写增、查、改、删四项权限");
        }
    }

    public static CrudPermissions from(User user) {
        return new CrudPermissions(user.canCreate(), user.canRead(), user.canUpdate(), user.canDelete());
    }

    public void require(CrudOperation operation) {
        boolean allowed = switch (operation) {
            case CREATE -> canCreate;
            case READ -> canRead;
            case UPDATE -> canUpdate;
            case DELETE -> canDelete;
        };
        if (!allowed) {
            String action = switch (operation) {
                case CREATE -> "新增";
                case READ -> "查询";
                case UPDATE -> "修改";
                case DELETE -> "删除";
            };
            throw new BizException(403, "当前账号没有" + action + "权限，请联系管理员");
        }
    }
}
