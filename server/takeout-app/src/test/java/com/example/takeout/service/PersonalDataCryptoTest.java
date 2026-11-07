package com.example.takeout.service;

import com.example.takeout.common.BizException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import java.security.SecureRandom;
import java.util.Base64;
import static org.junit.jupiter.api.Assertions.*;

class PersonalDataCryptoTest {
    static String key() { byte[] value=new byte[32]; new SecureRandom().nextBytes(value); return Base64.getEncoder().encodeToString(value); }

    @Test void randomizedAuthenticatedCiphertextDoesNotContainTheOriginalPersonalData() {
        var crypto=new PersonalDataCrypto(key(),key(),"",new ObjectMapper());
        String value="13800138999 私人收货地址";
        String first=crypto.encrypt(value,"addresses.private"), second=crypto.encrypt(value,"addresses.private");
        assertNotEquals(first,second); assertFalse(first.contains("13800138999"));
        assertEquals(value,crypto.decrypt(first,"addresses.private"));
        assertThrows(BizException.class,()->crypto.decrypt(first,"users.phone"),"ciphertext must be bound to its field purpose");
        byte[] changed=Base64.getDecoder().decode(first.split(":",3)[2]); changed[changed.length-1]^=1;
        String tampered=first.substring(0,first.lastIndexOf(':')+1)+Base64.getEncoder().encodeToString(changed);
        assertThrows(BizException.class,()->crypto.decrypt(tampered,"addresses.private"));
    }

    @Test void previousKeysPermitRotationButAnUnknownKeyNeverBecomesPlaintext() {
        String old=key(), next=key(), index=key();
        var original=new PersonalDataCrypto(old,index,"",new ObjectMapper());
        String stored=original.encrypt("13800138999","users.phone");
        var rotated=new PersonalDataCrypto(next,index,old,new ObjectMapper());
        assertEquals("13800138999",rotated.decrypt(stored,"users.phone"));
        assertFalse(rotated.isCurrent(stored));
        assertThrows(BizException.class,()->new PersonalDataCrypto(next,index,"",new ObjectMapper()).readLegacy(stored,"users.phone"));
        assertThrows(BizException.class,()->rotated.readLegacy("pd2:unknown:data","users.phone"));
        assertEquals("legacy",rotated.readLegacy("legacy","orders.address"));
        assertEquals(original.hash("phone:exact","13800138999"),rotated.hash("phone:exact","13800138999"));
    }

    @Test void rejectsInvalidOrReusedKeysAndBoundsTheIndexedPhoneLength() {
        String key=key();
        assertThrows(IllegalStateException.class,()->new PersonalDataCrypto(key,key,"",new ObjectMapper()));
        assertThrows(IllegalStateException.class,()->new PersonalDataCrypto("",key,"",new ObjectMapper()));
        var crypto=new PersonalDataCrypto(key,key(),"",new ObjectMapper());
        assertThrows(BizException.class,()->crypto.phoneToken("1".repeat(21)));
        assertNotEquals(crypto.hash("phone:gram","138"),crypto.hash("phone:exact","138"));
        byte[] fixture=new byte[32];for(int i=0;i<fixture.length;i++)fixture[i]=(byte)i;
        var interoperable=new PersonalDataCrypto(key(),Base64.getEncoder().encodeToString(fixture),"",new ObjectMapper());
        assertEquals("PqDifDiOjWaXawMW9Vv90rOJgAQX0Oq_w7sG1aHv14s",interoperable.hash("phone:exact","demo500-01"),"must agree with the catalog tool's Python HMAC format");
    }

    @Test void configurationRejectsReusingExistingServiceKeysForPersonalData() {
        String jwt=key(), verification=key(), assistant=key(), wallet=key(), personal=key(), index=key();
        assertDoesNotThrow(()->new com.example.takeout.config.SecuritySecretsGuard(jwt,verification,assistant,wallet,personal,index));
        assertThrows(IllegalStateException.class,()->new com.example.takeout.config.SecuritySecretsGuard(jwt,verification,assistant,wallet,jwt,index));
        assertThrows(IllegalStateException.class,()->new com.example.takeout.config.SecuritySecretsGuard(jwt,verification,assistant,wallet,personal,personal));
    }
}
