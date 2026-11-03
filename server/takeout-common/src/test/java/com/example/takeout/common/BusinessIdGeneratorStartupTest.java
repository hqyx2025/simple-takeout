package com.example.takeout.common;

import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

class BusinessIdGeneratorStartupTest {
    @Test
    void startupRejectsMissingOrInvalidWorkerAndUsesExplicitWorker() throws Exception {
        for (String worker : new String[]{null, "1024", "0"}) {
            var command = new java.util.ArrayList<String>();
            command.add(Path.of(System.getProperty("java.home"), "bin", "java").toString());
            command.add("-Dfile.encoding=UTF-8");
            if (worker != null) command.add("-Dtakeout.snowflake.worker-id=" + worker);
            command.addAll(java.util.List.of("-cp", System.getProperty("surefire.test.class.path"), Probe.class.getName()));
            var builder = new ProcessBuilder(command).redirectErrorStream(true);
            builder.environment().remove("TAKEOUT_SNOWFLAKE_WORKER_ID");
            builder.environment().remove("JAVA_TOOL_OPTIONS");
            builder.environment().remove("JDK_JAVA_OPTIONS");
            var process = builder.start();
            try {
                assertTrue(process.waitFor(10, TimeUnit.SECONDS));
                String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
                if ("0".equals(worker)) {
                    assertEquals(0, process.exitValue(), output);
                    assertEquals("0", output.trim());
                } else {
                    assertNotEquals(0, process.exitValue(), output);
                    assertTrue(output.contains("TAKEOUT_SNOWFLAKE_WORKER_ID"), output);
                }
            } finally {
                process.destroyForcibly();
            }
        }
    }

    public static class Probe {
        public static void main(String[] args) {
            new BusinessIdGenerator();
            System.out.println(BusinessIdGenerator.workerId());
        }
    }
}
