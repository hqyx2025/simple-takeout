package com.example.takeout.config;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DataSeederDisabledTest {

    @Test
    void skipsDemoDataAfterSchemaChecksWhenDisabled() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), eq(Integer.class))).thenReturn(1);
        when(jdbc.queryForObject(anyString(), eq(Integer.class), any(Object[].class))).thenReturn(1);
        DataSeeder seeder = new DataSeeder(jdbc);
        ReflectionTestUtils.setField(seeder, "seedEnabled", false);

        seeder.run(null);

        verify(jdbc, never()).queryForObject(eq("SELECT COUNT(*) FROM users"), eq(Integer.class));
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }
}
