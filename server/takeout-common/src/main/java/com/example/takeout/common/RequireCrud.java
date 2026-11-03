package com.example.takeout.common;

import java.lang.annotation.*;

@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.METHOD, ElementType.TYPE})
public @interface RequireCrud {
    /** 空数组仅用于在业务层按实际动作检查权限的接口。 */
    CrudOperation[] value();
}
