#ifndef XGATEWAY_CRYPTO_H
#define XGATEWAY_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

void xgw_hmac_sha1(
    const uint8_t *key,
    size_t key_len,
    const uint8_t *message,
    size_t message_len,
    uint8_t output[20]
);

#endif
