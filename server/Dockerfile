# 简单外卖后端服务镜像
# 多阶段构建：构建阶段用完整 JDK 编译，运行阶段只带 JRE，减小镜像体积。
#
# 注意：server/pom.xml 设置了 maven.compiler.release=25，构建阶段必须是 JDK 25，
# 否则编译直接报 "invalid target release: 25"。

# ---------- 构建阶段 ----------
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /workspace

# 先只拷 pom 并预热依赖，源码变更时不必重新下载依赖（利用 Docker 层缓存）
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q clean package -DskipTests

# 健康检查类在构建阶段编译（运行镜像是 JRE，没有 javac）
COPY docker/healthcheck.java /workspace/docker/healthcheck.java
RUN javac -d /workspace/docker /workspace/docker/healthcheck.java

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

COPY --from=build /workspace/target/*.jar app.jar

# 健康检查类（已在构建阶段编译好）：运行镜像无 curl/wget，用它探活
COPY --from=build /workspace/docker/healthcheck.class /app/healthcheck.class
RUN chown takeout:takeout /app/app.jar /app/healthcheck.class

USER takeout
EXPOSE 9000

# 容器内通过服务名访问 MySQL 与 Redis（见 docker-compose.yml）
ENTRYPOINT ["java", "-jar", "app.jar"]
