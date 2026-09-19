/**
 * 容器健康检查：仅用 JDK 自带能力探测后端端口是否可连接。
 *
 * 运行镜像基于 JRE，没有 curl/wget，因此用这段最小 Java 程序替代。
 * 只判断 TCP 能否建立连接（HTTP 层返回 400/401/200 都算服务已就绪）。
 *
 * 用法：java -cp /app healthcheck 127.0.0.1 9000
 * 退出码：0 = 服务可达；1 = 不可达
 */
import java.net.InetSocketAddress;
import java.net.Socket;

public final class healthcheck {

    public static void main(String[] args) {
        String host = args.length > 0 ? args[0] : "127.0.0.1";
        int port = args.length > 1 ? Integer.parseInt(args[1]) : 9000;

        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), 3000);
            System.exit(0);
        } catch (Exception e) {
            System.err.println("healthcheck failed: " + host + ":" + port + " - " + e.getMessage());
            System.exit(1);
        }
    }
}
