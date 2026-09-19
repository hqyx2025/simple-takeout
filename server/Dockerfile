# 简单外卖后端镜像（同时承载应用与网关两个可执行 jar）
#
# 多阶段构建：构建阶段用完整 JDK 编译，运行阶段只带 JRE，减小镜像体积。
#
# 注意：聚合根 server/pom.xml 与各模块都设了 maven.compiler.release=25，
# 构建阶段必须是 JDK 25，否则编译直接报 "invalid target release: 25"。
#
# 为什么一个镜像装两个 jar：网关与应用同源同版本、共用同一套 JDK 与基础镜像，
# 为网关单独维护一个 Dockerfile 只会增加漂移面。compose 里用不同的
# command/entrypoint 启动不同角色即可（见 docker-compose.yml 的 app 与 gateway 服务）。

# ---------- 构建阶段 ----------
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /workspace

# 先只拷 pom（聚合根 + 各模块）并预热依赖，源码变更时不必重新下载依赖（利用 Docker 层缓存）
COPY pom.xml .
COPY takeout-app/pom.xml takeout-app/pom.xml
COPY takeout-gateway/pom.xml takeout-gateway/pom.xml
RUN mvn -B -q -pl takeout-app,takeout-gateway -am dependency:go-offline || true

COPY takeout-app/src ./takeout-app/src
COPY takeout-gateway/src ./takeout-gateway/src
RUN mvn -B -q clean package -DskipTests

# 健康检查类在构建阶段编译（运行镜像是 JRE，没有 javac）
COPY takeout-app/docker/healthcheck.java /workspace/healthcheck.java
RUN javac -d /workspace /workspace/healthcheck.java

# ---------- 运行阶段 ----------
FROM eclipse-temurin:25-jre
WORKDIR /app

# 时区与编码：日志与数据库时间统一为东八区
ENV TZ=Asia/Shanghai \
    JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8 -Duser.timezone=Asia/Shanghai"

# 运行期需要写评价图片与日志，用非 root 用户并预建可写目录
RUN groupadd -r takeout && useradd -r -g takeout takeout \
    && mkdir -p /app/uploads /app/logs \
    && chown -R takeout:takeout /app

# 两个角色各自的 jar（默认入口是应用；网关由 compose 覆盖 ENTRYPOINT）
COPY --from=build /workspace/takeout-app/target/takeout-app-*.jar /app/takeout-app.jar
COPY --from=build /workspace/takeout-gateway/target/takeout-gateway-*.jar /app/takeout-gateway.jar

# 健康检查类（已在构建阶段编译好）：运行镜像无 curl/wget，用它探活
COPY --from=build /workspace/healthcheck.class /app/healthcheck.class
RUN chown takeout:takeout /app/takeout-app.jar /app/takeout-gateway.jar /app/healthcheck.class

USER takeout
EXPOSE 9000

# 容器内通过服务名访问 MySQL 与 Redis（见 docker-compose.yml）
# 默认启动应用；网关容器用 command 覆盖为启动网关
ENTRYPOINT ["java", "-jar", "/app/takeout-app.jar"]
CMD []