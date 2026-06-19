#include "XGatewayCrypto.h"

#include <string.h>

typedef struct {
    uint32_t state[5];
    uint64_t bit_count;
    uint8_t buffer[64];
} xgw_sha1_ctx;

static uint32_t xgw_rotate_left(uint32_t value, uint32_t bits) {
    return (value << bits) | (value >> (32U - bits));
}

static void xgw_sha1_transform(uint32_t state[5], const uint8_t block[64]) {
    uint32_t w[80];
    for (size_t i = 0; i < 16; i++) {
        size_t offset = i * 4;
        w[i] = ((uint32_t)block[offset] << 24)
             | ((uint32_t)block[offset + 1] << 16)
             | ((uint32_t)block[offset + 2] << 8)
             | ((uint32_t)block[offset + 3]);
    }
    for (size_t i = 16; i < 80; i++) {
        w[i] = xgw_rotate_left(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    uint32_t a = state[0];
    uint32_t b = state[1];
    uint32_t c = state[2];
    uint32_t d = state[3];
    uint32_t e = state[4];

    for (size_t i = 0; i < 80; i++) {
        uint32_t f;
        uint32_t k;
        if (i < 20) {
            f = (b & c) | ((~b) & d);
            k = 0x5a827999U;
        } else if (i < 40) {
            f = b ^ c ^ d;
            k = 0x6ed9eba1U;
        } else if (i < 60) {
            f = (b & c) | (b & d) | (c & d);
            k = 0x8f1bbcdcU;
        } else {
            f = b ^ c ^ d;
            k = 0xca62c1d6U;
        }

        uint32_t temp = xgw_rotate_left(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = xgw_rotate_left(b, 30);
        b = a;
        a = temp;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
}

static void xgw_sha1_init(xgw_sha1_ctx *ctx) {
    ctx->state[0] = 0x67452301U;
    ctx->state[1] = 0xefcdab89U;
    ctx->state[2] = 0x98badcfeU;
    ctx->state[3] = 0x10325476U;
    ctx->state[4] = 0xc3d2e1f0U;
    ctx->bit_count = 0;
    memset(ctx->buffer, 0, sizeof(ctx->buffer));
}

static void xgw_sha1_update(xgw_sha1_ctx *ctx, const uint8_t *data, size_t len) {
    size_t buffer_index = (size_t)((ctx->bit_count / 8U) % 64U);
    ctx->bit_count += (uint64_t)len * 8U;

    size_t i = 0;
    if (buffer_index > 0) {
        size_t fill = 64U - buffer_index;
        if (len < fill) {
            memcpy(ctx->buffer + buffer_index, data, len);
            return;
        }
        memcpy(ctx->buffer + buffer_index, data, fill);
        xgw_sha1_transform(ctx->state, ctx->buffer);
        i += fill;
    }

    for (; i + 63U < len; i += 64U) {
        xgw_sha1_transform(ctx->state, data + i);
    }

    if (i < len) {
        memcpy(ctx->buffer, data + i, len - i);
    }
}

static void xgw_sha1_final(xgw_sha1_ctx *ctx, uint8_t digest[20]) {
    uint8_t padding[64];
    memset(padding, 0, sizeof(padding));
    padding[0] = 0x80U;

    uint8_t length[8];
    for (size_t i = 0; i < 8; i++) {
        length[7U - i] = (uint8_t)((ctx->bit_count >> (i * 8U)) & 0xffU);
    }

    size_t buffer_index = (size_t)((ctx->bit_count / 8U) % 64U);
    size_t pad_len = buffer_index < 56U ? (56U - buffer_index) : (120U - buffer_index);
    xgw_sha1_update(ctx, padding, pad_len);
    xgw_sha1_update(ctx, length, sizeof(length));

    for (size_t i = 0; i < 5; i++) {
        digest[i * 4] = (uint8_t)((ctx->state[i] >> 24) & 0xffU);
        digest[i * 4 + 1] = (uint8_t)((ctx->state[i] >> 16) & 0xffU);
        digest[i * 4 + 2] = (uint8_t)((ctx->state[i] >> 8) & 0xffU);
        digest[i * 4 + 3] = (uint8_t)(ctx->state[i] & 0xffU);
    }
}

static void xgw_sha1(const uint8_t *data, size_t len, uint8_t digest[20]) {
    xgw_sha1_ctx ctx;
    xgw_sha1_init(&ctx);
    xgw_sha1_update(&ctx, data, len);
    xgw_sha1_final(&ctx, digest);
}

void xgw_hmac_sha1(
    const uint8_t *key,
    size_t key_len,
    const uint8_t *message,
    size_t message_len,
    uint8_t output[20]
) {
    uint8_t key_block[64];
    memset(key_block, 0, sizeof(key_block));

    if (key_len > 64U) {
        xgw_sha1(key, key_len, key_block);
    } else if (key_len > 0U) {
        memcpy(key_block, key, key_len);
    }

    uint8_t inner_pad[64];
    uint8_t outer_pad[64];
    for (size_t i = 0; i < 64U; i++) {
        inner_pad[i] = key_block[i] ^ 0x36U;
        outer_pad[i] = key_block[i] ^ 0x5cU;
    }

    xgw_sha1_ctx inner;
    uint8_t inner_digest[20];
    xgw_sha1_init(&inner);
    xgw_sha1_update(&inner, inner_pad, sizeof(inner_pad));
    xgw_sha1_update(&inner, message, message_len);
    xgw_sha1_final(&inner, inner_digest);

    xgw_sha1_ctx outer;
    xgw_sha1_init(&outer);
    xgw_sha1_update(&outer, outer_pad, sizeof(outer_pad));
    xgw_sha1_update(&outer, inner_digest, sizeof(inner_digest));
    xgw_sha1_final(&outer, output);
}
